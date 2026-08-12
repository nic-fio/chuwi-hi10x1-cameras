# 09 — Revisione avversariale pre-invio — 2026-08-11

> ## Stato: tutti i reperti tecnici sono stati corretti in giornata
>
> Restano aperti solo **B1** e **B2**, che sono di identita' e attribuzione e
> che nessuna quantita' di lavoro sul codice risolve.
>
> La **rivalidazione su hardware** e' stata fatta il **2026-08-12**, dopo il
> riavvio: 19 verifiche su 22 in `scripts/prova-completa.sh`, con le tre
> mancate spiegate in `docs/08-prova-hardware.md`. Ha prodotto un reperto
> nuovo, **A2**, che non e' dei nostri driver.
>
> | | Reperto | Stato |
> |---|---|---|
> | B1 | identita', `Signed-off-by`, `MODULE_AUTHOR` | **aperto** — solo l'autore puo' chiuderlo. `MODULE_AUTHOR` aggiunto col segnaposto |
> | B2 | copyright mancanti in `gc5035.c` | **corretto** — Bitland, Google e Intel aggiunti |
> | B3 | codice assistito da AI | **aperto** — decisione dell'autore |
> | A1 | NULL deref in `ipu6-isys` | **patch scritta**, `patches/wip/ipu6-fix/` |
> | A2 | NULL deref in `subdev_open()` | **trovato il 2026-08-12**, patch scritta, `patches/wip/subdev-fix/` |
> | M1 | `dev_err_probe()` fuori dalla probe | corretto |
> | M2 | `link_freq_bitmap` inutilizzato | **il reperto era mio errore**, vedi sotto |
> | M3 | ramo a 2 lane irraggiungibile | corretto |
> | M4 | nessuna identificazione in probe | corretto |
> | M5 | moltiplicazione a 32 bit | corretto |
> | M6 | commento che contraddice il codice | corretto |
> | M7 | `GC8034_VTS_OFFSET` inferito | commento riscritto, incertezza dichiarata |
> | M8 | `pm_runtime_get_if_active()` | corretto |
> | L1-L3 | `MODULE_AUTHOR`, dimensionamento handler, `u16`/`u8` | corretti |
> | L4 | riga `T:` in MAINTAINERS | **non e' un reperto**: `gc08a3` e `t4ka3` non ce l'hanno |
> | L5 | errori CSI-2 intermittenti | aperto, documentato |
>
> ### M2 era sbagliato, e vale la pena dire perche'
>
> Avevo scritto che il quinto parametro di `v4l2_ctrl_new_int_menu()` e' una
> maschera e che andava passato `~link_freq_bitmap`. **Non e' vero**: la
> maschera ce l'ha `v4l2_ctrl_new_std_menu()`, mentre `int_menu` ha `def`,
> l'indice di default. Passare il complemento del bitmap avrebbe introdotto un
> bug vero al posto di uno immaginario. Me ne sono accorto verificando la firma
> prima di fidarmi della mia stessa proposta, e la modifica e' stata annullata.
>
> Il fondo del reperto resta ma e' molto piu' debole: il bitmap serve come
> parametro d'uscita di `v4l2_link_freq_to_bitmap()`, che e' la funzione che
> **valida** la frequenza contro quella del firmware. Con un menu a una voce
> non porta altra informazione, e `imx258` e `gc05a2` fanno esattamente come
> noi. Nessuna modifica.

Revisione condotta come se fosse quella di un maintainer di `linux-media`
deciso a respingere la serie. Ogni reperto ha file, riga, innesco, impatto e
proposta di correzione. Le aree controllate **senza** reperti sono elencate
lo stesso, con gli scenari considerati: un'area non citata sarebbe un'area non
guardata.

Oggetto: i sei commit su `/home/nicfio/linux` sopra `d58772d85` (mainline
7.2-rc7), esportati in `patches/wip/serie/`.

---

## 0. Materiale mancante

Quello che manca **davvero**, cioe' che impedisce di chiudere una domanda:

| Cosa | Perche' serve |
|---|---|
| **Kernel con KASAN, UBSAN, KCSAN, lockdep, KMEMLEAK** | il Debian 6.12 in esecuzione ha solo `SLUB_DEBUG` e `DEBUG_LIST`. Use-after-free, doppi free, corse e inversioni di lock **non sono stati cercati con gli strumenti che li trovano**, solo per ispezione |
| **Datasheet o register guide GalaxyCore** | i blob PLL, D-PHY e bias analogico restano non verificabili. `GC8034_VTS_OFFSET` e' inferito |
| **Consenso degli autori originali** | Bitland/Google/Intel per il GC5035, Rockchip per il GC8034. Bloccante, vedi B2 |
| **Identita' reale del firmatario** | senza, la serie non esiste. Vedi B1 |
| **Un secondo esemplare di hardware** | tutto e' stato misurato su una macchina sola. I quirk per macchina sono la norma su IPU6 |
| **Suspend/resume di sistema** | non provato: su questo tablet un S3 fallito costa un riavvio senza rete di sicurezza |
| **Fault injection su I2C** | nessun modo semplice di iniettare errori sul bus senza `CONFIG_FAULT_INJECTION` |

Non manca invece nulla di **statico**: sorgenti, Kconfig, Makefile, MAINTAINERS,
binding YAML, DSDT decompilata, NVS ACPI, log di build e di test sono tutti in
questo repository.

---

## 1. Inventario

Sei commit, quattro file di codice.

| Commit | File | Cosa |
|---|---|---|
| 0001 | `Documentation/.../galaxycore,gc5035.yaml` | binding |
| 0002 | `drivers/media/i2c/gc5035.c` (1300 righe) + Kconfig, Makefile, MAINTAINERS | driver frontale |
| 0003 | `Documentation/.../galaxycore,gc8034.yaml` | binding |
| 0004 | `drivers/media/i2c/gc8034.c` (1225 righe) + Kconfig, Makefile, MAINTAINERS | driver posteriore |
| 0005 | `drivers/media/pci/intel/ipu-bridge.c` | due voci in `ipu_supported_sensors[]` |
| 0006 | `drivers/platform/x86/intel/int3472/clk_and_regulator.c` | `.set_rate` per IMGCLKOUT |

Struttura comune ai due driver di sensore:

- **entry point**: `module_i2c_driver()`, match ACPI (`GCTI5035`/`GCTI8034`) e OF
- **probe**: clock -> fwnode -> regmap CCI 8 bit -> GPIO reset/powerdown
  (opzionali) -> tre regolatori bulk -> controlli -> media entity -> subdev ->
  runtime PM -> `v4l2_async_register_subdev_sensor()`
- **remove**: unregister, cleanup subdev, cleanup entity, free controlli,
  `pm_runtime_disable()`, power off se non gia' sospeso
- **PM**: solo runtime, `DEFINE_RUNTIME_DEV_PM_OPS`, autosuspend 1000 ms.
  Nessun `.suspend`/`.resume` di sistema: li copre il runtime PM
- **niente interrupt, niente workqueue, niente kthread, niente timer, niente
  DMA, niente firmware, niente IOMMU.** Il driver e' interamente sincrono e
  guidato dall'ioctl
- **lock**: uno solo. `sd.state_lock` e' impostato a `ctrls.lock`, quindi il
  lock dello stato del subdev **e'** il lock del control handler. E' la ragione
  per cui `__v4l2_ctrl_modify_range()` (variante senza lock) e' corretta dentro
  `set_format`, e per cui `s_ctrl` puo' leggere `cur_mode` senza altro
- **risorse**: tutte `devm_` tranne il control handler e la media entity, che
  sono liberati a mano nei percorsi d'errore e in `remove()`

---

## 2. Bloccanti per l'invio

### B1 — La serie non e' firmabile allo stato attuale

`MAINTAINERS:10798` e `:10805` dicono `M: TODO Nome Cognome <email@reale>`.
`gc5035.c:5` e `gc8034.c:6` dicono `Copyright (C) 2026 <TODO: real name and
email before upstream submission>`. Nessun `Signed-off-by` in nessuno dei sei
commit, nessun `MODULE_AUTHOR` in nessuno dei due driver.

**Impatto**: la serie viene scartata prima di essere letta. Il `Signed-off-by`
e' una dichiarazione legale (DCO) e deve essere di una persona reale.

**Non e' un difetto da correggere qui**: e' l'unica cosa che il progetto ha
sempre saputo di non poter chiudere da solo. Va sciolta prima di tutto il resto.

### B2 — `gc5035.c` non riporta il copyright degli autori da cui prende le tabelle

`gc5035.c:13-17` dichiara **in prosa** che le tabelle vengono dalla serie
ChromeOS di Tomasz Figa, poi portata nel tree `ipu6-drivers` di Intel con
copyright Bitland Inc., Google LLC e Intel Corporation. Ma nel blocco di
copyright del file **c'e' una sola riga**, quella con il `TODO`.

Confronto interno: `gc8034.c:5` la riga la mette —
`Copyright (C) 2017 Fuzhou Rockchip Electronics Co., Ltd.`. I due file trattano
lo stesso problema in due modi diversi, e uno dei due e' sbagliato.

**Impatto**: e' una violazione di attribuzione GPL-2.0, non una svista di
stile. Il codice e' 161+162 righe di tabelle riprodotte verbatim.

**Correzione**: aggiungere le righe di copyright degli autori originali e i
tag `Co-developed-by:`/`Signed-off-by:` che quegli autori accetteranno di dare.
Fino ad allora la 0002 non e' inviabile, indipendentemente da quanto sia
corretta tecnicamente.

### B3 — Codice assistito da AI: da dichiarare, non da nascondere

Verificato: i sei commit della serie **non** contengono trailer
`Co-Authored-By` (i commit del repository di progetto si', ma quelli restano
qui e non vanno upstream). Resta la sostanza: parte del codice e dei commenti
e' stata scritta con assistenza automatica.

Un trailer `Co-developed-by:` per un'AI **non e' valido**: il DCO presuppone
una persona che possa fare quella dichiarazione. La responsabilita' e' per
intero di chi firma.

**[VERIFY]** la policy corrente: `Documentation/process/submitting-patches.rst`
e le eventuali indicazioni specifiche di `linux-media` al momento dell'invio.
La regola prudente e' che il firmatario abbia letto e capito ogni riga, e sia
in grado di difenderla in review — che e' esattamente cio' che i revisori
verificheranno comunque.

---

## 3. Reperti ad alta severita'

### A1 — NULL pointer dereference in `ipu6-isys`, presente in mainline

**Non e' un difetto di questi driver.** E' un difetto di mainline che questi
driver rendono raggiungibile su questo hardware per la prima volta, ed e' stato
provocato per davvero durante questa revisione.

**Innesco**: fare `unbind` del driver di sensore mentre una cattura e' in corso.

```
echo i2c-GCTI5035:00 > /sys/bus/i2c/drivers/gc5035/unbind   # con lo stream attivo
```

**Esito osservato**, kernel Debian 6.12.86:

```
BUG: kernel NULL pointer dereference, address: 0000000000000020
RIP: 0010:ipu6_isys_csi2_disable_streams+0x3c/0x70 [intel_ipu6_isys]
Call Trace:
 v4l2_subdev_disable_streams+0x1b7/0x370 [videodev]
 ipu6_isys_video_set_streaming+0x20f/0x930 [intel_ipu6_isys]
 stop_streaming+0x102/0x110 [intel_ipu6_isys]
 __vb2_queue_cancel+0x2a/0x2d0 [videobuf2_common]
 vb2_core_queue_release+0x22/0x80 [videobuf2_common]
 _vb2_fop_release+0x58/0xb0 [videobuf2_v4l2]
 v4l2_release+0xbd/0xd0 [videodev]
 __fput+0xde/0x2a0
```

**Causa**, `drivers/media/pci/intel/ipu6/ipu6-isys-csi2.c:395-396`:

```c
remote_pad = media_pad_remote_pad_first(&sd->entity.pads[CSI2_PAD_SINK]);
remote_sd = media_entity_to_v4l2_subdev(remote_pad->entity);
```

`media_pad_remote_pad_first()` restituisce `NULL` quando il link non c'e' piu',
ed e' esattamente quello che succede dopo l'unbind del sensore. Il valore non
viene controllato.

La prova che la diagnosi e' giusta sta nell'indirizzo: `CR2 = 0x20`, e in
`struct media_pad` il campo `entity` sta a offset `0x20` (dopo
`struct media_gobj`). L'opcode che fallisce e' `4c 8b 68 20`, cioe'
`mov r13, [rax+0x20]` con `RAX = 0`.

**Lo stesso schema, non controllato, e' anche sul percorso di enable**, riga
358-359 dello stesso file.

**Presente in mainline 7.2-rc7**: verificato, il codice e' identico riga per
riga. Non e' un problema della 6.12 di Debian.

**Severita'**: crash del kernel. L'innesco richiede pero' `root` (scrivere in
`/sys/bus/i2c/drivers/*/unbind`), quindi non e' un problema di sicurezza per un
utente non privilegiato. Dopo l'oops il pipeline resta bloccato: un
`media-ctl` rimane in stato `D` dentro `subdev_do_ioctl_lock`, perche' il mutex
dello stato appartiene a un task morto. **Si recupera solo riavviando.**

**Correzione proposta** (due righe, sui due percorsi):

```c
	remote_pad = media_pad_remote_pad_first(&sd->entity.pads[CSI2_PAD_SINK]);
	if (!remote_pad)
		return -ENOLINK;
```

**Cosa farne**: e' materiale per una patch separata a `linux-media`, non per
questa serie. Va segnalato comunque, perche' chiunque provi a fare `unbind` di
un sensore IPU6 mentre streamma ottiene un oops, e con l'arrivo di questi due
driver quel "chiunque" diventa una categoria piu' popolata.

---

### A2 — NULL pointer dereference in `subdev_open()`, presente in mainline

> Trovato il **2026-08-12**, dopo un riavvio, alla prima esecuzione completa di
> `scripts/prova-completa.sh`. Non e' A1: cambia il puntatore, cambia il
> percorso, e soprattutto **cambia l'innesco**, che qui non richiede nessuno
> streaming in corso.

**Non e' un difetto di questi driver.** Come A1, e' di mainline, e questi
driver lo rendono raggiungibile su questo hardware.

**Innesco**: fare `unbind` del sensore mentre qualcuno apre il suo
`/dev/v4l-subdevN`. La prima volta **non e' stato provocato**: e' bastata la
sezione bind/unbind della prova, con `v4l_id` lanciato da udev sul nodo che
compariva e spariva.

```
BUG: kernel NULL pointer dereference, address: 0000000000000008
RIP: 0010:subdev_open+0x8a/0x190 [videodev]
CPU: 1 PID: 4697 Comm: v4l_id
Call Trace:
 v4l2_open+0xa9/0x100 [videodev]
 chrdev_open+0xb2/0x230
 do_dentry_open+0x14c/0x440
 vfs_open+0x2e/0xe0
 path_openat+0x82e/0x12d0
 do_sys_openat2+0xae/0xe0
 __x64_sys_openat+0x55/0xa0
```

**Quale puntatore, e come si sa.** Il kernel Debian non ha i simboli, quindi
il nome del campo viene dalla disassemblata di `videodev.ko`
(`data/oops-subdev-2026-08-12/02-subdev_open-disasm.txt`):

```
be83:  49 8b 85 98 00 00 00    mov  0x98(%r13),%rax      <- sd->v4l2_dev
be8a:  48 83 78 08 00          cmpq $0x0,0x8(%rax)       <- ->mdev, RAX = 0
```

`0x8` e' l'offset di `mdev` in `struct v4l2_device`, ed e' esattamente il
`CR2` dell'oops. Il puntatore nullo e' **`sd->v4l2_dev`**.

**Causa**, `drivers/media/v4l2-core/v4l2-device.c:279-291`:

```c
	sd->v4l2_dev = NULL;                    /* 279 */
	...
	media_device_unregister_entity(&sd->entity);   /* dorme */
	...
	if (sd->devnode)
		video_unregister_device(sd->devnode);   /* 291 */
```

Il nodo viene tolto **per ultimo**. Fra la riga 279 e la 291 esiste un
`/dev/v4l-subdevN` ancora apribile il cui `sd->v4l2_dev` e' gia' `NULL`, e
`subdev_open()` (`v4l2-subdev.c:115`) lo dereferenzia senza controllarlo. In
mezzo c'e' `media_device_unregister_entity()`, che dorme: la finestra non e'
di poche istruzioni.

**C'e' una seconda mina nella stessa riga.** `media_device_unregister_entity()`
azzera `sd->entity.graph_obj.mdev`, e la condizione e'
`sd->v4l2_dev->mdev && sd->entity.graph_obj.mdev->dev`: appena dopo
l'unregister dell'entita' il primo termine e' ancora vero e il secondo
dereferenzia `NULL`. Questa **non e' stata osservata**, e' stata letta.

**Riordinare non basta.** Togliere il nodo prima di azzerare i puntatori
stringe la finestra ma non la chiude: `v4l2_open()` rilascia `videodev_lock`
prima di chiamare `fops->open()` (`v4l2-dev.c:426-433`), quindi tutta
`v4l2_device_unregister_subdev()` puo' ancora infilarsi in mezzo. Il controllo
va messo in `subdev_open()`.

**Riproducibile a comando**: `scripts/riproduci-oops-subdev.sh`, quattro
processi che aprono ogni `/dev/v4l-subdev*` mentre il sensore viene
riagganciato in ciclo. **Riprodotto al ciclo 7.**

**Presente in mainline 7.2-rc7**: verificato, `v4l2-subdev.c:115` e
`v4l2-device.c:279-291` sono identici.

**Non e' stato verificato che nessuno l'abbia gia' segnalata, e non e' per
pigrizia.** Due ricerche sul web — una libera, una ristretta a
`lore.kernel.org`, `patchwork.kernel.org` e `patchwork.linuxtv.org` — non hanno
trovato niente di pertinente. Ma l'archivio vero non e' interrogabile da qui:
`lore.kernel.org` sta dietro ad **Anubis**, che chiede una proof-of-work al
browser e rifiuta sia `curl` sia il recupero automatico della pagina. E "non
trovato da un motore di ricerca" non e' "non esiste".

Serve un browser, trenta secondi, questo indirizzo:

```
https://lore.kernel.org/linux-media/?q=subdev_open+v4l2_dev
```

Se non esce niente di simile, la patch e' nuova e si invia.

**Severita'**: crash del kernel. La macchina resta in piedi — l'oops uccide
chi apriva, non il kernel, e dopo due colpi non c'e' stato nessun task in
stato `D` — ma **ogni colpo perde per sempre un minor**: dopo i due oops di
oggi `/dev/v4l-subdev4` e `/dev/v4l-subdev5` non esistono piu' e il GC5035 e'
finito su `v4l-subdev7` (`data/oops-subdev-2026-08-12/03-nodi.txt`). Il
`video_device` non viene mai rilasciato perche' il riferimento preso da
`video_get()` resta appeso al processo morto.

Chi fa l'`unbind` deve essere root, ma **chi apre no**: basta essere nel gruppo
`video`. E l'`unbind` non e' un gesto esotico — un `rmmod` del driver di
sensore fa la stessa cosa, con udev che apre il nodo per conto suo.

**Correzione proposta**: `patches/wip/subdev-fix/`, testata in compilazione
contro mainline 7.2-rc7. Legge `sd->v4l2_dev` una volta sola, rifiuta con
`-ENODEV` se e' `NULL`, e fa lo stesso per l'`mdev` dell'entita'.

**Il `Fixes:` c'e'**, ed e' stato determinato senza clone completo:

```
Fixes: 61f5db549dde ("[media] v4l: Make v4l2_subdev inherit from media_entity")
```

`git blame` qui non serve — il clone e' shallow e si ferma al commit innestato.
La strada e' stata la blame di GitHub via `gh api graphql`, risalita di padre in
padre: `master` da' `218bf10e39ed` (2019), il cui padre da' `61f5db549dde`
(2011-03-22), e il padre di **quello** ha un `subdev_open()` che
`sd->v4l2_dev` non lo tocca proprio. Verificato leggendo il diff: e' il commit
che introduce `if (sd->v4l2_dev->mdev) {`.

La seconda mina ha un'altra data. `sd->entity.graph_obj.mdev->dev` senza
controllo arriva con `218bf10e39ed` ("media: v4l2-subdev: handle module
refcounting here"), che sposta il conteggio dei riferimenti al modulo dentro
`v4l2-subdev.c`. Prima faceva la stessa dereferenza `media_entity_get()`, quindi
non e' una regressione di quel commit: e' lo stesso difetto che cambia casa. Il
`Fixes:` resta uno solo, quello del 2011, ma nel corpo della patch e' citato
anche l'altro.

`subdev_close()` **non** e' affetto: dal 2019 usa `subdev_fh->owner` e non
tocca piu' `sd->v4l2_dev`.

**Cosa manca prima di inviarla**: solo il controllo sull'archivio.

**Cosa farne**: patch separata a `linux-media`, come A1 e insieme ad A1. Sono
due crash indipendenti nello stesso scenario — il sensore che se ne va mentre
qualcuno lo sta usando — e nessuno dei due deve aspettare la serie dei driver.

---

## 4. Reperti a severita' media

### M1 — `dev_err_probe()` chiamato fuori dal contesto di probe

`gc5035.c:590, 596, 902` — `gc8034.c` corrispondenti.

`gc5035_power_on()` e `gc5035_power_off()` sono callback di runtime PM;
`gc5035_identify_module()` e' chiamata da `enable_streams()`. Nessuna delle
tre e' in probe. `dev_err_probe()` registra il motivo del deferred probe e ha
una semantica legata alla probe: usarla altrove e' scorretto e i revisori lo
segnalano.

**Correzione**: `dev_err()` in tutti e tre i casi, e ritornare il codice
d'errore separatamente.

### M2 — `link_freq_bitmap` calcolato e mai usato

`gc5035.c:172` (campo), `:1046` (assegnato da `v4l2_link_freq_to_bitmap()`),
mai letto. In `init_controls` il parametro `mask` di
`v4l2_ctrl_new_int_menu()` e' `0` invece di `~link_freq_bitmap`, e il default
e' `0` invece di `__ffs(bitmap)`.

Oggi e' innocuo perche' il menu ha **una** voce: se la validazione passa il
bitmap vale per forza 1. Ma e' un campo morto in una struct, e diventerebbe un
bug il giorno in cui si aggiunge una seconda frequenza.

**Correzione**: passare `~gc5035->link_freq_bitmap` come mask e
`__ffs(gc5035->link_freq_bitmap)` come default, come fanno i driver mainline
con piu' di una frequenza.

### M3 — Codice morto nel GC8034: il ramo a 2 lane

`gc8034.c:61` definisce `GC8034_STREAM_ON_2LANE`, e `:888-890` sceglie fra i
due valori in base a `data_lanes`. Ma `gc8034_parse_fwnode()` **rifiuta**
qualunque conteggio diverso da `GC8034_DATA_LANES` (4), quindi il ramo a 2 lane
e' irraggiungibile.

**Impatto**: un revisore chiede o di togliere il codice morto o di supportare
davvero le 2 lane. La seconda strada e' onesta ma non testabile qui: nessuna
tabella registri a 2 lane e' stata importata.

**Correzione**: togliere la costante e il ternario, scrivere direttamente il
valore a 4 lane, e dire nel commento che le 2 lane non sono supportate perche'
le tabelle sono a 4.

### M4 — Il chip non viene identificato in probe

`gc5035_probe()` non accende mai il sensore e non legge mai il chip ID:
`identify_module()` viene chiamata al primo `enable_streams()`. Il bind quindi
**riesce anche se il sensore non c'e'** o e' un altro modello, e l'errore
compare solo alla prima cattura.

E' una scelta difendibile (evita di accendere l'hardware a ogni boot) e c'e'
del precedente, ma va **argomentata nel messaggio di commit**, perche' e' la
prima domanda che arriva.

**[VERIFY]** cosa fanno i peer piu' vicini (`ov2740`, `t4ka3`, `gc05a2`,
`gc08a3`) prima di scegliere: se la maggioranza identifica in probe, conviene
allinearsi invece di spiegare.

### M5 — Moltiplicazione a 32 bit su architetture a 32 bit

`gc5035.c:1166`:

```c
gc5035->link_freq_menu[0] = freq * GC5035_LINK_FREQ_MULTIPLIER;
```

`freq` e' `unsigned long`, quindi 32 bit su i386/ARM32. Il prodotto e'
calcolato in `unsigned long` **prima** di essere promosso a `s64`. Con i clock
reali (19,2 e 24 MHz) non trabocca, ma il tipo di destinazione e' a 64 bit e il
calcolo no: e' un troncamento silenzioso in attesa di un clock piu' alto.

Stesso schema in `gc8034.c` sul prodotto con `xclk_rate`.

**Correzione**: `(s64)freq * GC5035_LINK_FREQ_MULTIPLIER`, oppure tenere la
frequenza in `u64` fin dall'inizio.

### M6 — Commento che contraddice il codice

`gc8034.c:153-157`: «*The BSP only uses the first 7 indices... its last two
entries are dead code there. **They are kept here** because the sensor accepts
them*». Ma `gc8034_again_level[]` ha **sette** voci: le ultime due non sono
tenute affatto.

**Correzione**: riscrivere il commento dicendo che le ultime due voci del BSP
non sono state importate perche' non verificabili.

### M7 — `GC8034_VTS_OFFSET` e' inferito e la sua aritmetica non torna

`gc8034.c:68-78`. Il commento afferma «*reg = 16 gives VTS = 2500 = 0x09c4,
consistent with the vts_def declared below*», ma il `vts_def` dichiarato e'
**2496**, che corrisponde a reg = 12, non 16.

Peggio: la costante **non e' validabile con le misure fatte**. Un errore di 4
righe su 2496 sposta il frame rate dello 0,16%, sotto il rumore della misura, e
la variazione di VBLANK non lo discrimina perche' l'errore e' costante e si
semplifica. Il valore resta un'inferenza sui default del blob Rockchip.

**Correzione**: rendere il commento coerente e dire apertamente che l'offset e'
dedotto dai default del BSP e non misurato. Un revisore preferisce
un'incertezza dichiarata a un'aritmetica che non torna.

### M8 — `pm_runtime_get_if_active()` puo' restituire un errore

`gc5035.c:857`, `gc8034.c:806`:

```c
if (!pm_runtime_get_if_active(gc5035->dev))
	return 0;
```

La funzione restituisce 1 se ha preso il riferimento, 0 se il device non e'
attivo e **`-EINVAL` se il runtime PM e' disabilitato**. Con `-EINVAL` il test
`!x` e' falso, quindi il codice tocca l'hardware **e** chiama
`pm_runtime_put_autosuspend()` decrementando un contatore mai incrementato.

**Attenuante forte**: e' l'idioma della maggioranza in `drivers/media/i2c`
(`gc05a2`, `gc08a3`, `imx283`, `ov6211`, `s5kjn1`, `s5k3m5` fanno tutti cosi').
`ov64a40:3280` invece salva il valore e lo controlla come si deve.

**Correzione**: `if (pm_runtime_get_if_active(dev) <= 0) return 0;`. Costa
nulla ed e' giusto.

---

## 5. Reperti minori e di stile

| | File:riga | Cosa |
|---|---|---|
| L1 | entrambi, in coda | **`MODULE_AUTHOR` assente.** `gc05a2` e `gc08a3` ce l'hanno. Si chiude insieme a B1 |
| L2 | `gc5035.c:1061` | `v4l2_ctrl_handler_init(hdlr, 8)` ma i controlli sono 9 (7 piu' i 2 da fwnode). E' solo un suggerimento di dimensionamento, non un limite, ma tanto vale che sia giusto |
| L3 | `gc8034.c:181` | `gc8034_agc_bias_reg` e' `u16[]` con valori tutti `<= 0xff` |
| L4 | `MAINTAINERS:10797` | manca la riga `T:` col tree, presente in molte voci di `linux-media`. **[VERIFY]** la convenzione corrente |
| L5 | — | errori CSI-2 intermittenti sul solo GC5035, documentati in `docs/08-prova-hardware.md`. Non spiegati. Le immagini restano integre |

---

## 6. Aree controllate senza reperti

Questa sezione esiste perche' «non ho trovato niente» e «non ho guardato» si
scrivono nello stesso modo.

### Strumenti, tutti verificati come realmente eseguiti

| Strumento | Esito | Come ho verificato che girasse davvero |
|---|---|---|
| `checkpatch --strict --max-line-length=80` | pulito sui due `.c` | messaggio esplicito «ready for submission» |
| `checkpatch --strict` sulle 6 patch | solo `Missing Signed-off-by` (voluto) e il falso positivo noto su MAINTAINERS nei binding | — |
| `make W=1` | nessun warning | — |
| `sparse` v0.6.5-rc1, `C=1 W=1` | pulito | la sparse di Debian e' troppo vecchia e il kernel la **scarta proseguendo**: usata quella costruita a mano |
| `smatch` 0.6.4 | nessun warning | la riga `CHECK` compare nel log di build, e su un caso di prova scritto apposta smatch segnala correttamente un deref-before-check |
| `coccinelle` 1.3, 69 script (`free`, `locks`, `null`, `api`, `api/alloc`, `misc`, `iterators`) | nessun reperto | **primo tentativo invalido**: senza `-D report` le regole non si attivano e spatch stampa «No rules apply». Rieseguito con `-D report` |
| `make dt_binding_check` + `yamllint` | puliti su entrambi i binding | — |
| `v4l2-compliance` | 45/46 su entrambi | l'unico fallimento sono gli eventi sui controlli, assenti anche in `gc05a2`, `gc08a3`, `ov2740`, `ov08x40`, `t4ka3` |

### Scenari esaminati a mano

- **Ordine di distruzione in `remove()`**: unregister -> cleanup subdev ->
  cleanup entity -> free controlli -> `pm_runtime_disable()` -> power off ->
  `set_suspended()`. Corretto: `sd.state_lock` punta dentro il control handler,
  quindi lo stato del subdev **deve** morire prima dei controlli, e cosi' e'.
- **Percorsi d'errore di `probe()`**: le tre etichette (`err_rpm`,
  `err_media_entity_cleanup`, `err_ctrl_handler_free`) sono in cascata e
  liberano nell'ordine inverso. Tutto il resto e' `devm_`. Unica asimmetria:
  `err_rpm` non chiama `pm_runtime_set_suspended()` mentre `remove()` lo fa —
  innocuo, perche' su quel percorso il device non e' mai stato risvegliato.
- **Nessun `kfree`, `kmalloc`, `kzalloc` a mano**: solo `devm_kzalloc` in probe.
  Niente doppi free, niente use-after-free possibili per costruzione. Nessuna
  lista, nessun refcount proprio, nessun `get`/`put` sbilanciato oltre a M8.
- **Locking**: un solo mutex, `ctrls.lock`, usato come `state_lock`. Tutte le
  chiamate a `__v4l2_ctrl_modify_range()` avvengono da `set_format` o da
  `s_ctrl`, entrambe invocate col lock gia' preso. Nessuna acquisizione
  annidata, quindi nessuna inversione possibile. Nessun contesto atomico:
  tutte le operazioni possono dormire e nessuna e' chiamata da interrupt.
- **Paginazione dei registri** — il rischio piu' insidioso di questi due chip,
  perche' scrivere sulla pagina sbagliata non da' errore. Verificato che:
  `gc5035_init_regs` e la mode table finiscono con `{0xfe, 0x00}`, quindi il
  `__v4l2_ctrl_handler_setup()` che segue scrive esposizione e guadagno in
  pagina 0; `gc5035_test_pattern()` va in pagina 1 e **ritorna** in pagina 0;
  la sequenza di bias del GC8034 contiene `0xfe` tre volte e finisce anch'essa
  a pagina 0. Nessun percorso lascia il chip su una pagina inattesa.
- **Overflow aritmetici**: `gc8034_to_pixel_rate()` calcola
  `4272 * 2496 * 30 * 19 200 000` = 6,1e15, dentro `u64` con quattro ordini di
  grandezza di margine; il divisore di `div_u64()` e' 24e6, dentro `u32`. Il
  solo problema e' M5.
- **Underflow del registro di blanking del GC8034**:
  `height + vblank - 2484` con `height` 2448 e `vblank` minimo 48 da' 12. Il
  minimo e' imposto dal range del controllo, quindi non e' raggiungibile un
  valore negativo che diventerebbe un `u32` enorme. Vale la pena dirlo perche'
  l'espressione **e'** in aritmetica senza segno.
- **Indici delle tabelle di guadagno**: i due cicli partono dall'ultimo indice
  e si fermano a `idx > 0`, quindi `idx` resta sempre in `[0, N-1]` anche con
  un `a_gain` piu' piccolo della prima voce. Sul GC8034 uno `static_assert()`
  lega la lunghezza di `agc_bias` a quella di `again_level`, quindi
  `agc_bias[idx]` non puo' uscire dall'array. Il range del controllo e'
  esattamente `[first, last]` in entrambi i driver.
- **`s_ctrl` con controlli read-only**: il ramo `default:` restituisce
  `-EINVAL`, il che romperebbe `enable_streams` se venisse chiamato per
  `LINK_FREQ`, `PIXEL_RATE`, `HBLANK` o le proprieta' fwnode. Non succede:
  `__v4l2_ctrl_handler_setup()` salta i controlli `V4L2_CTRL_FLAG_READ_ONLY`, e
  tutti quelli elencati hanno quel flag.
- **`init_state` durante `v4l2_subdev_init_finalize()`**: passa
  `V4L2_SUBDEV_FORMAT_TRY`, quindi non tocca `cur_mode` ne' i controlli. Se
  toccasse i controlli lo farebbe prima che `pm_runtime_enable()` sia stata
  chiamata.
- **Input dal firmware trattato come ostile**: il conteggio di lane dell'ACPI e'
  validato contro una costante e la probe fallisce se non combacia; la link
  frequency dichiarata e' validata da `v4l2_link_freq_to_bitmap()` contro
  quella derivata dal clock; un clock a rate zero fa fallire la probe. La DSDT
  di questa macchina, se mentisse, non porterebbe oltre un rifiuto di bind.
- **Dati dal sensore**: il driver legge **un solo** registro, il chip ID, e lo
  confronta con una costante. Nessun buffer riempito dall'hardware, nessuna
  lunghezza presa dal dispositivo, nessuna OTP letta. La superficie d'attacco
  lato I2C e' quanto piu' piccola possa essere.
- **ioctl e memoria utente**: il driver non ne implementa nessuno di proprio.
  Passa tutto al core V4L2. Nessun `copy_to_user`/`copy_from_user`, nessun
  `.compat_ioctl32`, nessuna struct esposta a userspace.
- **Nessun DMA, nessuna mappatura di memoria, nessun IOMMU** nel driver di
  sensore: i buffer sono dell'ISYS, non suoi.
- **`bind`/`unbind` a riposo**: dieci cicli consecutivi sul GC5035, nessun
  messaggio d'errore, driver riagganciato ogni volta, nessuna perdita
  osservabile di riferimenti.

  > **Smentito il 2026-08-12, ed e' istruttivo.** Rifatti i dieci cicli su
  > entrambi i sensori con udev vivo, il kernel e' andato in oops: **A2**.
  > "A riposo" voleva dire "senza cattura in corso", ma la macchina non era a
  > riposo — c'era `v4l_id` che apriva il nodo. La perdita di riferimenti
  > c'era, e non era osservabile solo perche' guardavo la cosa sbagliata: si
  > vede nei minor di `/dev/v4l-subdev` che non tornano piu'. Quello che
  > questa riga provava davvero era che dieci cicli **senza nessuno che apra
  > il nodo** vanno bene.
- **Ricaricamento dei moduli**: piu' cicli completi di
  `rmmod`/`insmod`/`modprobe` della catena `ipu-bridge` + IPU6 + sensori
  durante la giornata, senza errori.

### Cosa resta scoperto, e va detto

1. **KASAN, UBSAN, KCSAN, lockdep, KMEMLEAK non sono mai stati eseguiti.** Il
   kernel a disposizione non li ha compilati. Tutto quello che scrivo sopra su
   memoria e locking e' ispezione, non strumentazione. E' il buco piu' grande
   di questa revisione.
2. **Suspend/resume di sistema non provato.**
3. **`unbind` durante lo streaming**: provato una volta sola, ha prodotto A1.
   Non ripetuto, perche' lascia la macchina da riavviare. L'`unbind` con il
   nodo aperto ma **senza** streaming e' invece stato ripetuto e riprodotto a
   comando: e' A2, e non lascia la macchina da riavviare.
4. **Il VCM `dw9714` non e' mai stato esercitato**: viene istanziato, il fuoco
   non e' stato mosso.
5. **Nessun test di concorrenza**: due processi che aprono lo stesso subdev,
   `set_format` mentre streamma, controlli scritti da due thread.
6. **Una macchina sola.**

---

## 7. Giudizio

**Inviabile domani: no.** Non per ragioni tecniche — per B1 e B2, che sono di
identita' e attribuzione, e che nessuna quantita' di lavoro sul codice risolve.

**Il codice regge?** Con le informazioni disponibili non ho trovato difetti
bloccanti nei due driver: nessun leak, nessun use-after-free, nessun doppio
free, nessuna inversione di lock, nessun overflow raggiungibile, nessun input
non validato. Gli otto reperti di severita' media sono tutti correzioni
circoscritte, la piu' invasiva delle quali tocca cinque righe.

**Rischi residui, in ordine:**

1. Niente KASAN/lockdep: la mia fiducia sulla memoria e sul locking vale quanto
   un'ispezione attenta, non piu'.
2. I blob PLL, D-PHY e bias restano non documentati. Funzionano; non si sa
   perche'.
3. `GC8034_VTS_OFFSET` e' inferito e non validabile con gli strumenti a
   disposizione.
4. Una macchina sola, un solo esemplare di ciascun sensore.
5. Gli errori CSI-2 intermittenti del GC5035 non hanno una spiegazione.

**L'ordine in cui affronterei le cose:** B1 e B2 prima di tutto, perche'
determinano se il resto ha senso. Poi M1, M2, M3, M5, M6, M7, M8 e L1-L3, che
sono mezza giornata in tutto. A1 e' una patch separata a `linux-media` e non
va tenuta in ostaggio dalla serie. KASAN e lockdep richiedono un kernel
apposta, ed e' il lavoro che darebbe piu' informazione per unita' di tempo.

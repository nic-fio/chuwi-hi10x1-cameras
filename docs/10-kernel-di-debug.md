# 10 — Il kernel di debug: come avviarlo e cosa cercarci

Serve a chiudere il buco piu' grande della revisione pre-invio: il kernel
Debian in uso non ha **nessuno** strumento di analisi dinamica, quindi tutto
quello che si e' detto su memoria e locking dei due driver e' ispezione, non
misura. Questo kernel li ha tutti.

```bash
./scripts/build-kernel.sh --debug        # non serve root, ~1-2 ore
```

**Gia' costruito il 2026-08-11 sera.** Non serve rifarlo:

| | |
|---|---|
| Versione | `7.2.0-rc7-intelcam-debug-gc61216fb5a24` |
| Immagine | `/home/nicfio/linux/arch/x86/boot/bzImage`, 29 MB |
| Avviabile da EFI | si', entry point handoff a 32 e 64 bit verificati |
| Driver | `gc5035.ko` e `gc8034.ko` costruiti **in albero**, non fuori |
| Config archiviata | `config/intelcam-7.2.0-rc7-debug.config` |

Contiene i due driver nella versione finale, con tutte le correzioni della
revisione. **Non** contiene la patch a `ipu6-isys`: quella sta su un branch a
parte, `ipu6-npd-fix`, perche' e' un invio separato.

Cosa aggiunge, e cosa trova ciascuno:

| Strumento | Trova |
|---|---|
| `KASAN` (generic, inline) | use-after-free, doppi free, overflow di slab e di stack |
| `UBSAN` | overflow di interi, shift fuori range, indici fuori dagli array |
| `PROVE_LOCKING` (lockdep) | inversioni di lock, ricorsioni, lock presi in contesto sbagliato |
| `DEBUG_ATOMIC_SLEEP` | dormire dove non si puo' — `usleep_range` in atomico |
| `DEBUG_KMEMLEAK` | memoria allocata e mai liberata, che KASAN non vede |
| `DEBUG_OBJECTS` | oggetti usati dopo la distruzione: timer, work, mutex |
| `DETECT_HUNG_TASK` | task bloccati piu' di 120 s, come quello lasciato dall'oops |

`PANIC_ON_OOPS` e' **disattivato apposta**: se qualcosa esplode, serve che la
macchina resti in piedi abbastanza da leggere il journal.

## Primo avvio, 2026-08-12 ore 09:03 — mancava il bus I2C

Il kernel e' partito, gli strumenti erano tutti attivi, ma `prova-completa.sh`
ha dato **6 superate e 8 fallite**: nessuno dei due sensori si e' agganciato.

Non e' un difetto dei driver. Manca il bus su cui vivono.

```
$ ls /sys/bus/i2c/devices/    ->  solo SMBus e i bus della grafica i915
$ ls /sys/bus/acpi/devices/GCTI*  ->  ci sono, status=15, physical_node NESSUNO
```

I due controller I2C dei sensori, su Alder Lake-N, sono dispositivi **PCI**
(`00:15.0`–`00:15.3`), non platform. A vederli e a creare il platform device
su cui `i2c-designware-platform` si aggancia e' `intel-lpss-pci`, cioe'
`CONFIG_MFD_INTEL_LPSS_PCI`. Nel config di debug era `is not set`.

Risultato a catena: nessun adattatore designware → nessun client I2C per
`GCTI5035:00` e `GCTI8034:00` → i driver restano caricati e inutilizzati.
`ipu-bridge` intanto stampa `Connected 2 cameras`, perche' lui legge la ACPI e
non il bus: e' quello che rende l'errore poco evidente a prima vista.

La verifica dei simboli in `build-kernel.sh` non l'ha intercettato perche'
controllava `I2C_DESIGNWARE_PLATFORM` — il driver — e non chi gli fornisce il
dispositivo. **Corretto il 2026-08-12**: ora lo script forza `X86_INTEL_LPSS`,
`MFD_INTEL_LPSS`, `MFD_INTEL_LPSS_PCI`, `MFD_INTEL_LPSS_ACPI` e `I2C_CHARDEV`
built-in, e `MFD_INTEL_LPSS_PCI` e `I2C_CHARDEV` sono nella lista obbligatoria.

Due dettagli minori emersi nella stessa sessione:

- `I2C_CHARDEV` era `is not set`, quindi `i2cget` non avrebbe potuto leggere il
  chip ID nemmeno col bus a posto
- `prova-completa.sh` ha provato a lanciare `build-6.12/carica.sh`, che fa
  `insmod` dei moduli fuori albero compilati per il 6.12; il kernel li ha
  rifiutati (`section size must match`). Innocuo, ma qui i moduli sono in
  albero e quel ramo dello script non andrebbe percorso

## ESITO — 2026-08-12, ore 09:13-09:35, secondo avvio

**Il buco della revisione e' chiuso: gli strumenti sono girati davvero.** Il
bus I2C c'era (`i2c-1` e `i2c-2`, designware su PCI), entrambi i sensori
agganciati, chip ID `0x50 0x35` e `0x80 0x44` letti da userspace.

Materiale grezzo in `data/kasan-20260812-0915/`.

### Cosa dicono gli strumenti dei nostri due driver

| Strumento | Esito su `gc5035` e `gc8034` |
|---|---|
| KASAN | nessun reperto |
| UBSAN | nessun reperto |
| KMEMLEAK | nessuna perdita attribuibile ai due driver |
| lockdep | nessun reperto (ma vedi il limite piu' sotto) |
| DETECT_HUNG_TASK | nessun task bloccato |
| `v4l2-compliance` | 46 superate, 0 fallite, su entrambi |
| Frame rate | scarto 0.01% e 0.00% dal dichiarato |
| Guadagno analogico | scarto 0.3% e 1.3% dal richiesto |

`prova-completa.sh`: **21 verifiche su 21**.

**La correzione A2 regge alla prova.** Il riproduttore
`riproduci-oops-subdev.sh` ha fatto 150 cicli con 4 apritori senza oops e
senza perdere un solo minor: `/dev/v4l-subdev0..5` sono rimasti contigui.
Prima della patch A2 si riproduceva **da solo**, con dieci cicli e udev vivo.

### Tre difetti nuovi, tutti di monte, nessuno nostro

**C1 — use-after-free in `__media_pipeline_stop()`.** Il reperto piu' grosso,
e lo trova solo KASAN.

```
BUG: KASAN: slab-use-after-free in __media_pipeline_stop+0x2b2/0x360
Write of size 8 at addr ffff88811bf1a9f8 by task v4l2-ctl
 stop_streaming+0x2a9/0x4c0 [intel_ipu6_isys]
 __vb2_queue_cancel  ->  vb2_core_queue_release  ->  v4l2_release  ->  __fput
```

**Innesco**: `unbind` del sensore mentre lo streaming e' in corso. E' lo
scenario di A1, ma il punto e' un altro e la patch A1 **non** lo copre.

La scrittura e' `mc-entity.c:946`, cioe' `ppad->pad->pipe = NULL` dentro
`list_for_each_entry(ppad, &pipe->pads, list)`. Verificato sulla disassemblata,
non dedotto:

```
mov  0x18(%rbx),%r14        <- r14 = ppad->pad
lea  0x38(%r14),%rdi        <- &pad->pipe
call __asan_report_store8_noabort
movq $0x0,0x38(%r14)        <- ppad->pad->pipe = NULL
```

`pipe->pads` elenca ancora un `media_pad` del sub-device che l'`unbind` ha
gia' liberato, e la chiusura del pipeline ci scrive dentro. Che sia memoria
davvero riciclata lo dicono le tracce di KASAN: l'oggetto risulta allocato da
`alloc_pipe_info()` e liberato da `free_pipe_info()`, cioe' lo slab era gia'
tornato in giro come pipe di un altro processo.

**C2 — `ipu6_isys_fw_pin_cfg()` legge lo stato del sub-device senza il lock.**
Tre asserzioni di lockdep, 27 volte ciascuna:

```
WARNING: include/media/v4l2-subdev.h:1886 at ipu6_isys_video_set_streaming
WARNING: drivers/media/v4l2-core/v4l2-subdev.c:1776 at __v4l2_subdev_state_get_format
WARNING: drivers/media/v4l2-core/v4l2-subdev.c:1810 at __v4l2_subdev_state_get_crop
```

In `ipu6_isys_video_set_streaming()` (`ipu6-isys-video.c`): prende il lock alla
riga 1005, **lo rilascia alla 1010**, poi alla 1029 chiama
`start_stream_firmware()` → `ipu6_isys_fw_pin_cfg()`, che usa la variante
`v4l2_subdev_get_locked_active_state()` — quella che pretende il lock ancora
tenuto. Legge `format` e `crop` scoperti: una `S_FMT` concorrente sul CSI-2
puo' cambiarli sotto, e il firmware riceve una configurazione che non
corrisponde a quella impostata.

**C3 — perdita di memoria in `int3472`, 272 volte.** KMEMLEAK ha riportato 272
oggetti persi e sono **tutti lo stesso difetto**: 137 da
`skl_int3472_clk_unprepare`, 135 da `skl_int3472_clk_prepare`.

`skl_int3472_enable_clk()` (`clk_and_regulator.c`) chiama `acpi_evaluate_dsm()`
e ne **scarta il valore di ritorno**, che invece il chiamante deve liberare con
`ACPI_FREE()`. Sono 32 byte a ogni accensione e a ogni spegnimento del clock:
non si stabilizza mai, cresce a ogni cattura.

**Non e' della nostra bozza** `int3472: Allow selecting the IMGCLKOUT
frequency`: quella cambia solo il valore di `args[2]`. La chiamata col ritorno
scartato c'era gia' in `HEAD~1`, verificato con `git show`.

### Le tre patch, scritte il 2026-08-12 pomeriggio

| Reperto | Cartella | Correzione |
|---|---|---|
| C1 | `patches/wip/mc-pipeline-fix/` | i pad dell'entity vengono staccati dalla pipeline in `__media_device_unregister_entity()`, prima di essere distrutti |
| C2 | `patches/wip/ipu6-lock-fix/` | `fw_pin_cfg()` prende il lock attorno alle due letture, come gia' fa `link_validate()` nello stesso file |
| C3 | `patches/wip/int3472-leak-fix/` | `ACPI_FREE()` sul ritorno di `acpi_evaluate_dsm()` |

Tutte e tre compilano pulite, `checkpatch --strict` da' **0 errori**, e i
`Fixes:` sono stati verificati confrontando il diff del commit incriminato con
la riga che introduce il difetto — non dedotti dal titolo:

```
C1  ae219872834a ("media: mc: entity: Rewrite media_pipeline_start()")
C2  58410f62e25d ("media: ipu6: Drop custom functions to obtain sd state information")
C3  e4543de8b6ff ("platform/x86: int3472: Evaluate device's _DSM method to control imaging clock")
```

**Sono applicate non committate** in `/home/nicfio/linux`, accanto ad A1 e A2 e
per lo stesso motivo: committarle cambierebbe la stringa di versione e
costringerebbe a ricompilare e reinstallare tutto.

**Ricompilate il 2026-08-12 alle 10:45**, build `#8`, incrementale sopra la
`#7`: `.config` identico a quello archiviato, **0 errori e 0 warning**,
`bzImage` di 29 389 824 byte. Nell'immagine si vedono C1 (`System.map` ha
`__media_pipeline_remove_entity_pads` e `__media_device_unregister_entity` la
chiama) e C3 (`skl_int3472_clk_prepare` adesso chiama `kfree`, cioe'
`ACPI_FREE`, accanto a `acpi_evaluate_dsm`). C2 finisce inline dentro
`ipu6_isys_video_set_streaming` e li' si contano cinque `mutex_lock_nested`:
coerente, ma la prova vera e' a runtime.

**Non installata e non provata sull'hardware.** La stringa di versione non
cambia — `-dirty` senza commit nuovi — quindi `make modules_install`
sovrascriverebbe i moduli della `#7`, che e' quella in esecuzione. Va fatto
solo insieme al riavvio, non prima:

```bash
sudo make -C /home/nicfio/linux modules_install
sudo mount /dev/sda1 /mnt/esp
sudo cp /mnt/esp/vmlinuz-debug /mnt/esp/vmlinuz-dbg-ok     # la #7, che avvia
sudo cp /home/nicfio/linux/arch/x86/boot/bzImage /mnt/esp/vmlinuz-debug
sync && sudo umount /mnt/esp
```

Le tre prove di verifica:

| Patch | Come si vede se funziona |
|---|---|
| C1 | `unbind` a streaming acceso non deve piu' dare `slab-use-after-free` |
| C2 | nessuna WARNING alla prima cattura, e `debug_locks` deve restare `1` |
| C3 | dopo un ciclo completo, `kmemleak` non deve piu' elencare `skl_int3472_clk_prepare` |

C2 e' anche la condizione perche' lockdep sopravviva abbastanza da guardare
davvero i nostri driver, per il motivo qui sotto.

### Un limite da sapere, e vale per tutte le sessioni future

**Lockdep si spegne da solo al primo errore che trova, e resta spento fino al
riavvio.** Dopo C2, `/proc/lockdep_stats` dice `debug_locks: 0`: da quel
momento nessuno controlla piu' il locking, e un "nessun BUG/WARNING" non vuol
dire piu' niente. KASAN e UBSAN invece continuano a funzionare, sono
indipendenti.

Conseguenza pratica: **finche' C2 non e' corretto, la copertura di lockdep sui
nostri driver si ferma alla prima cattura.** Quello che c'e' qui sopra vale
per KASAN, UBSAN e KMEMLEAK senza riserve; per lockdep vale fino a li'.

### Due difetti di `prova-completa.sh` corretti oggi

Trovati mentre si guardavano i risultati, ed entrambi facevano dire allo
script piu' di quanto avesse misurato:

1. **I numeri di bus I2C erano cablati** (`3` e `2`). Non sono stabili:
   dipendono da quanti controller il kernel enumera prima, e su questo kernel
   i sensori stanno su `2` e `1`. Erano le 2 verifiche fallite del primo giro.
   Adesso il bus si ricava da sysfs.
2. **`dmesg -C` subito prima dei cicli bind/unbind** cancellava cattura,
   guadagno e compliance prima che qualcuno li guardasse: il controllo finale
   diceva "nessun BUG/WARNING" avendo visto solo gli ultimi dieci cicli. E'
   cosi' che C2 era passato inosservato. Adesso il buffer copre tutta la
   prova, il grep cerca anche `KASAN|UBSAN|lockdep`, e c'e' una verifica in
   piu' che fallisce se lockdep si e' spento.

### Il terzo: la misura di guadagno mentiva con troppa luce

Aggiunto in serata, dopo due falsi allarmi di fila nella stessa ora. Lo
script sapeva gia' difendersi dal buio — al buio il segnale resta sul
piedistallo e il rapporto e' fra due rumori — ma non dal caso opposto.

Con troppa luce il fotogramma a guadagno massimo **taglia sul fondo scala** a
1023, il segnale che manca in cima schiaccia la media e il rapporto crolla.
Il `gc5035` ha dato prima 2.83 e poi 10.7 invece di 16, e la prima volta e'
sembrata una regressione dei driver: era mezzogiorno, e poi il tablet era
girato verso la finestra.

**La soglia sulla media non basta, ed e' l'errore che ho fatto al primo
tentativo.** Misurato sul silicio, `gc5035` a 16x in una stanza illuminata di
lato:

| Guadagno | Media | Massimo | Pixel al fondo scala |
|---|---|---|---|
| 1x | 97,5 | 366 | 0,00% |
| 16x | 421,6 | 1023 | **15,56%** |

Un sesto dell'immagine e' tagliato e la media e' 421 su 1023: nessuna soglia
sulla media puo' accorgersene. Il rilevatore giusto e' **la percentuale di
pixel al fondo scala**, e la soglia e' il 2%. Sopra, il rapporto non e' piu'
una misura del guadagno e lo script lo dice — `[--]`, con la percentuale nel
messaggio — invece di stampare un `[KO]` che manda a cercare un difetto
inesistente.

Le percentuali di taglio finiscono anche in `03-guadagno.txt`, cosi' la
misura resta verificabile a posteriori invece di dover essere creduta.

Nota pratica per chi rifa' la prova: **le due camere guardano da parti
opposte**, quindi non esiste una posizione della luce che vada bene per
entrambe insieme. Si misura una alla volta, e va benissimo: i due numeri non
devono venire dallo stesso fotogramma.

## ESITO — 2026-08-12, ore 10:52-11:20, terzo avvio

Il terzo avvio serviva a una cosa sola: **provare C1, C2 e C3**, che fino a
qui erano scritte ma mai eseguite. Il kernel di stamattina non le conteneva —
sono state trovate *durante* quella sessione, quindi la sessione che le ha
scoperte non poteva verificarle.

Verbale completo in `data/correzioni-20260812-111902/ESITO.md`. In breve:
**tutte e tre reggono**, `prova-completa.sh` da' 23 su 23, e lockdep e'
rimasto acceso fino in fondo.

Il kernel di debug adesso **parte da solo**, senza la trafila della UEFI
Shell: e' quello che ha reso possibile questa sessione.

### Non fidarsi delle date: verificare che le patch siano nel binario

La build #8 e' delle 10:45 e le patch sono state scritte alle 10:31-10:37.
Dedurre da questo che siano dentro sarebbe un ragionamento, non una prova — e
sui binari i ragionamenti sbagliano. Il controllo diretto e' provare a
**disapplicarle** dall'albero compilato:

```bash
cd /home/nicfio/linux
for d in ipu6-fix subdev-fix mc-pipeline-fix ipu6-lock-fix int3472-leak-fix; do
    p=$(ls /home/nicfio/INTEL-CAMERA/patches/wip/$d/*.patch | head -1)
    git apply --check --reverse "$p" 2>/dev/null \
        && echo "  DENTRO   $d" || echo "  ASSENTE  $d"
done
```

Se una patch torna indietro pulita, il codice corretto e' nel sorgente da cui
e' uscito il binario. Tutte e cinque: `DENTRO`.

### C4 — `DQBUF` non torna mai dopo l'unbind, reperto nuovo

Trovato oggi, e non cercandolo: la prima esecuzione del riproduttore si e'
impiantata e ci sono voluti sedici minuti per capire che non era lenta, era
ferma.

Dopo l'`unbind` a streaming acceso il processo di cattura resta in
`vb2_core_dqbuf` ad aspettare un fotogramma che non arrivera' mai. Nessuno
dice alla coda vb2 che il sensore se n'e' andato, quindi `DQBUF` non torna con
un errore: non torna e basta. **Riproducibile 10 volte su 10**, su entrambi i
sensori.

Va tenuto separato dagli altri tre, per quello che **non** e':

- **non e' un blocco del kernel**: il processo e' in stato `S`, attesa
  interrompibile. Un segnale lo libera e il sistema non ne risente. Ecco
  perche' `DETECT_HUNG_TASK` tace — sorveglia lo stato `D`, non `S`
- **non e' corruzione**: KASAN muto su tutti e dieci i cicli
- **non e' nostro**: sta nel percorso di mainline, non nei due driver

**Corretto in giornata.** `isys_async_ops` dichiara `.bound()` e `.complete()`
ma non `.unbind()`: nessuno avvisa i nodi video, e l'attesa in
`__vb2_wait_for_done_vb()` — che finisce su un buffer nuovo, su `!q->streaming`
o su `q->error` — non riceve nessuno dei tre. La patch aggiunge `.unbind()` e
chiama `vb2_queue_error()` sulle code **in streaming** del ricevitore CSI-2 a
cui il sensore era attaccato; marcare anche le code ferme le lascerebbe
avvelenate fino al successivo `STREAMOFF`, perche' `q->error` lo azzera solo
`__vb2_queue_cancel()`.

Patch in `patches/wip/ipu6-unbind-fix/`, `Fixes: f50c4ca0a820`. Su
`torvalds/master` di oggi il difetto c'e' ancora e l'archivio di `linux-media`
non ha nessun invio in proposito.

Confronto a una sola variabile — stesso script, stesso kernel, cambia solo il
modulo:

| | Cicli appesi | Cicli usciti | Errore |
|---|---|---|---|
| senza la patch | 3 su 3 | 0 | — |
| con la patch | 0 | 10 su 10 | `-EIO` |

### La prova che stava per mentire

Merita di essere raccontata, perche' e' passata a un soffio dall'essere
creduta. Dopo la ricarica dei moduli il riproduttore ha dato **5 successi su
5**, cioe' esattamente il risultato sperato. Era falso: ricaricando i moduli
il grafo media torna ai default, `STREAMON` falliva subito con `ENOLINK` e
`v4l2-ctl` usciva in un decimo di secondo **senza catturare niente**. Lo
script contava quell'uscita immediata come una vittoria.

Si e' scoperto solo andando a vedere *quale* errore tornasse a userspace: era
`STREAMON`, non `DQBUF`. Adesso lo script configura la pipeline riusando
`cattura.sh`, controlla che lo streaming sia partito davvero, e tratta un
ciclo senza cattura come **non valido** invece che come riuscito.

La morale, per le prossime sessioni: quando una prova da' il risultato che
speravi, e' quello il momento di chiederle come l'ha ottenuto.

### Il riproduttore aveva un difetto, corretto oggi

`unbind-in-streaming.sh` faceva `wait` liscio sul processo di cattura: con C4
di mezzo, attesa infinita. Adesso concede una finestra di grazia, poi termina
il processo, e **conta quanti cicli si sono appesi** invece di nasconderlo.

Terminare il processo non e' un ripiego, e' meta' della prova: chiudere il
file percorre `v4l2_release -> __vb2_queue_cancel -> __media_pipeline_stop`,
cioe' esattamente il punto dove viveva l'use-after-free C1. Ogni ciclo ci
passa per intero.

Cinque cicli: da oltre 80 minuti stimati a 50 secondi reali.

### Una trappola di lettura, per la prossima sessione

Cercando `KASAN` nel log d'avvio escono nove righe, e sembra un disastro. Sono
righe come `? __kasan_kmalloc` e `? kasan_quarantine_put` **dentro i backtrace
dei `WARNING` di i915** sulle porte TypeC: voci residue dello stack, non
segnalazioni. Una segnalazione vera comincia con `BUG: KASAN:`, ed e' quello
che va cercato.

## Il riquadro del secondo avvio (superato)

> Immagine ricompilata con LPSS e gia' installata. **Manca solo il riavvio.**
>
> | Cosa | Stato |
> |---|---|
> | Immagine sulla ESP | `/mnt/esp/vmlinuz-debug`, 29 385 728 byte, build `#7` |
> | Copia di sicurezza | `/mnt/esp/vmlinuz-dbg-ok` = l'immagine di prima, che almeno avviava |
> | Moduli | reinstallati, stessa cartella: la stringa di versione non e' cambiata |
> | Correzioni A1 e A2 | sempre applicate **non committate** in `/home/nicfio/linux` |
> | `startup.nsh` | **modificato**: adesso avvia `vmlinuz-debug` da solo, md5 `527d5481e29f0aa698aa02ebaed3cb90` |
>
> Attenzione a quell'ultima riga: il kernel di debug e' diventato il default.
> Se non parte, la macchina **non** torna a Debian da sola — bisogna premere
> ESC al countdown e digitare a mano, al prompt `Shell>`:
>
> ```
> fs0:
> vmlinuz initrd=initrd.img root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw quiet hostname=CHUWI iomem=relaxed
> ```
>
> (e' la seconda riga commentata dentro `startup.nsh`; oppure `vmlinuz-dbg-ok`
> al posto di `vmlinuz-debug` per riavere l'immagine precedente).
>
> **Una volta dentro**, prima di tutto il resto:
>
> ```bash
> ls /sys/bus/i2c/devices/     # devono comparire i bus designware, non solo SMBus e i915
> ls -l /sys/bus/i2c/devices/i2c-GCTI5035:00/driver   # deve esistere
> ```
>
> Se ci sono, allora la prova puo' partire davvero:
>
> ```bash
> sudo ./scripts/prova-completa.sh
> sudo ./scripts/misura-guadagno.sh          # con la luce accesa
> sudo dmesg | grep -E "KASAN|UBSAN|lockdep|BUG:|WARNING:|possible recursive"
> echo scan | sudo tee /sys/kernel/debug/kmemleak && sudo cat /sys/kernel/debug/kmemleak
> ```
>
> Nota: `prova-completa.sh` azzera il buffer di `dmesg`. Per rileggere i
> messaggi dall'avvio usare `journalctl -k -b`.

## PRONTO ALL'AVVIO — 2026-08-12, ore 08:56 (superato)

> **I passi 1 e 2 qui sotto sono gia' stati fatti.** Manca solo il riavvio.
>
> | Cosa | Stato |
> |---|---|
> | Immagine sulla ESP | `/mnt/esp/vmlinuz-debug`, 29 MB, con le due correzioni dentro |
> | Moduli installati | `/lib/modules/7.2.0-rc7-intelcam-debug-gc61216fb5a24-dirty` |
> | `startup.nsh` | **intatto**, md5 `78c831bb7c3f537b1c8bdae19025bfe3` |
> | Correzioni A1 e A2 | applicate **non committate** in `/home/nicfio/linux` |
> | `PARTUUID` di root | `dc363afc-02`, verificato con `lsblk` |
> | KMEMLEAK | attivo di suo, nessun parametro da aggiungere |
> | `PANIC_ON_OOPS` | disattivato: un oops non spegne la macchina |
>
> **Le due righe da digitare** dopo aver premuto ESC al conto alla rovescia:
>
> ```
> fs0:
> vmlinuz-debug root=PARTUUID=dc363afc-02 rw
> ```
>
> **Una volta dentro** (il prompt dira' `7.2.0-rc7-intelcam-debug`):
>
> ```bash
> uname -r                                   # deve dire 7.2.0-rc7-intelcam-debug-...
> sudo modprobe gc5035 gc8034                # qui sono IN-TREE, niente build-6.12
> sudo ./scripts/prova-completa.sh
> sudo ./scripts/misura-guadagno.sh          # con la luce accesa
> sudo dmesg | grep -E "KASAN|UBSAN|lockdep|BUG:|WARNING:|possible recursive"
> echo scan | sudo tee /sys/kernel/debug/kmemleak && sudo cat /sys/kernel/debug/kmemleak
> ```
>
> **Nota per la sessione dopo il riavvio**: questa conversazione girava sul
> tablet, quindi il riavvio l'ha interrotta. Il contesto e' tutto qui e in
> `docs/09-revisione-preinvio.md`. Le due correzioni nell'albero del kernel
> sono **non committate** apposta: committarle cambierebbe la stringa di
> versione e costringerebbe a ricompilare tutto.
>
> Per tornare a Debian: riavviare e lasciar scorrere `startup.nsh`.

## Avviarlo — richiede te davanti alla tastiera

Non lo si puo' rendere il default e non lo si vuole: e' un kernel da
laboratorio, lento, ed e' costruito a mano. La macchina continua ad avviare il
kernel Debian da sola, come adesso.

**`startup.nsh` non va toccato.** L'immagine si aggiunge con un nome nuovo e la
si lancia a mano dalla UEFI Shell. Se non parte, si riavvia e riparte Debian:
non c'e' niente da ripristinare. E' la stessa procedura che il 2026-08-11 ha
permesso di recuperare un boot fallito senza chiavetta.

### 1. Installare moduli e immagine

```bash
sudo make -C /home/nicfio/linux modules_install
sudo mkdir -p /mnt/esp && sudo mount /dev/sda1 /mnt/esp
ls -la /mnt/esp                      # guardare PRIMA cosa c'e'
sudo cp /home/nicfio/linux/arch/x86/boot/bzImage /mnt/esp/vmlinuz-debug
sync && sudo umount /mnt/esp
```

Nome nuovo, `vmlinuz-debug`: **non** sovrascrive `vmlinuz`, che e' il kernel
Debian con cui la macchina si avvia.

### 2. Al riavvio

Alla comparsa della UEFI Shell, premere **ESC** entro il countdown per saltare
`startup.nsh`, poi al prompt `Shell>`:

```
fs0:
vmlinuz-debug root=PARTUUID=dc363afc-02 rw
```

Tre dettagli, e sono i tre modi realistici di non fare boot:

- **`root=PARTUUID=`, non `root=UUID=`.** Questo kernel parte senza initrd e
  senza udev non risolve gli UUID di filesystem. Il disco e' MBR, quindi il
  PARTUUID e' firma-disco piu' numero di partizione: **`dc363afc-02`**
- **niente `initrd=`, niente `quiet`.** L'initrd non serve — `EXT4_FS`, `ATA`,
  `SATA_AHCI`, `BLK_DEV_SD` e `MSDOS_PARTITION` sono tutti `=y`, e
  `build-kernel.sh` si rifiuta di compilare se cosi' non fosse — e i messaggi
  al primo avvio vanno visti
- **`bzImage`, non `vmlinux`.** Lo stub EFI e' nel `bzImage`

### 3. Se non parte

Riavviare e lasciar scorrere `startup.nsh`. Torna Debian. Nessun file e' stato
modificato.

## Cosa fare una volta dentro

```bash
cd /home/nicfio/linux && sudo make modules_install     # se non gia' fatto
sudo modprobe gc5035 gc8034                            # ora sono IN-TREE
sudo ./scripts/prova-completa.sh
```

Qui i driver sono compilati **dentro** il kernel di prova, non fuori albero:
sparisce anche l'ultimo dubbio residuo, cioe' che l'header di compatibilita'
di `build-6.12/` mascheri qualcosa.

Poi, in ordine di quanto sono informativi:

> **Prima di tutto: applicare le due correzioni di mainline**, `ipu6-fix/` e
> `subdev-fix/`. Senza, questa sessione misura i difetti di qualcun altro. Il
> bind/unbind fa oopsare il kernel da solo per **A2** — basta udev che apre il
> nodo — e un oops interrompe la prova a meta' lasciando in giro riferimenti
> che poi KMEMLEAK segnala come perdite nostre. Non lo sono.
>
> ```bash
> cd /home/nicfio/linux
> git am /home/nicfio/INTEL-CAMERA/patches/wip/{ipu6-fix,subdev-fix}/*.patch
> ```

1. **Ripetere tutto il ciclo normale** — carica, cattura, guadagno,
   compliance, bind/unbind — e guardare `dmesg`. Con KASAN e lockdep attivi,
   un difetto che prima passava inosservato adesso stampa. Il guadagno chiede
   una luce accesa davanti ai sensori: al buio la misura non si fa, e dal
   2026-08-12 `prova-completa.sh` lo dice invece di dare `[KO]`.
2. **`unbind` durante lo streaming.** E' il test che dice se i **nostri**
   driver reggono quello scenario. Con `ipu6-fix/` applicata non lascia piu'
   la macchina da riavviare; senza, si', e allora si riproduce soltanto A1.
3. **KMEMLEAK dopo un ciclo completo**:

   ```bash
   echo scan | sudo tee /sys/kernel/debug/kmemleak
   sudo cat /sys/kernel/debug/kmemleak
   ```

   Da fare dopo dieci cicli di bind/unbind: e' li' che una perdita si accumula
   abbastanza da vedersi. **Una perdita in quel punto e' gia' nota e non e'
   nostra**: ogni oops di A2 lascia appeso per sempre un `video_device` con il
   suo minor, e si vede a occhio nudo dai buchi in `/dev/v4l-subdev*`. Con
   `subdev-fix/` applicata quel rumore sparisce e quello che resta e' materiale
   da guardare davvero.
4. **Cercare i messaggi che contano**:

   ```bash
   sudo dmesg | grep -E "KASAN|UBSAN|lockdep|BUG:|WARNING:|possible recursive"
   ```

Se dopo tutto questo non esce niente, allora — e solo allora — si puo' scrivere
in una cover letter che i driver sono stati provati con KASAN e lockdep. Prima
no.

---

## RICOSTRUITO — 2026-08-22, ore 11:21. Pronto all'avvio.

Il kernel di debug era stato rimosso il 21/08 insieme al suo albero dei
sorgenti, sul tablet **e** sul server di compilazione. Senza di lui il
**prerequisito di O2** non e' verificabile, perche' nessuno dei due kernel
rimasti ha `PROVE_LOCKING`:

| Kernel | `PROVE_LOCKING` |
|---|---|
| 7.0 (`/mnt/vmlinuz`, quello in uso) | lockdep non attivo |
| Debian 6.12.101 | `# CONFIG_PROVE_LOCKING is not set` |

Quindi e' stato ricostruito da zero. **Non e' un kernel nuovo: e' la build #8
riprodotta**, stessa base e stesso insieme di patch.

| | |
|---|---|
| Versione | `7.2.0-rc7-intelcam-debug-00011-g7575251abc28` |
| Base | `db2ddb871` = tag `v7.2-rc7`, clone shallow |
| Immagine | `/mnt/vmlinuz-debug`, **29 389 824 byte** |
| Moduli | `/lib/modules/7.2.0-rc7-intelcam-debug-00011-g7575251abc28`, 42 moduli |
| Compilata su | `nicfio@192.168.0.2`, `-j20`, 3 min 14 s, **0 errori 0 warning** |

I 29 389 824 byte sono **esattamente** la dimensione registrata per la build #8
del 2026-08-12. E' la conferma piu' diretta che si sia riprodotta quella, e non
qualcos'altro.

### Le 11 patch applicate, in quest'ordine

`serie/0001..0005` (bindings + i due driver + ipu-bridge), poi `ipu6-fix` (A1),
`subdev-fix` (A2), `mc-pipeline-fix` (C1), `ipu6-lock-fix` (C2),
`int3472-leak-fix` (C3), `ipu6-unbind-fix` (C4).

**C2 non e' opzionale qui**, ed e' il motivo per cui e' dentro: senza,
lockdep si spegne alla prima cattura e il prerequisito di O2 non si puo'
misurare (vedi il limite documentato piu' sopra).

Fuori resta la sola patch `int3472/` IMGCLKOUT, che `patches/wip/README.md`
dichiara non necessaria e che non era nella #8.

### Due scelte da non dimenticare alla prossima ricostruzione

1. **`build-kernel.sh` non e' stato usato cosi' com'e'.** Genera la config con
   `localmodconfig`, che legge i moduli *della macchina su cui gira*: sul
   server avrebbe prodotto la config del server — niente camere, niente LPSS.
   Si e' ripresa la config archiviata `config/intelcam-7.2.0-rc7-debug.config`
   e si sono rifatti a mano tutti i controlli di sicurezza dello script.
2. **Le patch vanno applicate e verificate IN SEQUENZA.** `serie/0002` e
   `serie/0004` toccano le stesse righe di `MAINTAINERS` e
   `drivers/media/i2c/Kconfig`: provarle tutte contro l'albero pulito da un
   falso `[KO]` sulla 0004, e disapplicarne una sola dall'albero completo da un
   falso `ASSENTE` sulla 0002. Il controllo buono e' `git am` in ordine, piu'
   un `grep` del codice atteso nei sorgenti.

### Avvio: c'e' una rete di sicurezza, stavolta

`startup.nsh` e' stato modificato, **ma la riga del 7.0 e' intatta e sotto**:

```
#vmlinuz initrd=initrd.img boot=live quiet hostname=CHUWI
vmlinuz-debug root=PARTUUID=dc363afc-02 rw
vmlinuz initrd=initrd.img root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw quiet hostname=CHUWI
```

La UEFI Shell esegue le righe in ordine. Se `vmlinuz-debug` **non si carica**,
la Shell passa alla riga dopo e riparte il 7.0 da sola. Se si carica, la terza
riga non viene mai raggiunta.

Il caso che la rete di sicurezza **non** copre e' il kernel che si carica e poi
va in panico (root non montabile). Contro quello valgono i controlli fatti
prima di compilare — `EXT4_FS`, `ATA`, `SATA_AHCI`, `BLK_DEV_SD`,
`MSDOS_PARTITION`, `EFI_STUB` tutti `=y`, `PARTUUID=dc363afc-02` verificato con
`lsblk` — e il fatto che questa stessa riga aveva gia' avviato la #8.

A mano, premendo ESC al countdown, al prompt `Shell>`:

```
fs0:
vmlinuz initrd=initrd.img root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw quiet hostname=CHUWI
```

Copia di `startup.nsh` originale: `/mnt/startup.nsh.bak-20260822-112118`
(md5 `b7589921d91c3ad2db2eca3e0c9c2e76`).

### Una volta dentro — il prerequisito di O2, che e' il motivo di tutto

La ESP non si rimonta da sola (`/etc/fstab` e' vuoto):
`sudo mount /dev/sda1 /mnt`.

```bash
uname -r                      # 7.2.0-rc7-intelcam-debug-00011-g7575251abc28
cat /proc/lockdep_stats | grep debug_locks     # deve dire 1
ls /sys/bus/i2c/devices/      # devono comparire i bus designware, non solo SMBus
```

Poi, **nell'ordine**, perche' lockdep si spegne al primo reperto e da li' in
poi non misura piu' niente:

```bash
cd /home/nicfio/INTEL-CAMERA
sudo ./scripts/prova-completa.sh              # attese 23 su 23
grep debug_locks /proc/lockdep_stats          # ancora 1? se no, fermarsi e leggere dmesg
sudo ./scripts/unbind-in-streaming.sh         # e' qui che passa isys_notifier_unbind()
sudo dmesg | grep -E "possible circular locking|possible recursive|WARNING: .*lock|lockdep"
```

La domanda a cui rispondere e' una sola:

> esiste un percorso che prende il lock del notificatore v4l2-async **tenendo
> gia'** `av->mutex`?

Se lockdep tace **ed e' rimasto acceso fino in fondo** (`debug_locks: 1` anche
alla fine), il prerequisito e' soddisfatto e O2 si puo' scrivere: prendere
`q->lock` attorno al controllo e alla marcatura in `isys_notifier_unbind()` non
introduce un ordine inverso. Se invece lockdep segnala una dipendenza
circolare, **O2 va ripensata**, perche' cosi' com'e' sostituirebbe un difetto
con un altro peggiore.

Attenzione a `debug_locks` alla fine e non solo all'inizio: un "nessun
messaggio" con lockdep gia' spento non vuol dire niente.

### Nota per la sessione che verra' dopo il riavvio

Questa conversazione girava **sul tablet**, quindi il riavvio l'ha interrotta.
Il contesto e' tutto qui e in `docs/11-osservazioni-review.md`. Da fare, oltre
al prerequisito di O2:

- **il ping sulla lista**: oggi e' il 22, la finestra 22-26 agosto e' aperta e
  il terzo controllo del 21/08 non ha trovato nessuna risposta umana
- **O7**, il controllo di NULL in `ipu6_isys_configure_stream_watermark()`, che
  non ha bisogno di nessun kernel particolare e va in `ipu6-lock-fix/` prima
  che parta l'invio 3

---

## ESITO DELL'AVVIO — 2026-08-22, ore 11:25-11:29. ANDATA MALE.

**Il kernel di debug e' partito, ma la macchina era inservibile: nessuno
schermo esterno e nessuna periferica del dock.** Nic ha dovuto ripristinare il
PC da una chiavetta d'emergenza. La riga `vmlinuz-debug` in `startup.nsh` e'
ora **commentata**: si avvia solo il 7.0.

Non rimetterla senza aver prima letto tutto questo paragrafo.

### Cosa e' successo davvero, dal journal (`journalctl -b -1`)

Il kernel si e' caricato, la radice si e' montata, i moduli si sono caricati,
il wifi e' partito e alle 11:27 GNOME era in piedi — due minuti dopo l'avvio,
perche' con KASAN inline tutto va al rallentatore (UPower e' andato in timeout
a 25 s). Quindi **la rete di sicurezza dello `startup.nsh` non e' mai
scattata**: la riga si e' caricata benissimo, era il sistema a essere
inservibile. E' esattamente il caso che avevo scritto di non coprire.

Il guasto e' nel Type-C:

```
i915 0000:00:02.0: [drm] *ERROR* Port F/TC#3: timeout waiting for PHY ready
WARNING: drivers/gpu/drm/i915/display/intel_tc.c:933 at adlp_tc_phy_connect
WARNING: drivers/gpu/drm/i915/display/intel_tc.c:315 at get_pin_assignment   <- drm_WARN_ON(val == 0xffffffff)
WARNING: drivers/gpu/drm/i915/display/intel_tc.c:332 at get_pin_assignment
```

La porta USB-C che porta **sia** lo schermo esterno **sia** il dock con le
periferiche non si aggancia: il PHY non risponde (`0xffffffff` = registro che
legge tutti uno, cioe' silicio non alimentato o non presente), e le tre
asserzioni si ripetono a ogni tentativo, fino alle 11:29:35, dentro
`intel_dp_detect()` chiamata da `systemd-logind`.

### Il punto che avrei dovuto vedere prima, e non ho visto

**Questo guasto c'era gia' il 12 agosto, identico, in tutti e tre gli avvii
del kernel di debug** — build #6, #7 e #8:

| Avvio | Data | `Port F/TC#3: timeout waiting for PHY ready` |
|---|---|---|
| #6 | 12/08 09:03 | si' |
| #7 | 12/08 09:13 | si' |
| #8 | 12/08 10:52 | si' |
| ricostruito | 22/08 11:25 | si' |

Era scritto nel journal di quelle sessioni. Nessuno l'ha notato perche' quel
giorno si guardavano solo KASAN, lockdep e le camere, e — questa e' la
differenza — **il dock e lo schermo esterno probabilmente non erano
attaccati**, quindi non e' costato niente a nessuno.

Quindi non e' un caso sfortunato del 22: e' una proprieta' nota e riproducibile
di questo kernel, che era gia' nei dati e che io non ho controllato prima di
dire "pronto all'avvio".

### Regole per la prossima volta

1. **`startup.nsh` non deve mai avere il kernel di debug come prima riga.** Il
   7.0 resta la riga che parte da sola. Il kernel di debug si sceglie **a
   mano** al prompt `Shell>`, premendo ESC al countdown:
   ```
   fs0:
   vmlinuz-debug root=PARTUUID=dc363afc-02 rw
   ```
   Cosi' l'unico modo di finire nel kernel di debug e' volerlo, e per uscirne
   basta riavviare, senza chiavette.
2. **Prima di proporre un avvio, leggere il journal degli avvii precedenti di
   quello stesso kernel** (`journalctl -b -N | grep -Ei "ERROR|WARNING"`), non
   solo la parte che interessa il progetto.
3. **Sessione col kernel di debug: dock e schermo esterno scollegati**, si
   lavora sullo schermo del tablet, si accetta che sia lento.
4. Il buco resta aperto: **il prerequisito di O2 non e' ancora misurato.**

### La causa vera: la config e' amputata, non e' il silicio

Correzione al paragrafo qui sopra. Il `timeout waiting for PHY ready` non e' un
difetto della porta: e' la conseguenza. **Nel kernel di debug manca l'intero
sottosistema USB Type-C.**

```
config/intelcam-7.2.0-rc7-debug.config:   # CONFIG_TYPEC is not set
config/intelcam-7.2.0-rc7.config:         # CONFIG_TYPEC is not set
config/intelcam-7.2.config:                # CONFIG_TYPEC is not set
```

Senza `TYPEC` non esistono nemmeno `TYPEC_DP_ALTMODE`, `TYPEC_UCSI`,
`UCSI_ACPI`, `USB_ROLE_SWITCH`, `USB4`. Nessuno negozia il DisplayPort sulla
porta USB-C, quindi i915 aspetta un PHY che nessuno ha acceso e legge
`0xffffffff`. Cadono insieme **schermo esterno e dock**, che stanno sulla
stessa porta.

Nel 7.0 in uso, invece, `drivers/usb/typec/` c'e' tutto: `typec.ko`,
`altmodes/`, `ucsi/`, `mux/`.

**Non e' l'unica cosa che manca.** Confronto fra i 210 moduli che il 7.0 sta
usando adesso e tutto cio' che il kernel di debug ha (moduli + built-in):
**108 su 210 sono assenti**.

| Cosa manca | Effetto |
|---|---|
| tutto `TYPEC` + `USB4` | niente schermo esterno, niente dock |
| `hid_multitouch` (`is not set`) | **touchscreen del tablet morto** |
| 33 moduli audio (`snd_sof*`, `snd_soc*`, `snd_hda_codec_*`, soundwire) | niente audio |
| 16 moduli termici (`int340x`, `processor_thermal_*`, `coretemp`, `rapl`) | niente gestione termica |
| 4 moduli `tpm` | niente TPM |
| `fuse`, `overlay`, `squashfs`, `configfs`, `kvm` | vari servizi non partono |

Il touchscreen morto **piu'** il dock morto spiega perche' la macchina sembrava
completamente bloccata: non c'era piu' nessun modo di darle un comando.

**Perche' la config e' ridotta cosi':** `scripts/build-kernel.sh` la genera con
`localmodconfig`, che tiene **solo i moduli caricati in quell'istante**. E'
stata generata l'11/08 sul tablet, verosimilmente senza dock, senza schermo
esterno e senza le altre periferiche attaccate: tutto quello che in quel
momento non era in uso e' stato buttato via. Da 4455 moduli del 7.0 a 42.

**Due cose che invece funzionavano** (dal journal, per correttezza):
`iwlwifi` ha caricato il firmware e `wlo1` si e' **associato alla rete FAST**
alle 11:25:15, handshake WPA completato; il Bluetooth ha caricato il firmware
di `hci0` e `bluetoothd` e' partito. I driver c'erano. Mancavano pero' i
profili `rfcomm` e `bnep`, e soprattutto non c'era piu' modo di *usare* la
macchina per accorgersene.

### Conseguenza per il progetto

Cosi' com'e', **questo kernel non e' utilizzabile come macchina di lavoro**: fa
girare KASAN e lockdep sui driver delle camere, e nient'altro. Per renderlo
usabile va ricompilato partendo da una config **completa** (base: quella del
kernel Debian, piu' le opzioni di debug), non da `localmodconfig`. Costa una
compilazione lunga sul server e un altro riavvio.

L'alternativa e' rinunciare alla misura di lockdep e dichiarare il
prerequisito di O2 come **limite noto**.

### DECISIONE — 2026-08-22: si lascia perdere

Nic ha scelto la prima delle due strade: **il kernel di debug non si
ricompila.** Il prerequisito di O2 e' chiuso come **limite noto** (vedi
`docs/11-osservazioni-review.md`).

**Pulizia fatta da Nic in giornata.** Stato finale, verificato:

- `/mnt/vmlinuz-debug` — **rimosso**
- `/lib/modules/7.2.0-rc7-intelcam-debug-00011-g7575251abc28` — **rimosso**
- `/mnt/startup.nsh` — tornato all'originale a due righe, `md5
  b7589921d91c3ad2db2eca3e0c9c2e76`, **identico** alla copia salvata prima
  della modifica del 22/08. Non e' rattoppato: e' proprio quello di prima
- nessuna misura dinamica ulteriore e' prevista su questa macchina

**Quello che resta, e che serve:** l'albero dei sorgenti su
`nicfio@192.168.0.2:~/linux`, con i 12 commit applicati (HEAD `b3366efad`).
E' la copia autorevole delle patch da quando quella sul tablet e' stata
rimossa il 21/08. Non e' un residuo del kernel di debug e non va cancellato.

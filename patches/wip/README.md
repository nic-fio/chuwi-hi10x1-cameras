# patches/wip — lavoro in corso

**PRONTE DA INVIARE dal 2026-08-12.** Fino a quel giorno i commit avevano
`BOZZA` nel subject apposta, per impedire un invio accidentale. Adesso non ce
l'hanno piu': sono firmate da Nicola Fiorillo <nicfio@gmail.com>, i segnaposto
di identita' sono spariti da tutti e otto i punti in cui stavano, e
`checkpatch --strict` da' **0 errori su tutte e dodici**.

Da qui in avanti un `git send-email` su questa cartella manda roba vera a
mailing list vere. Prima di farlo, la prova d'invio su se' stessi descritta
in fondo.

## Cosa c'e'

| File | Cos'e' |
|---|---|
| `serie/` | le cinque patch per `linux-media`, piu' la cover letter |
| `int3472/` | la patch per `platform-driver-x86` |
| `ipu6-fix/` | la correzione dell'oops di `ipu6-isys` |
| `subdev-fix/` | la correzione dell'oops di `subdev_open()` |
| `mc-pipeline-fix/` | **2026-08-12** — use-after-free in `__media_pipeline_stop()` |
| `ipu6-lock-fix/` | **2026-08-12** — stato del sub-device letto senza lock |
| `int3472-leak-fix/` | **2026-08-12** — perdita del ritorno di `_DSM` |
| `ipu6-unbind-fix/` | **2026-08-12** — `DQBUF` appeso per sempre dopo l'`unbind` |
| `cover-letter.txt` | il testo della cover, modificabile a mano |
| `destinatari.txt` | output di `get_maintainer.pl` per tutti e tre |
| `gc5035.c`, `gc8034.c`, `galaxycore,gc*.yaml` | copie di lettura |
| `int3472-clk_and_regulator.c` | copia del file toccato dalla patch int3472 |

La copia autorevole vive in `/home/nicfio/linux`, dove i sei commit sono
applicati sopra mainline 7.2-rc7. Le copie qui si rigenerano da li'.

## Tre invii indipendenti, non uno

Erano sei patch in fila. Sono diventate tre insiemi separati, perche' vanno a
destinatari diversi e non hanno motivo di aspettarsi a vicenda — e una serie
che tiene in ostaggio una correzione altrui e' una serie che si impantana.

Le patch sono sette dal 2026-08-12, ma gli invii restano tre: `subdev-fix/`
parte con `ipu6-fix/`, perche' sono due crash dello stesso scenario e vanno
agli stessi occhi.

### Le tre del kernel di debug — 2026-08-12 pomeriggio

Sono diventate **dodici patch e cinque invii** — contate a mano il 2026-08-12
sera, perche' qui c'era scritto "dieci" e i file sul disco erano di piu':
5 in `serie/` piu' sette correzioni singole. Le tre nuove non le ha trovate
la lettura del codice: le hanno trovate KASAN, lockdep e KMEMLEAK sul kernel
di debug, e ognuna ha in commit message l'output dello strumento che l'ha
vista. Dettagli e prove in `docs/10-kernel-di-debug.md`.

| Cartella | Cosa corregge | Dove va |
|---|---|---|
| `mc-pipeline-fix/` | use-after-free: la pipeline referenzia i pad di un'entity gia' liberata dall'`unbind` | `linux-media` |
| `ipu6-lock-fix/` | `ipu6_isys_fw_pin_cfg()` legge `format` e `crop` senza il lock dello stato | `linux-media` |
| `int3472-leak-fix/` | il ritorno di `acpi_evaluate_dsm()` non viene mai liberato | `platform-driver-x86` |

**`mc-pipeline-fix/` va da sola**, non con `ipu6-fix/`: e' lo stesso scenario
— `unbind` a streaming acceso — ma un sottosistema diverso, il media
controller invece di `ipu6-isys`, e altri manutentori. Tenerle insieme
significherebbe far aspettare l'una per l'altra.

**`int3472-leak-fix/` e' indipendente da `int3472/`**, benche' tocchino la
stessa funzione: verificato applicandola su mainline pura senza la bozza
IMGCLKOUT sotto. Possono partire in qualsiasi ordine; se partono insieme, la
correzione della perdita va per prima, perche' e' un `Fixes:` e l'altra e' un
miglioramento.

**Provate sul silicio il 2026-08-12 alle 11:20**, ed e' la prima volta: fino a
stamattina erano scritte ma mai eseguite, perche' il kernel in esecuzione non
le conteneva. Ora sono nella build #8 — verificato disapplicandole una per una
con `git apply --check --reverse`, non dedotto dalle date.

| Reperto | Prova | Esito |
|---|---|---|
| C1 | 10 cicli di `unbind` a streaming acceso, 5 per sensore | nessun reperto KASAN |
| C2 | streaming, compliance e 10 bind/unbind con lockdep acceso | `debug_locks: 1`, nessun reperto |
| C3 | KMEMLEAK, due passate, dopo un ciclo completo | 0 `unreferenced object` |

Verbale e materiale grezzo in `data/correzioni-20260812-111902/`.

### C4 — `ipu6-unbind-fix/`, la dodicesima patch

Trovata provando le tre qui sopra, e non cercandola: il riproduttore si e'
impiantato e ci sono voluti sedici minuti per capire che non era lento, era
fermo. Dopo l'`unbind` a streaming acceso `DQBUF` **non torna mai**, perche'
`isys_async_ops` non ha una `.unbind()` e nessuno sveglia la coda vb2.

La patch la aggiunge e chiama `vb2_queue_error()` sulle sole code in
streaming del ricevitore CSI-2 interessato. `Fixes: f50c4ca0a820`, verificato
sul diff vero: quel commit introduce `isys_async_ops` con due sole callback.

Confronto a una sola variabile — stesso script, cambia solo il modulo:

| | Cicli appesi | Cicli usciti | Errore |
|---|---|---|---|
| senza la patch | 3 su 3 | 0 | — |
| con la patch | 0 | 10 su 10 | `-EIO` |

`checkpatch --strict`: 0 problemi oltre ai due voluti (`Signed-off-by`
mancante e il falso positivo `Unknown commit id`). `W=1` pulito.

**Dove va**: a `linux-media`, **insieme a `ipu6-fix/`**. Stesso driver, stesso
scenario — `unbind` a streaming acceso — e stessi revisori. Al contrario di
`mc-pipeline-fix/`, che e' lo stesso scenario ma un altro sottosistema, qui
non c'e' nessuna dipendenza da spezzare.

Stato: `checkpatch --strict` da' **0 errori** su tutte e tre. L'unico avviso
residuo e' `Unknown commit id` sui `Fixes:`, ed e' un falso positivo:
`/home/nicfio/linux` e' un clone shallow di 7 commit e non puo' verificarli.
I tre hash sono stati controllati sul mirror, confrontando il diff del commit
con la riga che introduce il difetto.

### `serie/` — cinque patch a `linux-media`

```
0000  cover letter  (il testo vive in cover-letter.txt)
0001  media: dt-bindings: Add GalaxyCore GC5035
0002  media: i2c: Add GC5035 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0003  media: dt-bindings: Add GalaxyCore GC8034
0004  media: i2c: Add GC8034 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0005  media: ipu-bridge: Add GalaxyCore GC5035 and GC8034
```

Binding prima del driver, `MAINTAINERS` **nello stesso commit** del driver:
e' la forma che i revisori si aspettano.

### `int3472/` — una patch a `platform-driver-x86`

`int3472: Allow selecting the IMGCLKOUT frequency`. Nata dall'analisi in
`docs/07-clock-e-registri.md`, quando sembrava servisse a far funzionare il
GC8034. **Non serve**: le tabelle a 24 MHz funzionano a 19,2. Resta valida
come correzione di un buco di mainline — la piattaforma espone due frequenze e
il kernel ne offre una — ma va a un sottosistema diverso e non deve stare
nella serie media.

### `ipu6-fix/` — una patch a `linux-media`, indipendente

`media: ipu6: Check the remote pad before dereferencing it`. **Non e' nostro
codice**: e' un NULL pointer dereference di mainline, presente dalla
`3a5c59ad926b` (maggio 2024) e ancora in 7.2-rc7. Fa oopsare il kernel se si
fa `unbind` di un sensore mentre streamma. Trovato provocandolo davvero il
2026-08-11, vedi `docs/09-revisione-preinvio.md` § A1.

### `subdev-fix/` — una patch a `linux-media`, da inviare insieme a `ipu6-fix/`

`media: v4l2-subdev: Check v4l2_dev before dereferencing it in open()`.
**Non e' nostro codice**: e' un secondo NULL pointer dereference di mainline,
in `subdev_open()`. `v4l2_device_unregister_subdev()` azzera `sd->v4l2_dev`
prima di togliere il nodo, e chi apre `/dev/v4l-subdevN` in quella finestra
oopsa. Non e' stato provocato: si e' presentato da solo il 2026-08-12 con
`v4l_id` di udev. Vedi `docs/09-revisione-preinvio.md` § A2.

Ha il suo `Fixes:` — `61f5db549dde`, del 2011 — trovato con la blame di GitHub
perche' il clone locale e' shallow. L'archivio di `linux-media` e' stato
controllato il 2026-08-12: nessuno l'ha gia' inviata, e la finestra e' aperta
da quindici anni. Tecnicamente pronta, aspetta solo B1.

Destinatari di tutte e quattro in `destinatari.txt`, da `get_maintainer.pl`.

## Stato verificato, non dichiarato

| Verifica | Esito |
|---|---|
| Compilano su mainline 7.2-rc7 | **si'** |
| Build `W=1` dei due sottosistemi toccati | **nessun warning** |
| `checkpatch --strict --max-line-length=80` sui file | **0/0/0** su entrambi i driver |
| `checkpatch --strict` su tutte e dodici le patch | **0 errori**, 9 avvisi tutti falsi positivi |
| Firmate con `Signed-off-by` | **si', tutte e dodici** — 2026-08-12 |
| Segnaposto di identita' | **nessuno** — erano 8, in 5 file |
| `make dt_binding_check` sui due binding | **pulito** — dtschema 2026.6 |
| `yamllint` con la config del kernel | **pulito** |
| `sparse` (`C=1 W=1`) | **pulito** — sparse v0.6.5-rc1 |
| `smatch` | **pulito** — 0.6.4, verificato su un caso di prova |
| `coccinelle`, 69 script con `-D report` | **pulito** |
| Commenti in inglese | **si'** — tradotti il 2026-08-11 |
| Nessun carattere non ASCII | **verificato** |
| Tabelle registri importate | **si'** — GC5035 161+162, GC8034 233+7x14 |
| Tabelle identiche all'originale | **verificato**, comandi qui sotto |
| Link frequency coerenti fra driver e `ipu-bridge` | **si'** — 422,4 e 268,8 MHz, derivate dal clock |
| **Le tre correzioni C1/C2/C3 eseguite su hardware** | **SI', 2026-08-12 ore 11:20** — `data/correzioni-20260812-111902/` |
| **C4 corretta e provata** | **SI', 2026-08-12** — 3 su 3 appesi senza la patch, 10 su 10 usciti con `-EIO` con |
| Guadagno rimisurato sul kernel #8 | **si'** — 15,89x su 16 e 7,51x su 7,66, misurati uno alla volta |
| **Eseguiti su hardware** | **SI', 2026-08-11** — entrambi catturano |
| **Rieseguiti dopo un riavvio** | **SI', 2026-08-12** — 19 su 22, e le tre mancate non sono dei driver. `data/prova-20260812-072414/` |
| Frame rate dopo il riavvio | 28,82 e 24,01 — scarto 0,01% e 0,04% dal previsto |
| Guadagno dopo il riavvio | **si', alle 08:05 con la luce** — 15,85x su 16 e 7,37x su 7,66 |
| Oops nel kernel durante la prova | **si', ma non nostro** — A2, `subdev_open()` di mainline |
| Chip ID letto sul silicio | `0x5035` e `0x8044` |
| `v4l2-compliance` | **45/46** su entrambi — vedi `docs/08-prova-hardware.md` |
| Tabelle di guadagno verificate a misura | si' — 15,7x su 16 e 7,9x su 7,66 |
| Link frequency | **derivate dal clock**, 19,2 x 22 e 19,2 x 14 |
| Frame rate previsto dal driver = misurato | si' — 28,82 e 24,00 |
| La serie si applica a `torvalds/master` di oggi | **si'** — `ipu-bridge.c` su master e' identico alla nostra base a meno delle due voci |
| I nomi `gc5035`/`gc8034` sono liberi upstream | **si'** — verificato su `drivers/media/i2c/{Kconfig,Makefile}` di master |
| Punto d'inserimento alfabetico in Kconfig | corretto — dopo `VIDEO_GC2145` |

### Rifare la verifica delle tabelle

E' la domanda che un revisore fa per prima quando vede 400 righe di registri
copiati: «come faccio a sapere che non hai cambiato un valore per sbaglio?».
La risposta e' che si ricontrolla in tre comandi, uno per tabella:

```bash
L=/home/nicfio/linux/drivers/media/i2c
python3 scripts/regtab-to-cci.py --check \
        reference/gc8034-rockchip-bsp.c gc8034_global_regs_4lane \
        $L/gc8034.c gc8034_mode_3264x2448        # 233 registri
python3 scripts/regtab-to-cci.py --check \
        reference/gc5035-intel.c gc5035_global_regs \
        $L/gc5035.c gc5035_init_regs             # 161 registri
python3 scripts/regtab-to-cci.py --check \
        reference/gc5035-intel.c gc5035_2592x1944_regs \
        $L/gc5035.c gc5035_mode_2592x1944        # 162 registri
```

Rilegge entrambe le liste e le confronta coppia per coppia. Ultima esecuzione
2026-08-11 a fine giornata, dopo tutte le correzioni della revisione: **tre
`OK`**.

Gli strumenti si installano con `scripts/setup-verifica.sh`. Due trappole che
quello script evita: `dtschema` non compila senza `swig` e `python3-dev` (fallisce
su `pylibfdt`), e la `sparse` di Debian e' troppo vecchia — il kernel la rifiuta
e **prosegue lo stesso**, stampando un warning che si perde nell'output, cosi'
`C=1` sembra aver funzionato senza aver controllato niente.

**Dal 2026-08-12 `checkpatch --strict` da' 0 errori su tutte e dodici.** Prima
ne dava uno per patch, `Missing Signed-off-by`, ed era corretto che ci fosse:
il DCO e' una dichiarazione legale, la firma dev'essere di una persona reale e
va aggiunta da chi invia. Adesso c'e'.

I 9 avvisi che restano sono tutti falsi positivi, verificati uno per uno:

| Avviso | Quante volte | Perche' e' falso |
|---|---|---|
| `Unknown commit id` sui `Fixes:` | 7 | il clone locale e' shallow e non puo' risolverli; i sette hash sono stati controllati sul diff del commit che introduce ciascun difetto |
| `does MAINTAINERS need updating?` | 2 | la voce `MAINTAINERS` che copre anche il binding sta nel commit del driver, dove i revisori se l'aspettano |
| `Prefer a maximum 75 chars per line` | 1 | e' una riga `create mode` generata da git nel diffstat: il percorso del file binding e' semplicemente lungo |

## Fatto il 2026-08-11

- **Tabelle registri importate.** Non piu' segnaposto. La conversione da
  `{0xNN, 0xNN}` a `{ CCI_REG8(0xNN), 0xNN }` e' fatta da
  `scripts/regtab-to-cci.py`, che ha anche una modalita' `--check`: rilegge il
  file generato e lo confronta registro per registro con l'originale. Serve a
  poter dire in review che la riscrittura e' **puramente sintattica**, senza
  doverlo far verificare a mano al revisore.
- **Commenti tradotti in inglese.** Erano in italiano: da soli sarebbero
  bastati a far respingere la serie.
- **MCLK corretto da 24 a 19,2 MHz**, con la motivazione nel commento. Vedi
  `docs/07-clock-e-registri.md`.
- **Serie 0 scritta** (`0006`): `.determine_rate` e `.set_rate` per il clock di
  `int3472`.
- **Corretto un dato sbagliato** nel commento sui GPIO del GC5035: diceva
  pin 175, la NVS dice 239.
- **Guadagno analogico del GC5035 implementato.** Era `-EOPNOTSUPP` con range
  bloccato a 1x. Importata la tabella a 17 voci dalla patch Intel: il registro
  `0xb6` prende un indice, non un moltiplicatore, e il resto si compensa in
  digitale su `0xb1`/`0xb2`. Il range esposto ora e' 1x…16x. Nota: il codice
  vendor scala il digitale per un rapporto letto dall'OTP; qui l'OTP non si
  legge, quindi quel rapporto e' unitario, e il commento nel driver lo dice.
- **Bias analogico del GC8034 importato.** Erano i 14 registri per indice di
  guadagno del BSP: indirizzi fissi, valori dipendenti dall'indice, con la
  sequenza che si sceglie da sola la pagina — per questo `0xfe` compare tre
  volte. Importate 7 righe su 9, tante quante gli indici raggiungibili, con uno
  `static_assert` che lega le due tabelle cosi' che non possano scollarsi.
- **Binding validati** con `make dt_binding_check`, **sparse pulito**, e
  aggiunto `scripts/setup-verifica.sh` per rifare l'ambiente.
- **Due difetti di PM runtime corretti**, emersi dal confronto con `t4ka3.c`.

## Cosa manca — in ordine di quanto blocca

### 1. ~~Provare su hardware~~ — **FATTO il 2026-08-11**

Il riavvio sul kernel Debian ha sbloccato tutto in una sera. Delle quattro
domande che erano appese qui:

- **il GC8034 con tabelle da 24 MHz a 19,2**: funziona, con i tempi scalati di
  0,8. Ne' ipotesi A ne' ipotesi B
- **le due link frequency**: **non confermate, smentite.** Le vere sono
  422,4 MHz (non 438) e 268,8 MHz (non 336), misurate dal frame rate
- **la polarita' del reset GPIO**: giusta, i sensori escono dal reset
- **`v4l2-compliance`**: 45/46, con il 46° condiviso con tutto il mainline
  recente

Tutto in `docs/08-prova-hardware.md`, per rifarlo `build-6.12/README.md`.

### 2. ~~Correggere le link frequency~~ — **FATTO il 2026-08-11**

Scelta la strada del valore **derivato a runtime** da `clk_get_rate()`, non
della costante: il moltiplicatore di PLL sta nella tabella registri, il clock
d'ingresso no, quindi lo stesso driver resta corretto sia sui 19,2 MHz di una
piattaforma IPU6 sia sui 24 MHz di un device-tree.

Moltiplicatori misurati: **22** per il GC5035, **14** per il GC8034. Le voci
di `ipu-bridge` sono state cambiate insieme ai driver, come devono.

Controprova: il frame rate previsto dal driver ora coincide con quello
misurato — 28,82 contro 28,82 e 24,00 contro 24,01.

### 3. ~~Rilievi della revisione pre-invio~~ — **CHIUSI il 2026-08-11**

Tredici reperti da `docs/09-revisione-preinvio.md`, tutti corretti tranne
quelli di identita'. I due che contano:

- **identificazione del chip spostata in probe.** Prima il bind riusciva anche
  senza sensore e l'errore compariva alla prima cattura. Sei driver mainline su
  sette identificano in probe, incluso `gc08a3` che e' il template diretto
- **le righe di copyright di Bitland, Google e Intel** mancavano in `gc5035.c`
  pur essendoci quella di Rockchip in `gc8034.c`. Aggiunte

Gli altri: `dev_err_probe()` fuori dalla probe, `pm_runtime_get_if_active()`
il cui `-EINVAL` portava a un `put` sbilanciato, ramo a 2 lane irraggiungibile
nel GC8034, moltiplicazione a 32 bit assegnata a un `s64`, due commenti che
dicevano il falso, `MODULE_AUTHOR` assente, `u16` dove bastava `u8`.

### 4. Come si invia — i passi di preparazione sono FATTI

Identita', firme e rimozione di `BOZZA`: fatti il 2026-08-12. Restano solo i
cinque invii, in quest'ordine. I primi due sono correzioni di difetti gia'
presenti in mainline, quindi non hanno motivo di aspettare la serie dei
driver.

**Prima di tutto, una volta sola: la prova d'invio su se' stessi.** Vedi
sotto — se il provider riscrive le righe, tutto il resto e' inutile.

#### Configurazione dell'invio — fatta il 2026-08-12

`git-email` e' installato, con i moduli Perl per TLS: `IO::Socket::SSL`,
`Net::SMTP::SSL` e `Authen::SASL`. Quest'ultimo manca spesso e quando manca
l'autenticazione fallisce con un errore che non lo nomina.

La configurazione e' globale, quindi vale sia da qui sia dall'albero del
kernel:

```
sendemail.smtpserver      smtp.gmail.com
sendemail.smtpserverport  587
sendemail.smtpencryption  tls
sendemail.smtpuser        nicfio@gmail.com
sendemail.from            Nicola Fiorillo <nicfio@gmail.com>
sendemail.confirm         always
```

**La password non e' salvata, ed e' voluto.** `git send-email` la chiede al
momento dell'invio: cosi' non finisce in chiaro dentro `~/.gitconfig`, che e'
un file di testo come tutti gli altri. Serve una **password per le app** di
Google, non quella dell'account: si genera da
`myaccount.google.com/apppasswords`, e Gmail rifiuta l'autenticazione SMTP con
la password normale.

`sendemail.confirm always` fa chiedere conferma prima di ogni singolo
messaggio. Queste patch vanno a mailing list pubbliche e archiviate per
sempre: un invio partito per sbaglio non si richiama.

```bash
cd /home/nicfio/INTEL-CAMERA

# 1. i tre difetti di ipu6/v4l2 dello stesso scenario, insieme
git send-email --to=linux-media@vger.kernel.org \
    --cc=sakari.ailus@linux.intel.com --cc=bingbu.cao@intel.com \
    --cc=tian.shu.qiu@intel.com \
    patches/wip/ipu6-fix/*.patch patches/wip/subdev-fix/*.patch \
    patches/wip/ipu6-unbind-fix/*.patch

# 2. l'use-after-free del media controller, da solo: altri manutentori
git send-email --to=linux-media@vger.kernel.org \
    --cc=sakari.ailus@linux.intel.com --cc=laurent.pinchart@ideasonboard.com \
    patches/wip/mc-pipeline-fix/*.patch

# 3. il lock mancante in ipu6, da solo
git send-email --to=linux-media@vger.kernel.org \
    --cc=sakari.ailus@linux.intel.com --cc=bingbu.cao@intel.com \
    patches/wip/ipu6-lock-fix/*.patch

# 4. la serie dei due driver, con cover letter
git send-email --to=linux-media@vger.kernel.org \
    --cc=mchehab@kernel.org --cc=sakari.ailus@linux.intel.com \
    --cc=robh@kernel.org --cc=krzk+dt@kernel.org --cc=conor+dt@kernel.org \
    --cc=devicetree@vger.kernel.org \
    --cc=tfiga@chromium.org --cc=liang1.wang@intel.com \
    patches/wip/serie/*.patch

# 5. int3472, altro sottosistema. La perdita di memoria per prima: e' un
#    Fixes:, l'altra e' un miglioramento
git send-email --to=platform-driver-x86@vger.kernel.org \
    --cc=dan.scally@ideasonboard.com --cc=hansg@kernel.org \
    --cc=ilpo.jarvinen@linux.intel.com --cc=sakari.ailus@linux.intel.com \
    patches/wip/int3472-leak-fix/*.patch patches/wip/int3472/*.patch
```

Controllare i `--cc` di `mc-pipeline-fix` con `get_maintainer.pl` prima di
mandarlo: e' l'unico dei cinque che va a un sottosistema su cui non avevamo
ancora raccolto i destinatari.

I `--cc` vengono da `destinatari.txt`, cioe' da `get_maintainer.pl`, tranne
`tfiga@chromium.org` e `liang1.wang@intel.com`: quelli sono gli autori del
codice riusato, e ci vanno per cortesia — vedi `reference/README.md`.

#### La prova d'invio su se' stessi — da fare una volta, prima di tutto

Un client che riscrive le righe, converte i tab in spazi o manda HTML rende la
patch **inapplicabile**, e la serie viene ignorata senza che nessuno spieghi
perche'. Non e' un rischio teorico: e' il modo piu' comune in cui un primo
invio si perde nel vuoto.

La prova non e' "mi e' arrivata la mail", e' "la mail che mi e' arrivata si
applica ancora":

```bash
cd /home/nicfio/INTEL-CAMERA

# 1. mandarsi la patch piu' piccola
git send-email --to=nicfio@gmail.com patches/wip/int3472-leak-fix/*.patch

# 2. da Gmail: apri il messaggio, menu tre puntini -> "Mostra originale"
#    -> "Scarica messaggio originale". Viene giu' un .eml o .txt

# 3. il collaudo vero: quel file si applica ancora?
cd /home/nicfio/linux
git checkout -b prova-invio prima-della-firma
git am ~/Scaricati/messaggio-originale.eml   # il nome che ha preso
```

Se `git am` applica il commit, la strada e' pulita e si puo' inviare davvero.
Se si lamenta di una patch corrotta, il problema e' nel percorso di invio e va
risolto **prima**, non dopo aver scritto a una mailing list.

Per tornare indietro dopo la prova:

```bash
git am --abort 2>/dev/null
git checkout master && git branch -D prova-invio
```

### 5. ~~Formalita'~~ — **CHIUSE il 2026-08-12**

Erano le uniche cose che non potevo fare io, perche' richiedevano un'identita'
reale. Nicola Fiorillo <nicfio@gmail.com> le ha fornite e sono state applicate
a tutta la storia:

| Cosa | Dov'era | Adesso |
|---|---|---|
| Identita' `git` | `INTEL-CAMERA WIP <wip@localhost>` su ogni patch | reale su tutte e dodici |
| Righe di copyright | `<TODO: real name...>` nei due driver | reali |
| `MODULE_AUTHOR` | `TODO` nei due driver | reale |
| Voci `MAINTAINERS` | 2 con `TODO Nome Cognome` | reali |
| Campo `maintainers` dei binding | 2 YAML con `TODO Nome Cognome` | reali |
| `Signed-off-by` | assente ovunque | su tutte e dodici |
| `BOZZA` nel subject | su tutte e dodici | tolto |

I segnaposto erano **otto in cinque file**: i due YAML dei binding non erano
nell'elenco che questo documento riportava, e si sarebbero scoperti in review.
Sono stati trovati cercandoli in tutto l'albero invece di fidarsi della lista.

Dopo la sostituzione i due driver sono stati ricompilati e i due binding
rivalidati con `dt_binding_check`: il campo `maintainers` ha un formato che
`dtschema` controlla davvero, e una scrittura sbagliata li avrebbe rotti.
Entrambi puliti.

L'attribuzione **non** e' piu' in questa lista: la DCO clausola (b) copre il
riuso GPL-2.0 dentro il kernel senza chiedere permesso a nessuno. Servivano le
righe di copyright originali e la provenienza dichiarata, e ci sono entrambe.
Vedi `reference/README.md`, sezione «Cosa serve davvero».

## Rilievi: cosa e' stato chiuso e cosa no

**Confronto con `t4ka3.c`** — fatto il 2026-08-11. E' il driver ACPI-only piu'
recente accettato in mainline. Ne sono usciti due difetti reali, corretti:

- `pm_runtime_use_autosuspend()` era chiamato ma mai accoppiato a
  `pm_runtime_put_autosuspend()`: il driver usava `pm_runtime_put()` liscio,
  quindi il ritardo di 1000 ms non entrava mai in gioco e il sensore veniva
  spento subito a ogni stop. Corretto in 4 punti per driver.
- il percorso d'errore della probe faceva `pm_runtime_disable()` senza
  `pm_runtime_dont_use_autosuspend()`, lasciando lo stato a meta'.

**`cur_mode` nella struct del device** — verificato, e si tiene. `t4ka3` deriva
tutto dallo state, ma `gc08a3`, `gc05a2` e `ov2740` — tutti mainline, e i primi
due sono proprio i template di questi driver — mantengono `cur_mode`. Non e'
quindi un blocco. Controllato il caso che sarebbe stato un bug vero: `set_format`
aggiorna `cur_mode` **solo** per `V4L2_SUBDEV_FORMAT_ACTIVE`, mai per `TRY`.

**Polarita' del reset GPIO** — **chiuso il 2026-08-11**: giusta. Con
`gpiod_set_value_cansleep(reset, 0)` i sensori escono dal reset e rispondono
all'I2C, quindi la convenzione del driver e quella di INT3472 combaciano.

**Link frequency del GC8034 incoerente nel BSP** — **chiuso misurando**, come
previsto. Il driver dichiarava 336 MHz e il commento del BSP 656 Mbps per lane
(cioe' 328): sbagliati tutti e due. Il valore vero su questa piattaforma e'
**268,8 MHz**, cioe' `19,2 x 14`, e i 336 sono lo stesso moltiplicatore
applicato ai 24 MHz di Rockchip.

## Nota sul PIXEL_RATE — i due driver fanno scelte diverse, apposta

`V4L2_CID_PIXEL_RATE` e' il rate del **pixel array**, non del bus CSI-2, perche'
viene usato con HBLANK/VBLANK per calcolare il frame interval.

- **GC5035**: `hts × vts × fps` = 175,9 MHz e `link_freq × 2 × lanes / bpp` =
  175,2 MHz **coincidono**, quindi la formula del bus va bene.
- **GC8034**: divergono — 319,9 contro 268,8 MHz. La differenza e' attesa
  (durante il blanking non si trasmette), e il valore corretto e' il primo.
  Il driver usa quello.

Entrambe le scelte sono motivate nel codice con il calcolo esplicito: e' la
risposta da dare in review, non "l'ho copiato dal template".

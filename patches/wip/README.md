# patches/wip — lavoro in corso

**Niente di qui e' inviabile.** I commit hanno `BOZZA` nel subject apposta:
serve a impedire un invio accidentale.

## Cosa c'e'

| File | Cos'e' |
|---|---|
| `serie/000*.patch` | la serie completa, generata con `git format-patch` |
| `gc5035.c`, `gc8034.c` | copie dei due driver |
| `int3472-clk_and_regulator.c` | copia del file modificato dalla Serie 0 |
| `galaxycore,gc*.yaml` | copie dei due binding |

La copia autorevole vive in `/home/nicfio/linux`, dove i sei commit sono
applicati sopra mainline 7.2-rc7.

## La serie

```
0001  media: dt-bindings: Add GalaxyCore GC5035
0002  media: i2c: Add GC5035 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0003  media: dt-bindings: Add GalaxyCore GC8034
0004  media: i2c: Add GC8034 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0005  media: ipu-bridge: Add GalaxyCore GC5035 and GC8034
0006  platform/x86: int3472: Allow selecting the IMGCLKOUT frequency
```

Binding prima del driver, `MAINTAINERS` **nello stesso commit** del driver:
e' la forma che i revisori si aspettano.

La 0006 e' nata il 2026-08-11 dall'analisi in `docs/07-clock-e-registri.md` ed
e' **indipendente dalle altre cinque**: si regge da sola come correzione a
`int3472`, e puo' essere inviata separatamente. Anzi conviene, perche' va a un
sottosistema diverso (`platform-driver-x86`, non `linux-media`).

## Stato verificato, non dichiarato

| Verifica | Esito |
|---|---|
| Compilano su mainline 7.2-rc7 | **si'** |
| Build `W=1` dei due sottosistemi toccati | **nessun warning** |
| `checkpatch --strict --max-line-length=80` sui file | **0/0/0** su entrambi i driver |
| `checkpatch --strict` sulle sei patch | **solo `Missing Signed-off-by`**, voluto |
| `make dt_binding_check` sui due binding | **pulito** — dtschema 2026.6 |
| `yamllint` con la config del kernel | **pulito** |
| `sparse` (`C=1 W=1`) sui tre file | **pulito** — sparse v0.6.5-rc1 |
| Commenti in inglese | **si'** — tradotti il 2026-08-11 |
| Nessun carattere non ASCII | **verificato** |
| Tabelle registri importate | **si'** — GC5035 161+162, GC8034 233+7x14 |
| Tabelle identiche all'originale | **verificato** con `scripts/regtab-to-cci.py --check` |
| Link frequency coerenti fra driver e `ipu-bridge` | **si'** — 438 e 336 MHz |
| **Eseguiti su hardware** | **SI', 2026-08-11** — entrambi catturano |
| Chip ID letto sul silicio | `0x5035` e `0x8044` |
| `v4l2-compliance` | **45/46** su entrambi — vedi `docs/08-prova-hardware.md` |
| Tabelle di guadagno verificate a misura | si' — 15,7x su 16 e 7,9x su 7,66 |

Gli strumenti si installano con `scripts/setup-verifica.sh`. Due trappole che
quello script evita: `dtschema` non compila senza `swig` e `python3-dev` (fallisce
su `pylibfdt`), e la `sparse` di Debian e' troppo vecchia — il kernel la rifiuta
e **prosegue lo stesso**, stampando un warning che si perde nell'output, cosi'
`C=1` sembra aver funzionato senza aver controllato niente.

L'unico errore di checkpatch e' `Missing Signed-off-by`. **E' corretto che ci
sia**: il DCO e' una dichiarazione legale e la firma deve essere di una persona
reale, con nome e cognome veri. Va aggiunta da chi invia, non da chi scrive.

Sulle due patch di binding resta un warning *"added file(s), does MAINTAINERS
need updating?"*: e' un falso positivo noto, la voce `MAINTAINERS` che copre
anche il binding sta nel commit del driver.

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

### 2. Correggere le link frequency — **ora e' questo a bloccare**

Le costanti nei due driver **e** le voci corrispondenti in `ipu-bridge` vanno
cambiate insieme, altrimenti la probe fallisce sulla validazione
dell'endpoint. Per il GC8034 c'e' prima una decisione da prendere: costante
fissa (giusta su x86, sbagliata su device-tree a 24 MHz) o valore derivato a
runtime da `clk_get_rate()`. La seconda e' la sola difendibile in review, e
vale anche per il GC5035.

### 3. Formalita'

Sono le uniche cose rimaste che **non** posso fare io:

- nome, email e copyright reali al posto dei `TODO` (2 punti per driver)
- `Signed-off-by`: e' una dichiarazione legale, la firma dev'essere di chi
  invia
- attribuzione da concordare con gli autori originali, che vanno contattati:
  `reference/README.md`

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

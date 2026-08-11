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
| Commenti in inglese | **si'** — tradotti il 2026-08-11 |
| Nessun carattere non ASCII | **verificato** |
| Tabelle registri importate | **si'** — GC5035 161+162, GC8034 233 |
| Tabelle identiche all'originale | **verificato** con `scripts/regtab-to-cci.py --check` |
| **Eseguiti su hardware** | **MAI** — il kernel che li contiene non e' mai stato avviato |

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

## Cosa manca — in ordine di quanto blocca

### 1. Provare su hardware (blocca tutto il resto)

I driver non sono mai stati eseguiti. Serve `pinctrl-alderlake`, che nel kernel
7.0 locale non e' compilato, quindi serve un kernel di distribuzione, quindi
**serve un riavvio**. Fino a li' non e' possibile:

- sapere se il GC8034 aggancia la PLL a 19,2 MHz con tabelle da 24 (ipotesi A
  contro ipotesi B in `docs/07-clock-e-registri.md`)
- confermare le due link frequency, 438 e 336 MHz
- verificare la polarita' del reset GPIO
- far girare `v4l2-compliance`

### 2. Bias analogico del GC8034

Il guadagno analogico e' implementato su **entrambi** i driver. Sul GC8034
resta pero' una lacuna di qualita': il BSP riscrive 14 registri di bias
analogico da `agc_register[9][14]` a ogni cambio di indice, e quelli non sono
ancora importati. Sono valori non documentati ma piccoli e strutturati: servono
alla resa dell'immagine, non a far funzionare il controllo.

Non e' bloccato dall'hardware, si puo' fare in qualunque momento.

### 3. Formalita'

- nome, email e copyright reali al posto dei `TODO` (2 punti per driver)
- `Signed-off-by`
- attribuzione da concordare con gli autori originali: `reference/README.md`
- validazione dei binding: `pip install dtschema yamllint`, poi
  `make dt_binding_check`

## Rilievi noti, non ancora affrontati

- **`cur_mode` nella struct del device.** Sakari chiede di derivarlo dallo
  state con `v4l2_find_nearest_size()`. Presente in entrambi, ereditato dai
  template.
- **Polarita' del reset GPIO.** `gpiod_set_value_cansleep(reset, 1)` significa
  reset *attivo*. Da verificare che la convenzione del driver combaci con
  quella dichiarata da INT3472.
- **Link frequency del GC8034 incoerente nel BSP**: il driver dichiara 336 MHz,
  il commento sopra la tabella dice 656 Mbps per lane, che sarebbero 328. Il
  commento nel nostro driver lo dice apertamente invece di nasconderlo.
- Confrontare tutto con **`drivers/media/i2c/t4ka3.c`**, il modello ACPI-only
  piu' recente accettato in mainline.

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

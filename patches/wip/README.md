# patches/wip — lavoro in corso

**Niente di qui e' inviabile.** I commit hanno `BOZZA` nel subject apposta:
serve a impedire un invio accidentale.

## Cosa c'e'

| File | Cos'e' |
|---|---|
| `serie/000*.patch` | la serie completa, generata con `git format-patch` |
| `gc5035.c`, `gc8034.c` | copie dei due driver |
| `galaxycore,gc5035.yaml`, `galaxycore,gc8034.yaml` | copie dei due binding |

La copia autorevole vive in `/home/nicfio/linux`, dove i cinque commit sono
applicati sopra mainline 7.2-rc7.

## La serie

```
0001  media: dt-bindings: Add GalaxyCore GC5035
0002  media: i2c: Add GC5035 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0003  media: dt-bindings: Add GalaxyCore GC8034
0004  media: i2c: Add GC8034 image sensor driver     (+ Kconfig, Makefile, MAINTAINERS)
0005  media: ipu-bridge: Add GalaxyCore GC5035 and GC8034
```

Binding prima del driver, `MAINTAINERS` **nello stesso commit** del driver:
e' la forma che i revisori si aspettano.

## Stato verificato, non dichiarato

| Verifica | Esito |
|---|---|
| Compilano su mainline 7.2-rc7 | **si'** |
| Build `W=1` | **nessun warning** |
| `checkpatch --strict --max-line-length=80` sui file | **0/0/0** su entrambi |
| `checkpatch --strict` sulle patch | **1 solo errore, voluto** — vedi sotto |
| Sottosistema media completo | **nessuna regressione** |
| Alias ACPI | `acpi*:GCTI5035:*`, `acpi*:GCTI8034:*` |
| **Eseguiti su hardware** | **MAI** — il kernel che li contiene non e' mai stato avviato |

L'unico errore di checkpatch e' `Missing Signed-off-by`. **E' corretto che ci
sia**: il DCO e' una dichiarazione legale e la firma deve essere di una persona
reale, con nome e cognome veri. Va aggiunta da chi invia, non da chi scrive.

Sulle due patch di binding resta un warning *"added file(s), does MAINTAINERS
need updating?"*: e' un falso positivo noto, la voce `MAINTAINERS` che copre
anche il binding sta nel commit del driver.

## Cosa manca — in ordine di quanto blocca

### 1. Le tabelle registri (blocca tutto)

Entrambi i driver hanno una `reg_list` con **una sola voce segnaposto**. Le
sequenze vere sono ~600 righe per il GC5035 (patch Intel) e ~880 per il GC8034
(BSP Rockchip), in `reference/`.

Non e' un copia-incolla:

- va sciolta l'**attribuzione** (vedi `reference/README.md`): la patch Intel
  deriva dalla serie ChromeOS di Tomasz Figa, il BSP e' Rockchip GPL-2.0
- vanno spezzate in tre liste — power-on, clock e link frequency, mode — come
  chiedono i revisori
- per il GC8034 va tolto tutto il codice OTP e gli ioctl Rockchip

### 2. Guadagno analogico

- **GC5035**: `V4L2_CID_ANALOGUE_GAIN` e' dichiarato con range 1x…1x e
  `s_ctrl` ritorna `-EOPNOTSUPP`. Manca la tabella `GC5035_AGC_Param[17][2]`.
  E' una limitazione **dichiarata**, non un bug nascosto.
- **GC8034**: qui il guadagno **e' implementato** — indice in
  `gc8034_again_level[]` piu' compensazione digitale. Mancano solo i 14
  registri di bias analogico per step (`agc_register[9][14]`), che servono alla
  qualita' dell'immagine, non alla funzione.

### 3. Valori da confermare sull'hardware

| Valore | Ora | Da dove verra' |
|---|---|---|
| Link frequency GC5035 | 438 MHz (ADL-M) | dal driver stesso — **non e' nell'SSDB**, verificato |
| Link frequency GC8034 | 336 MHz (BSP Rockchip) | idem |
| Lane MIPI | 2 e 4 | fwnode costruito da `ipu-bridge` |
| MCLK | 24 MHz | `clk_get_rate()` |

### 4. Formalita'

- nome, email e copyright reali al posto dei `TODO` (3 punti per driver)
- `Signed-off-by`
- validazione dei binding: serve `pip install dtschema yamllint`, poi
  `make dt_binding_check`
- `v4l2-compliance` pulito — richiede il kernel avviato e `apt install v4l-utils`

## Rilievi noti, non ancora affrontati

Cose che i revisori chiedono sistematicamente e che questi scheletri non fanno:

- **`cur_mode` nella struct del device.** Sakari chiede di derivarlo dallo
  state con `v4l2_find_nearest_size()`. Presente in entrambi, ereditato dai
  template.
- **Polarita' del reset GPIO.** `gpiod_set_value_cansleep(reset, 1)` significa
  reset *attivo*. Su questa macchina INT3472 dichiara `reset` **active-low**
  (pin 175): da verificare che la convenzione del driver combaci.
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

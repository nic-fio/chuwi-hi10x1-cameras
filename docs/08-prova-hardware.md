# 08 — Prova su hardware — 2026-08-11

Il primo giorno in cui i due driver hanno **girato davvero**. Fino a stasera la
riga piu' importante di `patches/wip/README.md` era «Eseguiti su hardware:
**MAI**».

Ambiente: kernel **Debian 6.12.86+deb13-amd64**, avviato al riavvio delle
20:11. Il 7.0 compilato a mano non c'entra piu' niente: e' il kernel di
distribuzione previsto da `docs/06-azioni-root.md` punto 5, ed e' quello che
porta `pinctrl-alderlake`.

## Esito in una tabella

| | GC5035 frontale | GC8034 posteriore |
|---|---|---|
| Client I2C creato | si', `i2c-3` @ `0x3f` | si', `i2c-2` @ `0x37` |
| Chip ID letto | **`0x5035`** | **`0x8044`** |
| Probe del driver | OK | OK, piu' VCM `dw9714` @ `0x0c` |
| Grafo CSI-2 | -> `CSI2 2` -> `/dev/video16` | -> `CSI2 1` -> `/dev/video8` |
| Streaming | 2592x1944 SGRBG10 | 3264x2448 SRGGB10 |
| Fotogramma riconoscibile | **si'** | **si'** |
| `v4l2-compliance` | 45/46 | 45/46 |
| Errori del kernel durante lo streaming | **nessuno** | **nessuno** |

Le immagini e i log stanno in `data/prima-cattura-2026-08-11/`.

## I tre semafori che si sono aperti da soli

`collect-diag.sh` (`data/20260811-201501/`) su questo kernel:

```
[OK] pinctrl-alderlake compilato
[OK] gpiochip presente
[OK] INT3472:01 agganciato
```

Erano `[KO]` da sempre, ed erano una sola causa: `pinctrl-alderlake` mancante
nel `.config` del 7.0. Con `INTC1057:00` che finalmente ha un driver, la `_DEP`
dei `GCTI*` verso `INT3472` si soddisfa e l'enumerazione ACPI crea i client I2C.

**Il sospetto della Fase 0 e' archiviato definitivamente.** Non era vero che i
sensori fossero dichiarati senza risorsa I2C: `/sys/bus/i2c/devices/` contiene
`i2c-GCTI5035:00` e `i2c-GCTI8034:00`, agli indirizzi esatti che la NVS aveva
previsto. Il `_CRS` vuoto non c'e' mai stato.

## Come sono stati costruiti i moduli

I driver sono scritti contro mainline 7.2, il kernel che gira e' il 6.12: build
fuori albero, in `build-6.12/`, contro gli header Debian della versione esatta.

**I sorgenti `.c` non sono stati toccati**: sono copie bit-identiche di
`/home/nicfio/linux`. L'unica differenza di API — `devm_v4l2_sensor_clk_get()`,
che nella 6.12 non esiste — e' colmata da `build-6.12/compat-6.12.h`, incluso
con `-include`. Cosi' quello che gira e' esattamente il codice che verra'
inviato, e non una sua variante.

Entrambi compilano contro la 6.12 **senza un warning**.

Serviva anche `ipu-bridge` con le due voci `GCTI*`: ricompilato dal sorgente
`v6.12.86` con la sola patch della Serie 3 applicata, e caricato al posto di
quello di Debian. Al ricaricamento di `intel-ipu6`:

```
intel-ipu6 0000:00:05.0: Found supported sensor GCTI5035:00
intel-ipu6 0000:00:05.0: Found supported sensor GCTI8034:00
intel-ipu6 0000:00:05.0: Connected 2 cameras
```

Istruzioni per rifarlo: `build-6.12/README.md`.

## Quello che la prova ha chiuso

### 1. La catena di alimentazione e clock funziona

I sensori rispondono sull'I2C solo con l'XVCLK attivo. Che rispondano dimostra
che il clock arriva, e questo chiude il dubbio lasciato aperto in
`docs/07-clock-e-registri.md` § 6: le scritture ACPI verso `SBREG_BAR`
**arrivano a destinazione** anche col P2SB nascosto. `CLKC` abilita davvero.
Non serve piu' «prima di dare la colpa ai registri, verificare che il clock ci
sia».

### 2. La polarita' del reset e' giusta

`gpiod_set_value_cansleep(reset, 0)` porta i sensori fuori dal reset e li fa
rispondere. La convenzione del driver e quella dichiarata da INT3472 combaciano.
Rilievo chiuso.

### 3. Il CSI-2 e' pixel-esatto

Test pattern del GC5035, riga 0: `0, 1020, 0, 1020, …`; riga 500: `512` per
tutta la riga. Un valore fuori posto su cinque milioni di pixel si vedrebbe.
Non c'e' corruzione, non ci sono lane invertite, il packing a 10 bit e' corretto.

### 4. Le tabelle di guadagno importate sono giuste

Non «il controllo esiste»: il guadagno misurato coincide con quello chiesto.
Segnale = media − 64 (il pedestal).

| | guadagno chiesto | segnale prima | segnale dopo | rapporto misurato |
|---|---|---|---|---|
| GC5035 | 1x -> 16x | 9,2 | 144,5 | **15,7x** |
| GC8034 | 1x -> 7,66x | 13,5 | 107,2 | **7,9x** |

Il GC5035 e' la tabella a 17 voci della patch Intel, il GC8034 i 14 registri di
bias per indice del BSP Rockchip. Erano il pezzo di codice piu' a rischio di
essere stato trascritto male: non lo sono.

### 5. Le tabelle Rockchip a 24 MHz funzionano a 19,2 MHz

Questa era **la domanda aperta piu' grande del progetto**, l'ipotesi A contro
l'ipotesi B di `docs/07-clock-e-registri.md` § 4.

Risposta: **nessuna delle due, e va meglio del previsto.** Le tabelle a 24 MHz
danno fotogrammi corretti a 19,2 MHz — niente frame corrotti, niente timeout
CSI-2, un'immagine perfettamente riconoscibile a 8 MP. Semplicemente **tutti i
tempi scalano di 19,2/24 = 0,8**.

Non servono i quattro registri ritarati (ipotesi A) e non serve forzare i 24 MHz
(ipotesi B). La **Serie 0** resta una correzione valida di un buco di mainline,
ma **non e' piu' sulla via critica** di questo hardware.

## Quello che la prova ha aperto: le link frequency dichiarate sono sbagliate

Il frame rate e' un cronometro sul PLL. Misurato su 200 fotogrammi, stabile alla
seconda cifra:

| | nominale dal driver | misurato | rapporto |
|---|---|---|---|
| GC5035 | 29,88 fps | **28,81** | 0,9642 |
| GC8034 | 30,00 fps | **23,99** | 0,7997 |

Il rapporto del GC5035 **non dipende dal blanking** — 0,9642 identico a
`vblank` = 64, 500 e 1000 — quindi non e' un errore di conteggio righe: il
modello `hts`/`vts` del driver e' esatto e a essere sbagliata e' la costante.

Ricavando la frequenza vera dal rate misurato si ottengono due multipli interi
e puliti dei 19,2 MHz, il che conferma sia la misura sia l'MCLK:

| | dichiarata | **misurata** | |
|---|---|---|---|
| GC5035 link freq | 438 MHz | **422,4 MHz** | = 19,2 × **22** |
| GC8034 link freq | 336 MHz | **268,8 MHz** | = 19,2 × **14** |

Le due discrepanze hanno cause diverse:

- **GC8034**: 336 = 24 × 14. E' il valore Rockchip, giusto per il *loro* XVCLK.
  Stesso moltiplicatore di PLL, clock d'ingresso diverso. Prevedibile.
- **GC5035**: 438 non e' un multiplo di 19,2 (438/19,2 = 22,81) **ne' di 24**
  (18,25). Il valore della patch Intel e' sbagliato e basta. Che quello vero
  sia 19,2 × 22 esatto e' la prova indipendente che le tabelle Intel sono
  native a 19,2 MHz — la conclusione del `README` regge, ma per un numero
  diverso da quello che dichiarava.

Verifica incrociata sul pixel rate, che chiude il cerchio:

| | dichiarato | misurato | atteso alla freq. vera |
|---|---|---|---|
| GC5035 | 175 200 000 | 168 923 402 | 168 960 000 (0,02%) |
| GC8034 | 319 887 360 | 255 803 259 | 255 909 888 (0,04%) |

### Le correzioni da fare

Non sono cosmetiche: `V4L2_CID_LINK_FREQ` e `V4L2_CID_PIXEL_RATE` sono i valori
su cui l'userspace calcola l'esposizione e su cui il ricevitore CSI-2 dimensiona
la D-PHY. Che l'IPU6 sia stato tollerante non li rende giusti.

| File | Da | A |
|---|---|---|
| `gc5035.c` `GC5035_LINK_FREQ_438MHZ` | 438 MHz | 422,4 MHz |
| `gc8034.c` `GC8034_LINK_FREQ_336MHZ` | 336 MHz | 268,8 MHz |
| `ipu-bridge.c` `IPU_SENSOR_CONFIG("GCTI5035", …)` | 438000000 | 422400000 |
| `ipu-bridge.c` `IPU_SENSOR_CONFIG("GCTI8034", …)` | 336000000 | 268800000 |

Le due coppie vanno cambiate **insieme**: il driver valida la propria lista
contro le `link-frequencies` che `ipu-bridge` pubblica sull'endpoint, e un
disallineamento fa fallire la probe.

**Decisione di progetto ancora da prendere, per il GC8034.** Un valore fisso
sarebbe giusto qui e sbagliato su una piattaforma device-tree che dia 24 MHz,
dove le stesse tabelle producono davvero 336 MHz. Tre strade:

1. **Derivare a runtime**: `link_freq = 14 × clk_get_rate(xclk)`, e il pixel
   rate di conseguenza. Corretto su entrambe le piattaforme, ed e' la verita'
   fisica: il moltiplicatore di PLL sta nella tabella, il clock d'ingresso no.
   Costa un `V4L2_CID_LINK_FREQ` a un solo elemento calcolato in probe.
2. **Fissare 268,8 MHz** e rifiutare la probe con MCLK diverso da 19,2. Onesto,
   ma chiude il driver a x86/IPU6.
3. **Serie 0** e forzare i 24 MHz, cosi' i numeri Rockchip tornano veri.
   Ora e' la strada peggiore: aggiunge una dipendenza da una patch a un altro
   sottosistema per risolvere un problema che non si presenta piu'.

La 1 e' la sola difendibile in review. Vale anche per il GC5035, dove il
moltiplicatore e' 22.

## `v4l2-compliance`: 45 su 46, e il 46° non e' nostro

Unico fallimento, identico sui due sensori:

```
fail: v4l2-test-controls.cpp(1128): subscribe event for control 'User Controls' failed
test VIDIOC_(UN)SUBSCRIBE_EVENT/DQEVENT: FAIL
```

Sono gli eventi di cambio controllo, che richiedono
`V4L2_SUBDEV_FL_HAS_EVENTS` e `v4l2_ctrl_subdev_subscribe_event`. Verificato che
**nessun** driver di sensore mainline recente li implementi:

| driver | `HAS_EVENTS` | `subscribe_event` |
|---|---|---|
| `gc05a2` | no | no |
| `gc08a3` | no | no |
| `ov2740` | no | no |
| `ov08x40` | no | no |
| `t4ka3` | no | no |

I primi due sono i template di questi driver e il quinto e' il piu' recente
accettato. Non e' un difetto introdotto qui, ed e' la risposta da dare se un
revisore lo solleva. Implementarlo sarebbe comunque un miglioramento reale, e
costa quattro righe.

## Rilievi minori raccolti

- **`int3472-discrete INT3472:02`** avvisa al boot:
  `reset ... pin number mismatch _DSM 239 resource 175` e
  `power-enable ... _DSM 207 resource 335`. Il driver usa il pin della risorsa
  e va avanti, e la camera funziona, quindi non e' bloccante. Va capito prima
  dell'invio: il commento del GC5035 era gia' stato corretto da 175 a 239
  sulla base della NVS, e la NVS dice 239 come il `_DSM` — ma il `_CRS` dice
  175. **Il pin che funziona e' quello del `_CRS`**, cioe' 175: era giusto il
  commento vecchio.
- **`supply dvdd not found, using dummy regulator`** su entrambi. Atteso su
  x86: le alimentazioni sono sempre accese o gestite da `INT3472`, e i dummy
  non impediscono nulla. Da citare nella cover letter prima che lo chieda un
  revisore.
- **Il VCM del posteriore esiste** e viene istanziato (`dw9714` @ `0x0c`),
  coerente con `L0DI = 2` della NVS. Il fuoco non e' stato provato.
- **Sei righe di errore CSI-2 viste una volta sola.** Sulla porta del GC5035:
  `csi2-2 error: Transfer FIFO overflow` e `Inter-frame long/short packet
  discarded`, in due gruppi. Poi **non piu' riprodotte** in una decina di
  catture successive fatte apposta per cercarle — 2 e 100 fotogrammi, su file
  e su `/dev/null`, subito dopo il ricaricamento dei moduli e a freddo. Le
  immagini di quel momento erano comunque integre. Sta scritto qui perche' un
  evento non riprodotto non e' un evento smentito: se ricompare, il primo
  sospetto e' la link frequency dichiarata sbagliata (438 contro 422,4), che
  fa dimensionare male la D-PHY del ricevitore.

## Come rifare tutto

```bash
cd build-6.12 && make                       # 3 moduli
sudo ./carica.sh                            # sostituisce ipu-bridge e carica i driver
media-ctl -p                                # il grafo deve mostrare gc5035 e gc8034
./scripts/cattura.sh gc5035                 # -> PNG guardabile
```

Nessuno di questi passi sopravvive a un riavvio: i moduli sono fuori albero e
`ipu-bridge` di Debian torna al suo posto. E' voluto — l'obiettivo del progetto
resta mainline, non un'installazione locale.

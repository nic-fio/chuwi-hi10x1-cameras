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

### Le correzioni, fatte la sera stessa

Non erano cosmetiche: `V4L2_CID_LINK_FREQ` e `V4L2_CID_PIXEL_RATE` sono i
valori su cui l'userspace calcola l'esposizione e su cui il ricevitore CSI-2
dimensiona la D-PHY. Che l'IPU6 sia stato tollerante non li rendeva giusti.

**Decisione presa: derivare a runtime da `clk_get_rate()`.** Le alternative
erano fissare i valori misurati — giusto qui, sbagliato su device-tree a
24 MHz — oppure tirare in ballo la Serie 0 per forzare i 24 MHz, cioe' una
dipendenza da un altro sottosistema per un problema che non si presenta piu'.
Derivare e' la verita' fisica: **il moltiplicatore di PLL sta nella tabella
registri, il clock d'ingresso no.** Un driver, due piattaforme, nessuna
costante da indovinare.

Nei due driver:

```c
#define GC5035_LINK_FREQ_MULTIPLIER	22	/* 19,2 MHz -> 422,4 */
#define GC8034_LINK_FREQ_MULTIPLIER	14	/* 19,2 MHz -> 268,8; 24 -> 336 */
```

Il menu di `V4L2_CID_LINK_FREQ` non e' piu' un array statico ma un campo della
struct del device, riempito in probe. Da qui una modifica d'ordine che vale la
pena notare: **il clock va risolto prima di leggere il fwnode**, perche' e'
`parse_fwnode()` a validare la frequenza offerta contro quella che il firmware
dichiara. Se il clock non c'e', la probe fallisce con un messaggio esplicito
invece di ereditare uno zero.

Il pixel rate segue per strade diverse nei due, come gia' documentato:

- **GC5035**: formula di bus sulla link frequency derivata, perche' rate di
  bus e rate d'array coincidono.
- **GC8034**: rate d'array, `hts x vts x fps`, dove `fps` e' tabulato per
  `GC8034_MCLK_REFERENCE` (24 MHz) e viene scalato al clock reale.

E in `ipu-bridge`, che pubblica le `link-frequencies` sull'endpoint e va
cambiato **insieme** ai driver, o la validazione fallisce e la probe non passa:

```c
IPU_SENSOR_CONFIG("GCTI5035", 1, 422400000),
IPU_SENSOR_CONFIG("GCTI8034", 1, 268800000),
```

### La verifica: ora il modello prevede la misura

E' il controllo che chiude il cerchio. Prima della correzione il driver
prevedeva un frame rate che il sensore non aveva; dopo, con 200 fotogrammi:

| | previsto dal driver | misurato |
|---|---|---|
| GC5035 | 28,82 fps | **28,82** |
| GC8034 | 24,00 fps | **24,01** |

Entrambi i sensori catturano ancora, `v4l2-compliance` resta 45/46, e i
controlli riportano `422400000` / `168960000` e `268800000` / `255909888`.

### Un dettaglio della stessa famiglia

Il GC8034 aspettava `350 us` prima del primo accesso I2C. Sono gli 8192 cicli
di XVCLK che il BSP chiede, **ma contati a 24 MHz**: a 19,2 MHz gli stessi
cicli durano 427 us, quindi l'attesa era troppo corta. Ora e' espressa in
cicli e divisa per il clock reale. Funzionava lo stesso, ma per fortuna, non
per costruzione.

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
- **Errori CSI-2 intermittenti, solo sul GC5035.** `csi2-2 error: Transfer
  FIFO overflow` e `Inter-frame long/short packet discarded`, da 4 a 14 righe
  per stream. Cosa si sa, dopo una ventina di prove:

  | | |
  |---|---|
  | Porta | solo `csi2-2`, il GC5035. Mai visto sul GC8034 |
  | Quando | ai bordi dello stream, mai durante |
  | Frequenza | intermittente: stessa sequenza, a volte 0 e a volte 6 |
  | Uno stream lungo isolato | **0 errori**, sempre |
  | Uno stream corto seguito da un altro | quasi sempre errori |
  | Pausa di 2 s fra i due | **non aiuta** |
  | Immagini | integre, frame rate stabile |

  Non e' una regressione della correzione sulla link frequency: la prima
  comparsa e' precedente, con i valori vecchi. La pausa che non aiuta esclude
  anche il dato in volo dallo stream precedente — con l'autosuspend a 1 s il
  sensore in mezzo si spegne del tutto. Resta aperto.

## La rivalidazione dopo il riavvio — 2026-08-12

Riavvio alle 07:16, moduli ricostruiti e ricaricati, e **prima esecuzione
completa di `scripts/prova-completa.sh`**: 19 verifiche superate, 3 fallite.
Output in `data/prova-20260812-072414/`.

Quello che conta e' tornato identico su una macchina ripartita da zero:

| | GC5035 | GC8034 |
|---|---|---|
| Chip ID | `0x50 0x35` | `0x80 0x44` |
| Frame rate previsto / misurato | 28.8162 / 28.82 (0,01%) | 24 / 24.01 (0,04%) |
| `v4l2-compliance` | 45 ok, 1 fallito | 45 ok, 1 fallito |
| 10 cicli di bind/unbind | riagganciato | riagganciato |

### Due delle tre mancate non sono un difetto: era buio

Il test del guadagno alza il guadagno analogico da minimo a massimo e chiede
che la luminosita' segua. Alle 07:24 il segnale misurato era **64,2** e
**63,8**: il piedistallo di black level e' 64, quindi il segnale utile era
sotto l'LSB. Il rapporto misurato — 3,98 contro 16 attesi — e' il rapporto fra
due rumori.

| | 2026-08-11 sera | 2026-08-12 07:24 |
|---|---|---|
| GC5035, media / massimo | 198 / 411 | 64 / 84 |
| GC8034, media / massimo | 124 / 598 | 64 / 80 |

La prova che e' la scena e non il driver sta nel massimo: 84 su 4096. Un
sensore che ignora il guadagno darebbe un'immagine costante, non un'immagine
nera. E la stessa misura, l'11 con la luce, aveva dato **15,7x su 16 chiesti**
e **7,9x su 7,66**: le tabelle di guadagno erano gia' state verificate, ed e'
la misura di oggi a non esistere, non quella di ieri.

`prova-completa.sh` adesso lo riconosce da solo e stampa `[--]` invece di
`[KO]`: se al guadagno massimo il segnale resta a meno di 4 LSB dal
piedistallo, la misura non e' stata fatta. **Il test del guadagno va rifatto
con una luce accesa davanti ai sensori** — resta l'unica verifica del giorno
che non ha prodotto un numero.

### La terza mancata e' un oops, e non e' dei nostri driver

```
BUG: kernel NULL pointer dereference, address: 0000000000000008
RIP: subdev_open+0x8a/0x190 [videodev]     Comm: v4l_id
```

`sd->v4l2_dev` e' `NULL` mentre il nodo `/dev/v4l-subdevN` e' ancora apribile,
perche' `v4l2_device_unregister_subdev()` azzera il puntatore prima di togliere
il nodo. E' un difetto di mainline, riprodotto poi a comando al settimo ciclo
con `scripts/riproduci-oops-subdev.sh`. Reperto **A2** in
`docs/09-revisione-preinvio.md`, patch in `patches/wip/subdev-fix/`, prove in
`data/oops-subdev-2026-08-12/`.

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

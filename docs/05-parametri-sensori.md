# 05 — Parametri dei sensori

Tutto quello che serve per scrivere i due driver, con l'origine di ogni valore.

**Regola di lettura**: ogni riga e' marcata con la sua provenienza.

| Marca | Significato |
|---|---|
| **[CODICE]** | letto da codice sorgente esistente e verificato — affidabile |
| **[DSDT]** | da leggere dalla DSDT di *questa* macchina — **ancora ignoto** |
| **[IPOTESI]** | valore da un'altra piattaforma, da confermare — **non usare senza verifica** |

Lo stato attuale: la DSDT non e' ancora stata estratta (serve root), quindi
tutte le righe **[DSDT]** sono vuote. E' il blocco della Fase 0.

---

## GC5035 — frontale, 5 MP

**HID ACPI**: `GCTI5035` — confermato **[CODICE]**, la patch Intel dichiara
`gc5035_acpi_ids[] = {{"GCTI5035"}, {}}`. Coincide con quanto la DSDT del CHUWI
espone su `\_SB.PC00.LNK1`.

### Identificazione

| | Valore | Origine |
|---|---|---|
| Chip ID | `0x5035` | **[CODICE]** |
| Registri ID | `0xf0` (H), `0xf1` (L) | **[CODICE]** — leggibili in qualsiasi pagina |
| Indirizzo I2C | **da DSDT** (`_CRS` I2cSerialBus di `LNK1`) | **[DSDT]** — il binding ChromeOS usa `0x37`, ma **non assumerlo** |
| Bus I2C | **da DSDT** | **[DSDT]** |

### Parametri CSI-2

| | Valore ADL-M | Origine |
|---|---|---|
| Lane MIPI | 2 | **[MISURATO]** — confermato dalla NVS e dallo streaming |
| Link frequency | **422 400 000 Hz** | **[MISURATO]** — 19,2 MHz × 22. La patch Intel dichiara 438 000 000 ed **e' sbagliata**: 438 non e' multiplo intero di nessun clock plausibile |
| Data rate/lane | 844,8 Mbps | derivato dalla misura |
| Bits per sample | 10 | **[CODICE]** |
| Pixel rate | **168 960 000** (= freq × 2 × lane / 10) | **[MISURATO]** — 168,92 MHz dal frame rate, scarto 0,02% |
| Bus type | `V4L2_MBUS_CSI2_DPHY` | **[CODICE]** |
| MCLK | 24 MHz nei commenti, 19,2 MHz tipico su ADL-N | **[DSDT]** — conflitto irrisolto, vedi sotto |

> **Conflitto MCLK nella patch Intel**: definisce `GC5035_MCLK_RATE 24000000`
> (mai usata) e passa `192000000` a `clk_set_rate()` nel probe. I commenti delle
> tabelle registri dicono "Xclk 24Mhz". Il valore vero per questa macchina si
> legge dal `_DSD` `clock-frequency` nella DSDT.

### Registri di controllo

Il sensore e' **paginato**: registro `0xfe` seleziona la pagina. Indirizzi a
8 bit. Tutti i registri sotto sono in pagina 0 salvo dove indicato. **[CODICE]**

| Funzione | Registro | Formato |
|---|---|---|
| Page select | `0xfe` | `0x00` = pagina 0 |
| Exposure | `0x03` (mask `0x3f`), `0x04` | 14 bit, unita' = righe, min 4 |
| Analogue gain | `0xb6` | **indice** in `GC5035_AGC_Param[17][2]`, non lineare |
| Digital gain | `0xb1` (mask `0x0f`), `0xb2` (mask `0xfc`, shift 2) | Q6 frazionario |
| VBLANK / frame length | `0x41` (mask `0x3f`), `0x42` | scrive `vblank + height`, **step 4** |
| Line length | `0x05`, `0x06` | unita' da 4 pixel |
| Streaming | `0x3e` | `0x91` = on, `0x01` = standby |
| Mirror/flip | `0x17` | scritto staticamente a `0x80`, flip su bit[1:0] |
| Test pattern | `0x8c` **in pagina 1** | `0x11` = on, `0x10` = off |

**Ordine Bayer**: la patch usa `MEDIA_BUS_FMT_SGRBG10_1X10`, con
`SRGGB10_1X10` commentato in quattro punti. Segnale che e' stato cambiato a mano
per il modulo ADL-M. **Da verificare empiricamente sul CHUWI**: il flip cambia
l'ordine Bayer.

### Mode dichiarati **[IPOTESI]**

| Risoluzione | hts | vts | fps |
|---|---|---|---|
| 2592×1944 | 2920 | 2008 | 30 |
| 1296×972 | 1460 | 2008 | 30 |
| 1280×720 | 1896 | 1536 | 60 |

> **Bug noto nella patch**: tutte e tre le tabelle scrivono lo stesso line
> length (`0x05=0x02`, `0x06=0xda` = 2920). Gli `hts` 1460 e 1896 dichiarati per
> le mode binned **non corrispondono ai registri**, quindi l'HBLANK esposto per
> quelle due mode e' sbagliato. Da correggere nel driver mainline, non da
> ricopiare.

---

## GC8034 — posteriore, 8 MP

**HID ACPI**: `GCTI8034` su `\_SB.PC00.LNK0`. Nessun codice x86 esistente:
i valori vengono dal BSP Rockchip (device-tree).

### Identificazione

| | Valore | Origine |
|---|---|---|
| Chip ID | **`0x8044`** (non `0x8034`) | **[CODICE]** |
| Registri ID | `0xf0` (H), `0xf1` (L) | **[CODICE]** |
| Indirizzo I2C | **da DSDT** (`_CRS` di `LNK0`) | **[DSDT]** |
| Bus I2C | **da DSDT** | **[DSDT]** |

### Parametri CSI-2 **[IPOTESI]** — dal BSP Rockchip, piattaforma diversa

| | 2-lane | 4-lane |
|---|---|---|
| Risoluzione | 3264×2448 | 3264×2448 |
| Link frequency | 634 MHz (30 fps) / 336 MHz (15 fps) | 336 MHz a 24 MHz di XVCLK, **268,8 misurati** a 19,2 |
| HTS | 4272 | 4272 |
| VTS | 2496 / 2500 | 2496 |
| Formato | `MEDIA_BUS_FMT_SRGGB10_1X10` | idem |

MCLK del BSP: 24 MHz. **Quante lane usi questa macchina si legge dalla DSDT.**

> **Verificato sull'hardware il 2026-08-11, e il BSP ha ragione lui.** Le due
> quantita' non concordano perche' **non sono la stessa cosa**: il rate
> dell'array e' piu' alto di quello del bus perche' durante il blanking
> orizzontale sul bus non passa niente. `V4L2_CID_PIXEL_RATE` e' quello
> dell'array, perche' l'userspace lo usa con HBLANK e VBLANK per calcolare
> l'intervallo di frame. Il driver usa quindi `hts × vts × fps`, scalato al
> clock reale: **255 909 888** a 19,2 MHz, contro i 255 803 259 misurati.
> Scarto 0,04%.

### Registri di controllo

Anche questo sensore e' **paginato** via `0xfe`, indirizzi a 8 bit. **[CODICE]**

| Funzione | Registro | Formato |
|---|---|---|
| Page select | `0xfe` | `0x00` = pagina 0 |
| Exposure | `0x03` (H, mask `0x7f`), `0x04` (L) | 15 bit nominali, limitati a 13 da `VTS_MAX 0x1fff` |
| Analogue gain | `0xb6` | indice in tabella a 9 voci (vedi sotto) |
| Digital gain | `0xb1` (int), `0xb2` (frac) | Q8, `0x0100` = 1,00× |
| Blanking | `0x07` (H), `0x08` (L) | **offset**, non VTS: `VTS = reg + 2484` |
| Line length | `0x05`, `0x06` | contiene **HTS/8** |
| Streaming | `0x3f` | `0xd0` = on 4-lane, `0x91` = on 2-lane, `0x00` = standby |
| Mirror/flip | `0xc0`/`0xc1`/`0xc2`/`0xc3` | nel BSP e' una `#define` a compile-time |

Tabella gain, unita' `0x40` = 64 = 1,00× (Q6):

```
gain_level[9] = { 0x0040, 0x0058, 0x007d, 0x00ad, 0x00f3,
                  0x0159, 0x01ea, 0x02ac, 0x03c2 }
                 1.000x  1.375  1.950  2.700  3.800
                 5.400   7.660  10.688 15.030
```

Il BSP usa solo i primi 7 indici (`MEAG_INDEX = 7`): le ultime due voci sono
codice morto. Ogni cambio di indice riscrive anche 14 registri di bias analogico
da `agc_register[9][14]` — non documentati ma piccoli e strutturati, da portare
cosi' come sono.

### Due insidie specifiche del GC8034

1. **Exposure forzata a valore pari.** Il BSP fa `cal_shutter = (exp >> 1) << 1`
   e compensa il bit perso con `Dgain_ratio = 256 * exp / cal_shutter`. Il
   sensore non accetta shutter dispari. Nel driver mainline: o si replica
   l'accoppiamento exposure→gain, o si dichiara `EXPOSURE step = 2` (piu'
   pulito, da preferire).
2. **`VTS = reg[0x07:0x08] + 2484`**, dove 2484 = 2448 righe attive + 36 di
   overhead. Verificato sui default del blob: `reg = 16` → VTS = 2500 = `0x09c4`,
   coerente con il `vts_def` dichiarato.

### Sequenza di power-on del BSP **[CODICE]**

Timing piu' lenti del template `gc08a3` (che usa 2 ms + 2 ms):

```
power_gpio=1 → 1 ms → clk 24 MHz → reset=1 → regolatori (dovdd, dvdd, avdd,
uno alla volta) → 100 µs → clk enable → 1 ms → pwdn=0 → 500 µs →
reset=0 → 6 ms → attendere 8192 cicli xvclk (~341 µs) prima del primo I2C
```

I **6 ms dopo il rilascio del reset** e i ~341 µs prima della prima transazione
I2C sono critici e vanno mantenuti.

---

## Rischio aperto: le PLL non sono documentate

**Questo e' il rischio tecnico numero uno del progetto.**

Per entrambi i sensori, i registri che determinano la PLL e il timing D-PHY sono
blob non documentati. Per il GC5035 sono `0xf4`, `0xf5`, `0xf6`, `0xf8`, `0xf9`,
`0xd3`, `0xee` (clock tree e bias analogico) e il blocco MIPI in pagina 3
(`0x02`, `0x03`, `0x15`, `0x18`, `0x21`–`0x2b` = Tlpx, Ths-prepare/zero/trail,
Tclk-*).

Conseguenza concreta: **non si sa come cambiare la link frequency.** Resta
vero, e resta senza importanza: non serve cambiarla, serve **dichiararla
giusta**, e adesso si sa quanto vale perche' e' stata misurata. I 438 MHz
della patch Intel sono un blob sbagliato, non un calcolo.

> **Superato dai fatti.** Gli scenari qui sotto sono stati scritti prima di
> poter accendere i sensori. Il verdetto e' che nessuno dei tre si e'
> avverato: le tabelle funzionano cosi' come sono, a un clock diverso da
> quello per cui erano nate, e l'unica cosa da correggere erano due costanti.
> Vedi `docs/08-prova-hardware.md`.

Scenari, in ordine di probabilita' decrescente:

1. La DSDT dichiara gli **stessi** valori della patch Intel → si procede senza
   ostacoli.
2. La DSDT dichiara valori **diversi** → serve il register guide GalaxyCore,
   oppure il blob di un altro vendor con quella configurazione, oppure si
   contatta GalaxyCore.
3. Il numero di lane e' diverso → stesso problema: nel GC5035 il lane count non
   e' configurato da un registro esplicito, e' implicito nella tabella pagina 3.

**Fino all'estrazione della DSDT non e' possibile sapere in quale scenario siamo.**

---

## Nota: la link frequency non si legge dalla DSDT

Sembra contraddire la sezione sopra, e va chiarito. `ipu-bridge.c:39-50`
dichiara che il valore da mettere nella tabella e' **quello che si aspetta il
driver**, e ammette esplicitamente che non e' ricavabile dall'`SSDB`:

> *…in the hopes of a better source for the information (possibly some encoded
> value in the SSDB buffer that we're unaware of) becoming apparent in the
> future.*

Quindi:

- per la **Serie 3** si cita il driver come fonte, non la DSDT
- la DSDT serve comunque per il **numero di lane**, l'indirizzo I2C, il clock e
  i GPIO, e come **conferma incrociata** della link frequency
- se DSDT e patch Intel divergono, e' il segnale d'allarme dello "scenario 2"
  qui sotto

---

# Analisi della DSDT — 2026-08-11

DSDT estratta e decompilata: 96.923 righe. Nodi isolati in `data/dsdt-analisi/`.

**Il risultato non e' quello che ci si aspettava**, e cambia il piano.

## Conferme

| | |
|---|---|
| `GCTI5035:00` | `\_SB.PC00.LNK1`, status **15** — enumerato a runtime |
| `GCTI8034:00` | `\_SB.PC00.LNK0`, status **15** — enumerato a runtime |
| `INT3472` | `DSC0` (`_UID` 0) e `DSC1` (`_UID` 1), `_DDN` "PMIC-CRDG" |

## Il problema: quasi nulla e' nella DSDT

`_HID` non e' una stringa, e' un **Method** che chiama `HCID(uid)`, la quale
sceglie fra ~24 ID di sensore in base alle variabili NVS `L0SM`/`L1SM`. Il BIOS
e' un template AMI generico per molti moduli camera; quale sia montato lo decide
il firmware a runtime.

Lo stesso vale per tutto il resto:

| Parametro | Dove sta | Variabile NVS |
|---|---|---|
| Indirizzo I2C | `_CRS` → `IICB(L1A0, L1BS)` | `L1A0` |
| Bus I2C | idem | `L1BS` |
| Numero di device I2C | `_CRS` | `L1DI` |
| **Numero di lane MIPI** | `SSDB` offset `0x1D` | **`L1NL`** |
| **MCLK** | `SSDB` offset `0x56` (DWORD) | **`L1CK`** |
| Control logic id | `SSDB` offset `0x5A` | `L1CL` |
| Rotazione | `SSDB` offset `0x54` | `CDEG(L1DG)` |
| Clock source index | `CLDB` offset `0x0E` | `C1CS` |
| Pin e funzioni GPIO | `_DSM` → `GPPI(C1Fx, …)` | `C1F0`…`C1F5`, `C1P0`…, `C1G0`… |

Nella DSDT quei campi sono **solo dichiarati** (`Field` alle righe 1987-2060),
mai assegnati: i valori li scrive il BIOS in NVS al boot. Non sono leggibili
staticamente, e non lo sono nemmeno da userspace senza il debugger ACPI.

## La scoperta che conta: `maxlanespeed` resta a zero

Nel buffer `SSDB` l'offset `0x46`-`0x49` — `maxlanespeed`, cioe' il campo da cui
si spererebbe di leggere la link frequency — **non e' fra quelli patchati dal
BIOS** e conserva il valore statico `0x00000000`.

E' la conferma sperimentale, su questa macchina, di quanto `ipu-bridge.c:39-50`
dichiara in astratto:

> *…in the hopes of a better source for the information (possibly some encoded
> value in the SSDB buffer that we're unaware of) becoming apparent in the
> future.*

**Non c'e'.** La link frequency va dal driver alla tabella, non viceversa. Il
cross-check che questo documento ipotizzava non e' possibile.

## Serie 4 (quirk `int3472`): quasi certamente NON serve

`DSC0`/`DSC1` espongono due `_DSM` distinti, ed **entrambi i GUID sono gia'
gestiti da mainline**:

| GUID | Funzione | Dove in mainline |
|---|---|---|
| `79234640-9e10-4fea-a5c1-b5aa8b19756f` | descrittori GPIO | `int3472/discrete.c:28` |
| `82c0d13a-78c5-4244-9bb1-eb8b539a8d11` | controllo del clock (`ICLK.CLKC`/`CLKF`) | `int3472/clk_and_regulator.c:19` |

Il secondo e' esattamente quello che la patch Intel chiama a mano — ma non
serve replicarlo: mainline lo fa gia'. Resta da verificare a runtime che i tipi
di funzione (`C1F0`…`C1F5`) siano fra quelli riconosciuti: `RESET` 0x00,
`POWERDOWN` 0x01, `STROBE` 0x02, `POWER_ENABLE` 0x0b, `CLK_ENABLE` 0x0c,
`PRIVACY_LED` 0x0d, `DOVDD` 0x10, `HANDSHAKE` 0x12, `HOTPLUG_DETECT` 0x13.

## Dati letti a runtime da `int3472-discrete` (2026-08-11)

Forzando un tentativo di probe (`echo INT3472:01 > …/int3472-discrete/bind`),
senza riavviare:

```
int3472-discrete INT3472:01: Sensor module id: 'GC8034'
int3472-discrete INT3472:01: avdd \_SB.GPI0 pin 85 active-high
int3472-discrete INT3472:01: cannot find GPIO chip INTC1057:00, deferring
```

Tre fatti:

1. **`INT3472:01` e' il control logic del GC8034** (posteriore). Per esclusione
   `INT3472:02` e' quello del GC5035. Il nome del modulo e' letteralmente
   `GC8034` — non un codice opaco tipo `CJAK519` come nel design ADL-M della
   patch Intel, dove `int3472_sensor_configs[]` matchava su quel nome. Una
   ragione in piu' per cui quell'hack non e' trasferibile.
2. **Il primo GPIO e' riconosciuto**: `avdd` significa che il tipo era
   `INT3472_GPIO_TYPE_POWER_ENABLE` (0x0b), che mainline mappa a regolatore.
   Pin **85** su `\_SB.GPI0`, **active-high**.
3. **Si ferma al primo GPIO.** Il lookup del gpiod fallisce perche' manca il
   gpiochip, quindi il probe va in defer prima di processare gli altri. Ogni
   tentativo mostra solo il primo.

### `INT3472:02` — il control logic del GC5035 (frontale)

```
int3472-discrete INT3472:02: [Firmware Bug]: reset \_SB.GPI0 pin number mismatch _DSM 239 resource 175
int3472-discrete INT3472:02: reset \_SB.GPI0 pin 175 active-low
int3472-discrete INT3472:02: [Firmware Bug]: avdd \_SB.GPI0 pin number mismatch _DSM 207 resource 335
int3472-discrete INT3472:02: avdd \_SB.GPI0 pin 335 active-high
int3472-discrete INT3472:02: cannot find GPIO chip INTC1057:00, deferring
```

| GPIO | Tipo INT3472 | Pin | Polarita' |
|---|---|---|---|
| `reset` | `RESET` (0x00) | 175 | **active-low** |
| `avdd` | `POWER_ENABLE` (0x0b) | 335 | active-high |

**Entrambi i tipi sono gestiti da mainline.**

### Secondo bug del firmware — gia' neutralizzato da mainline

Il kernel marca da solo `[Firmware Bug]`: il numero di pin dichiarato nel `_DSM`
**non coincide** con quello della risorsa `_CRS`.

| GPIO | pin da `_DSM` | pin da `_CRS` | usato |
|---|---|---|---|
| `reset` | 239 | 175 | **175** |
| `avdd` | 207 | 335 | **335** |

`int3472-discrete` rileva la discrepanza, la segnala e **usa il valore di
`_CRS`** (`discrete.c:322`). Nessuna azione richiesta: e' gia' risolto upstream.
Da non "correggere" in una Serie 4 — sarebbe lavoro duplicato.

### Perche' il posteriore mostra un GPIO solo e il frontale due

I tipi `RESET`/`POWERDOWN` vengono registrati in una lookup table e il gpiod lo
acquisira' poi il driver del sensore; `POWER_ENABLE` invece registra subito un
regolatore, e **quella** acquisizione richiede il gpiochip. Il probe va quindi
in defer appena incontra il primo `POWER_ENABLE`:

- su `INT3472:01` `avdd` e' il primo della lista → si vede solo lui
- su `INT3472:02` `reset` lo precede → si vedono entrambi

Gli eventuali GPIO successivi restano invisibili finche' non c'e'
`pinctrl-alderlake`, cioe' col kernel nuovo.

**Conseguenza per la Serie 4**: verdetto *parziale, e finora nettamente
favorevole*. Tre tipi osservati su due control logic, tutti riconosciuti; due
bug del firmware trovati, entrambi gia' gestiti da mainline. L'elenco completo
si potra' chiudere solo col kernel nuovo, ma l'ipotesi "la Serie 4 non serve"
e' piu' solida di prima.

> Nota: nel `dmesg` compare anche il WARNING `i915`
> `adlp_tc_phy_connect`/`get_pin_assignment`, gia' documentato in
> `01-hardware.md` come rumore non correlato. Il kernel risulta inoltre
> `Tainted: G S W`, dove `S` = `CPU_OUT_OF_SPEC`. Nessuno dei due c'entra con
> le camere.

## Bug nel firmware, solo sulla camera frontale

Nel `_DSM` di **`DSC1`** — il control logic del GC5035 — il case `Arg2 == 0x06`
compare **due volte**:

```
DSC0:  0x02 0x03 0x04 0x05 0x06 0x07     <- corretto, 6 GPIO
DSC1:  0x02 0x03 0x04 0x05 0x06 0x06     <- il secondo e' codice morto
```

Il ramo per `C1F5` e' irraggiungibile. `int3472-discrete` interroga i GPIO con
`func = i + 2`: se `C1GP == 6`, la query per il sesto arriva con `Arg2 == 0x07`,
cade nel `Return (Buffer(One){0x00})` finale e ottiene un descrittore nullo.

Se il sesto GPIO e' usato, **questo e' il caso in cui la Serie 4 servirebbe
davvero**: non come quirk di tipo, ma come workaround a un bug del firmware.
Si stabilisce leggendo `C1GP` a runtime.

## Nessun client I2C viene creato

`/sys/bus/i2c/devices/` non contiene ne' `i2c-GCTI5035:00` ne' `i2c-GCTI8034:00`,
pur essendo entrambi i device ACPI presenti e abilitati (l'accelerometro
`i2c-NSA2513:00` invece c'e', quindi l'enumerazione ACPI-I2C funziona).

Spiegazione piu' probabile: `_CRS` contiene `If ((L1DI == Zero)) { Return
(Buffer (Zero){}) }` — con `L1DI` a zero non viene emessa nessuna risorsa
`I2cSerialBus` e quindi nessun client. **Da verificare**: se fosse cosi', anche
con i driver pronti non ci sarebbe nulla a cui agganciarli, e sarebbe un
problema precedente a tutto il resto.

## Come leggere i valori NVS — **senza riavviare**

I valori non sono nella DSDT, ma la `OperationRegion` che li contiene ha un
**indirizzo fisico letterale**:

```
OperationRegion (GNVS, SystemMemory, 0x75886000, 0x0CE1)
```

Quindi i valori sono in memoria adesso, sulla macchina in esecuzione, e si
leggono da `/dev/mem` senza installare niente e senza riavviare.

L'indirizzo e' allineato alla pagina e la regione (3297 byte) sta **in una sola
pagina**: basta una lettura.

```bash
sudo ./scripts/read-camera-nvs.py
```

Lo script mappa i 1897 campi del `Field (GNVS, …)` — tabella degli offset in
`data/dsdt-analisi/gnvs-offsets.txt`, ricavata dalla DSDT — e stampa per
ciascun sensore: indirizzo e bus I2C, **numero di lane**, **MCLK**, control
logic id, numero e funzione di ogni GPIO. Poi emette tre verdetti:

- se il bug del `_DSM` di `DSC1` morde (`C1GP >= 6`)
- se qualche tipo di GPIO non e' riconosciuto da `int3472-discrete`
  (cioe' se la Serie 4 serve davvero)
- se `L0DI`/`L1DI` sono zero, il che spiegherebbe l'assenza di client I2C

E' una **lettura pura**: non scrive nulla, non tocca il boot, non richiede il
kernel nuovo.

> Se fallisce con un errore di I/O, il kernel ha `CONFIG_STRICT_DEVMEM` attivo.
> In quel caso restano: `CONFIG_ACPI_DEBUGGER` + `/sys/kernel/debug/acpi/acpidbg`,
> oppure un modulo che valuti i metodi ACPI — entrambi pero' richiedono un
> kernel diverso da quello in esecuzione.

**Nota di validita'**: indirizzo e offset valgono per questa macchina con questo
BIOS (`SA10C.N1195.24071902.014`). Dopo un aggiornamento del BIOS vanno
ricalcolati ridecompilando la DSDT.

## Cosa manca — da compilare dopo `dump-dsdt.sh`

- [ ] Indirizzo I2C e bus di `LNK0` (GC8034) e `LNK1` (GC5035)
- [ ] Numero di lane MIPI di ciascun sensore
- [ ] Porta CSI-2 a cui ciascuno e' collegato
- [ ] Link frequency dichiarata (`SSDB` / `_DSD`)
- [ ] Sorgente e frequenza del clock (`clock-frequency`, `CLDB` clock source index)
- [ ] GPIO usati e tipi di funzione nei `_DSM` di `DSC0`/`DSC1`
- [ ] Contenuto completo dei buffer `SSDB`
- [ ] **Verdetto sullo scenario PLL** (1, 2 o 3 qui sopra)
- [ ] **Verdetto sulla Serie 4**: i tipi di funzione GPIO nei `_DSM` sono
      riconosciuti da `intel_skl_int3472_discrete`?

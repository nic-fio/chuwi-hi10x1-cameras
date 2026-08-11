# INTEL-CAMERA

Portare in **mainline vanilla** il supporto nativo alle fotocamere del tablet
**CHUWI Hi10 X1** (Intel N100 / Alder Lake-N, Intel IPU6).

## Obiettivo

Che questa sequenza, su un kernel vanilla non modificato **scaricato da
kernel.org**, funzioni:

```
menuconfig -> VIDEO_GC5035, VIDEO_GC8034, PINCTRL_ALDERLAKE, VIDEO_INTEL_IPU6
make && make modules_install && reboot
apt install libcamera-tools pipewire-libcamera
# le fotocamere funzionano
```

Oggi il passo `menuconfig` **non e' eseguibile**: `VIDEO_GC5035` e
`VIDEO_GC8034` non esistono in nessuna versione del kernel. Il progetto consiste
nello scriverli e farli accettare upstream.

### Definizione di "fatto"

Il progetto **non** e' completo quando le fotocamere funzionano su questa
macchina con patch locali. Quello e' un passaggio intermedio.

E' completo quando il codice e' **nel tree di Linus Torvalds**, cioe' quando:

```bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
grep VIDEO_GC5035 linux/drivers/media/i2c/Kconfig    # deve trovare la voce
```

...su un tag di release ufficiale (`vX.Y`), senza alcuna patch applicata. Da li'
in poi il supporto arriva da solo a chiunque, via distribuzione, senza che
nessuno debba sapere che questo progetto e' esistito.

Il percorso e': `linux-media` -> `media_stage` -> tree `media` -> pull request a
Linus nella merge window -> `vX.Y`. Vedi `docs/03-piano-upstream.md`.

## Cosa c'e' da fare, in una riga

Due driver di sensore (`gc5035`, `gc8034`) piu' due voci in `ipu-bridge`.
Tutto il resto della catena — IPU6, ISYS, firmware, pinctrl, libcamera — e' gia'
in mainline e gia' pacchettizzato.

## Hardware

| | |
|---|---|
| Tablet | CHUWI Hi10 X1 — Intel N100 (Alder Lake-N) |
| ISP | Intel IPU6 `8086:462e` — funzionante |
| Posteriore | GalaxyCore **GC8034** 8 MP — ACPI `GCTI8034` @ `\_SB.PC00.LNK0` |
| Frontale | GalaxyCore **GC5035** 5 MP — ACPI `GCTI5035` @ `\_SB.PC00.LNK1` |

## Stato

**Le due fotocamere funzionano.** Il 2026-08-11, sul kernel Debian 6.12.86,
entrambi i driver hanno fatto probe, i sensori hanno risposto con il loro chip
ID e hanno prodotto fotogrammi riconoscibili — 5 MP la frontale, 8 MP la
posteriore — senza un solo errore del kernel. `v4l2-compliance`: 45 su 46 per
entrambi, e il 46° fallisce anche su tutti i driver di sensore mainline
recenti. Prove e misure in **`docs/08-prova-hardware.md`**.

Questo **non** e' il traguardo: e' il passaggio intermedio descritto qui sopra.
Il codice gira con patch locali, non e' nel tree di Linus.

Cinque semafori, aggiornati da `collect-diag.sh` (`data/20260811-201501/`):

| # | Semaforo | Stato | Dove si risolve |
|---|---|---|---|
| 1 | `pinctrl-alderlake` compilato | **OK** | risolto dal kernel Debian |
| 2 | `gpiochip` presente | **OK** | conseguenza di 1 |
| 3 | `INT3472:01/:02` agganciati | **OK** | conseguenza di 1 |
| 4 | `ipu-bridge` conosce i `GCTI*` | KO | **upstream** — Serie 3 |
| 5 | driver `gc5035`/`gc8034` presenti | KO | **upstream** — Serie 1 e 2 |

I semafori 1-3 erano un difetto del kernel 7.0 compilato a mano, **non**
materiale da mandare a mainline: `CONFIG_PINCTRL_ALDERLAKE` e' in mainline
dalla 5.18 e chi ha compilato quel kernel l'ha saltato. Il tentativo di
risolverli con un kernel vanilla costruito in casa era fallito (Fase 1,
abbandonata); la strada giusta era il kernel di distribuzione, ed e' quella che
ha funzionato.

I semafori 4-5 restano `[KO]` perche' misurano il kernel **installato**, e i
driver girano come moduli fuori albero caricati a mano (`build-6.12/`). Il
traguardo vero e' comunque il sesto criterio, che `collect-diag.sh` non puo'
misurare: **il codice nel tree di Linus**, con i cinque semafori `[OK]` su un
kernel vanilla senza patch.

## Struttura

```
INTEL-CAMERA/
├── README.md                    questo file
├── ROADMAP.md                   fasi, criteri di completamento, decisioni aperte
├── docs/
│   ├── 01-hardware.md           inventario, catena camera, stato dell'ambiente
│   ├── 02-diagnosi.md           i tre blocchi, con le prove
│   ├── 03-piano-upstream.md     le patch da inviare e cosa devono contenere
│   ├── 04-riferimenti.md        template, sorgenti registri, canali, maintainer
│   ├── 05-parametri-sensori.md  registri e parametri, con la provenienza di ognuno
│   ├── 06-azioni-root.md        i passi che richiedono root, con la motivazione
│   ├── 07-clock-e-registri.md   il clock di piattaforma e le tabelle registri
│   └── 08-prova-hardware.md     la prima esecuzione su hardware, con le misure
├── scripts/
│   ├── collect-diag.sh          snapshot riproducibile + semafori
│   ├── dump-dsdt.sh             estrae e decompila la DSDT (la specifica)
│   ├── cattura.sh               configura la pipeline IPU6 e cattura
│   ├── raw-to-png.py            da RAW Bayer a PNG guardabile
│   ├── build-kernel.sh          kernel vanilla di sviluppo, riproducibile
│   └── fix-pinctrl-alderlake.sh OBSOLETO — vedi l'intestazione del file
├── build-6.12/                  build fuori albero per provare sul kernel Debian
├── config/                      .config usate, una per versione di kernel
├── reference/                   codice di terze parti + vincoli di attribuzione
├── data/                        snapshot datati; data/latest -> ultimo
├── patches/                     le patch in lavorazione
└── upstream/                    copie di quanto inviato e feedback ricevuti
```

I sorgenti kernel vanilla stanno **fuori** dal progetto, in `/home/nicfio/linux`
(mainline, clone shallow).

## Uso quotidiano

```bash
sudo ./scripts/collect-diag.sh      # stato attuale + semafori
cat data/latest/SOMMARIO.txt
```

Rilanciarlo **dopo ogni modifica al kernel**: gli snapshot sono datati e
confrontabili, ed e' il modo per accorgersi di regressioni.

## La ACPI NVS e' stata letta — 2026-08-11

**Fatto.** Riavvio con `iomem=relaxed` alle 18:43, `/dev/mem` si e' aperto al
primo colpo, 3297 byte letti da `0x75886000`. Snapshot in
`data/nvs-2026-08-11/`. La lettura si ripete in qualunque momento, finche' dura
questo boot, con:

```bash
sudo ./scripts/read-camera-nvs.py           # i campi che contano
sudo ./scripts/dump-camera-nvs-completo.py  # tutti i campi L0/L1/C0/C1
```

Nota storica: era stato dedotto che servisse un kernel nuovo, perche' sul 7.0
`/dev/mem` dava `EPERM` (`IO_STRICT_DEVMEM=y`). **Deduzione sbagliata**:
`IO_STRICT_DEVMEM` e' subordinato a `strict_iomem_checks`, che `iomem=relaxed`
azzera (`kernel/resource.c:1918`). Il kernel vanilla era stato costruito e
provato lo stesso — boot fallito, Fase 1 abbandonata. Non era necessaria.

### I parametri, dal firmware

| | GC8034 posteriore | GC5035 frontale |
|---|---|---|
| bus / indirizzo I2C | bus **1**, **0x37** | bus **2**, **0x3f** |
| device I2C nel `_CRS` | **2** (0x37 sensore + 0x0c VCM) | **1** (solo sensore) |
| lane MIPI | **4** | **2** |
| MCLK | **19,2 MHz** | **19,2 MHz** |
| control logic | `DSC0` | `DSC1` |
| GPIO | 1: `POWER_ENABLE` pin 85 | 2: `RESET` pin 239, `POWER_ENABLE` pin 463 |
| nome modulo (`L*M*`) | `GC8034` | `CJAK519` |

### Tre conseguenze

**1. Il timore del `_CRS` vuoto e' smentito.** `L0DI` = 2 e `L1DI` = 1, non
zero: il firmware dichiara eccome le risorse I2C. L'ipotesi "sensori presenti
ma senza bus" e' archiviata.

**2. La causa vera dell'assenza di client I2C e' il pinctrl, ed e' provata.**
Da `dmesg`:

```
int3472-discrete INT3472:01: cannot find GPIO chip INTC1057:00, deferring
```

La catena e': manca `pinctrl-alderlake` → nessun gpiochip `INTC1057` →
`int3472-discrete` resta in deferred probe per sempre → la `_DEP` dei `GCTI*`
verso `INT3472` non e' mai soddisfatta → l'enumerazione I2C dell'ACPI non crea
i client. **Un solo difetto spiega i semafori 1, 2, 3 e l'assenza di client.**
Non e' un problema di firmware e non e' materiale da mandare upstream.

Non e' risolvibile a caldo: `pinctrl-alderlake.ko` non esiste in
`/lib/modules/7.0` — ci sono tigerlake, meteorlake, jasperlake, icelake e altri
otto, e' stato saltato solo quello che serve — e `INTC1057` e' rivendicato
**esclusivamente** da quel driver
(`/home/nicfio/linux/drivers/pinctrl/intel/pinctrl-alderlake.c:722`). Serve un
kernel di distribuzione. Resta fuori dalla via critica.

**3. La Serie 4 non serve.** `C1GP` = 2, sotto la soglia di 6: il bug del `_DSM`
duplicato non morde. E tutti i tipi GPIO usati (`0x00 RESET`, `0x0b
POWER_ENABLE`) sono gia' gestiti da `int3472-discrete`. Due patch in meno da
scrivere e da far accettare.

### Il rischio PLL: risolto la sera stessa, misurando

> **Aggiornamento del 2026-08-11, ore 20.** Tutto il paragrafo che segue e'
> stato scritto prima di poter accendere i sensori. La prova su hardware l'ha
> superato: **le tabelle Rockchip a 24 MHz funzionano a 19,2 MHz cosi' come
> sono**, con tutti i tempi scalati di 0,8 e nessuna corruzione. Non servono i
> quattro registri ritarati, e non serve forzare i 24 MHz.
>
> In compenso la misura del frame rate ha smascherato due costanti sbagliate:
> le link frequency vere sono **422,4 MHz** per il GC5035 (dichiarata 438) e
> **268,8 MHz** per il GC8034 (dichiarata 336), entrambe multipli interi dei
> 19,2 MHz — per 22 e per 14. I driver ora non le scrivono piu' a mano: le
> **ricavano dal clock**, perche' il moltiplicatore di PLL sta nella tabella
> registri mentre il clock d'ingresso dipende dalla piattaforma. Il frame rate
> che il driver prevede coincide adesso con quello misurato.
> Vedi `docs/08-prova-hardware.md`.
>
> Il testo resta perche' e' il ragionamento che ha portato a fare la misura
> giusta.

Era "non si sa se i blob PLL di nessuno dei due sensori valgono qui". Ora:

- **GC5035 — allineato.** La patch Intel usa 2 lane, il firmware ne dichiara 2.
  Sul clock c'e' un falso allarme da chiarire: la patch definisce
  `GC5035_MCLK_RATE 24000000UL` **e non lo usa mai** — grep, una sola
  occorrenza, la `#define` stessa. La probe chiede invece
  `clk_set_rate(..., 192000000)`, che e' 19 200 000 con uno zero di troppo, e
  sul disallineamento emette solo un `dev_warn`. Quindi i blob sono stati
  tarati a **19,2 MHz**, esattamente quello che dichiara questo firmware.
  Scenario 1.
- **GC8034 — il rischio si concentra qui, ma ora e' aggredibile.** Le lane
  tornano (4 = 4), mentre le uniche tabelle disponibili sono il BSP Rockchip a
  **XVCLK 24 MHz** e qui l'MCLK e' 19,2. Le due scorciatoie sperate sono chiuse:
  `gc08a3`, benche' mainline e della stessa famiglia, usa una mappa registri di
  generazione diversa (16 bit piatti contro 8 bit paginati), e il GC5035 usa gli
  stessi indirizzi con semantica diversa. Il problema si riduce pero' a
  **quattro registri** — `0xf4`, `0xf5`, `0xf7`, `0xfa`, gli unici a cambiare
  fra le configurazioni 2 e 4 lane.

  **E c'e' una via che prima non si vedeva.** Lo IMGCLKOUT della piattaforma sa
  fare **entrambe** le frequenze: `coreboot`, per Alder Lake, documenta il bit 0
  del registro `ICLK` come *«0: 24MHz, 1: 19.2MHz»*. Il kernel scrive sempre `1`
  e il clock di `int3472` non espone `.set_rate`, quindi i 24 MHz sono
  irraggiungibili **per una scelta software, non per un limite hardware**.
  Insegnare a `int3472` a programmare quel bit renderebbe valide le tabelle
  Rockchip senza toccarle.

Analisi completa, con le prove e le piste rimaste, in
`docs/07-clock-e-registri.md`. La sequenza in `ROADMAP.md`.

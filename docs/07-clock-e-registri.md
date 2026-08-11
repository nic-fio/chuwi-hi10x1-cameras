# Clock di piattaforma e tabelle registri — 2026-08-11

Analisi svolta dopo la lettura della ACPI NVS, per rispondere a una domanda
sola: **le tabelle registri del GC8034 disponibili sono utilizzabili su questa
macchina?**

Risposta breve: **no, non cosi' come sono**, e le due scorciatoie sperate sono
entrambe chiuse. Ma il problema si e' ristretto da "tutto il blob" a **quattro
registri**, e la catena di alimentazione e clock e' risultata sana.

---

## 1. GC08A3 non e' una fonte per il GC8034

Era la pista piu' promettente: `gc08a3` e' un driver **mainline**, GalaxyCore,
8 MP, risoluzione nativa 3264x2448 identica al GC8034, 4 lane come qui.

E' inutilizzabile: **i due chip non condividono la mappa dei registri.**

| Driver | Schema | Prova |
|---|---|---|
| `gc8034` (BSP Rockchip) | 8 bit **paginato**, page-select `0xfe` | 82 scritture su `0xfe` |
| `gc5035` (patch Intel) | 8 bit **paginato**, page-select `0xfe` | 106 scritture su `0xfe` |
| `gc08a3` (mainline) | 16 bit **piatto** | 395 registri `CCI_REG8(0x0…)` |
| `gc05a2` (mainline) | 16 bit **piatto** | 420 registri `CCI_REG8(0x0…)` |

I registri del `gc08a3` sono per di piu' agli indirizzi SMIA standard (`0x0202`
esposizione, `0x0340` frame length, `0x0342` line length): e' una generazione
successiva di silicio, non una variante. **Nessun valore e' trasportabile.**

Conseguenza organizzativa, non solo tecnica: `gc05a2`/`gc08a3` restano ottimi
come **modello di struttura** per un driver che passi la review — sono recenti,
mainline, usano `cci_reg_sequence` e `v4l2_link_freq_to_bitmap` — ma come
sorgente di **valori** non servono.

## 2. Il GC5035 non aiuta il GC8034

Seconda speranza: i due sensori del tablet sono della stessa famiglia paginata,
e il GC5035 ha gia' tabelle **tarate a 19,2 MHz** (vedi punto 4). Se i registri
PLL avessero la stessa semantica, si sarebbe potuto trasporre.

Non ce l'hanno:

| | GC5035 (Intel, 19,2 MHz) | GC8034 (BSP, 24 MHz) |
|---|---|---|
| `0xf7` | in **pagina 3**, valore `0x01` | nel blocco **SYS**, valore `0x9d` |
| `0xf4` | `0x40` | `0x80` |
| `0xf5` | `0xe9` | `0x19` |
| `0xf6` | `0x14` | `0x44` |
| `0xf8` | `0x49` | `0x63` |
| `0xf9` | `0x82` | `0x00` |
| `0xfa` | `0x00` | `0x45` |

Stessi indirizzi, significati diversi — `0xf7` sta perfino in una pagina
diversa. Il fatto che due chip usino lo stesso schema di indirizzamento non
implica che condividano la mappa.

## 3. Il problema si riduce a quattro registri

Confronto fra `gc8034_global_regs_2lane` e `gc8034_global_regs_4lane`, cioe' fra
due configurazioni MIPI diverse **dello stesso chip allo stesso XVCLK**:

| Registro | 2 lane | 4 lane | |
|---|---|---|---|
| `0xf4` | `0x90` | `0x80` | **cambia** |
| `0xf5` | `0x3d` | `0x19` | **cambia** |
| `0xf6` | `0x44` | `0x44` | uguale |
| `0xf7` | `0x95` | `0x9d` | **cambia** |
| `0xf8` | `0x63` | `0x63` | uguale |
| `0xf9` | `0x00` | `0x00` | uguale |
| `0xfa` | `0x42` | `0x45` | **cambia** |

Quindi il rate MIPI e' governato da **`0xf4`, `0xf5`, `0xf7`, `0xfa`**, mentre
`0xf6`, `0xf8`, `0xf9` restano fissi. La superficie da ritarare per passare da
24 a 19,2 MHz e' quella, non l'intero blob da 233 registri.

Resta che i quattro valori sono comunque non documentati: sapere *quali* byte
toccare non dice *quali valori* metterci. Ma per un tentativo empirico, o per
una domanda a GalaxyCore, e' una richiesta molto piu' circoscritta.

Il modo 4 lane completo, dal BSP:

```
mipi_freq_idx = 0  ->  336 MHz   hts_def = 0x10b0   vts_def = 0x09c0
                                 exp_def = 0x08c6   XVCLK   = 24 MHz
```

## 4. Il clock di piattaforma e' una scelta a un bit, e mainline la fissa

Percorso completo, verificato nel sorgente e nella DSDT:

1. `ipu-bridge` legge `mclkspeed` dall'`SSDB` e lo pubblica come proprieta'
   `clock-frequency` del nodo sensore (`ipu-bridge.c:373` e `:434`). Qui vale
   **19 200 000**.
2. `int3472-discrete` registra un clock il cui `recalc_rate` restituisce lo
   stesso valore, riletto dall'`SSDB`
   (`clk_and_regulator.c:skl_int3472_get_clk_frequency`).
3. L'accensione passa dal `_DSM` con GUID `82c0d13a-78c5-4244-9bb1-eb8b539a8d11`
   funzione 1, che nella DSDT del CHUWI chiama:

   ```
   ^^^ICLK.CLKC (indice, abilita)      -> bit 1 del registro CLKn
   ^^^ICLK.CLKF (indice, frequenza)    -> bit 0 del registro CLKn
   ```

4. Il kernel passa **sempre `1`** come argomento frequenza
   (`clk_and_regulator.c`, `args[2].integer.value = 1`).

La selezione di frequenza e' quindi **un singolo bit**, con due valori
possibili, e mainline ne sceglie uno fisso.

### Quale bit corrisponde a quale frequenza: risposta certa

Non serve dedurlo. Il codice di riferimento Intel lo dichiara, e per **Alder
Lake specificamente**: `coreboot`,
`src/soc/intel/alderlake/acpi/camera_clock_ctl.asl`, licenza GPL-2.0-or-later.

```c
#define R_ICLK_PCR_CAMERA1      0x8000
#define B_ICLK_PCR_FREQUENCY    0x1
#define B_ICLK_PCR_REQUEST      0x2
/* The clock control registers for each IMGCLK are offset by 0xC */
#define B_ICLK_PCR_OFFSET       0xC

/*
 * Arg0: Clock source select (0 .. 5 => IMGCLKOUT_0 .. IMGCLKOUT_5)
 * Arg1: Frequency select (0: 24MHz, 1: 19.2MHz)
 */
```

Combacia in ogni dettaglio con la DSDT del CHUWI: registro base `0x8000`, passo
`0x0C` fra un clock e il successivo, bit 0 frequenza (`CLKF`), bit 1 richiesta
(`CLKC`). E dice quello che serve sapere:

> **`1` = 19,2 MHz, `0` = 24 MHz.**

Il kernel passa `1`. Quindi il sensore riceve **19,2 MHz**, confermato da fonte
autorevole e non per inferenza. Le tabelle Rockchip a 24 MHz sono effettivamente
inadatte a questa piattaforma cosi' come sono.

### Ma i 24 MHz sono raggiungibili: e' una scelta software, non un limite hardware

Questo e' il punto piu' importante di tutta l'analisi, ed e' emerso solo qui.

Lo IMGCLKOUT **sa fare 24 MHz**: basta scrivere `0` nel bit 0. Non e' il
silicio a impedirlo, e' `int3472` che non lo chiede mai — il valore `1` e'
scritto a mano nel sorgente, e il clock registrato dal driver espone solo
`.recalc_rate`, senza `.set_rate` ne' `.determine_rate`. Un driver di sensore
che chiami `clk_set_rate(24 MHz)` non ottiene 24 MHz: ottiene silenzio, e poi un
`clk_get_rate()` che continua a rispondere con il valore dell'`SSDB`.

E' un buco vero in mainline, non una peculiarita' di questa macchina: la
piattaforma dichiara due frequenze e il kernel ne espone una sola, senza modo di
scegliere. Apre una via che prima non c'era:

> **Serie 0 (possibile): dare al clock di `int3472` un `.determine_rate` e un
> `.set_rate` che programmino il bit 0 via `_DSM`.** Se passa, il GC8034
> funziona con le tabelle Rockchip **cosi' come sono**, e il problema dei
> quattro registri non si pone piu'.

Con un'avvertenza da non nascondere in review: l'`SSDB` di **questa** macchina
dichiara 19,2 MHz per entrambi i sensori. Il firmware, cioe', dice che la
scheda e' pensata per 19,2. Forzare 24 MHz sarebbe andare contro quella
dichiarazione, e va verificato sperimentalmente prima di proporlo come
soluzione. Restano due ipotesi concorrenti, **entrambe verificabili** appena i
GPIO funzioneranno:

| | Ipotesi | Come si verifica |
|---|---|---|
| **A** | Il modulo e' davvero a 19,2 MHz e servono tabelle ritarate | le tabelle a 24 MHz danno frame corrotti o timeout CSI-2 |
| **B** | Il modulo vuole 24 MHz e l'`SSDB` riporta un default del template AMI | forzando `bit0 = 0` le tabelle Rockchip funzionano |

Prima di questa analisi l'unica strada sembrava "procurarsi il register guide
GalaxyCore". Ora ci sono due esperimenti da fare in casa.

## 5. Buona notizia: la catena clock del GC8034 non e' rotta

Dalla NVS, `C0GP = 1`: il GC8034 ha **un solo GPIO**, `POWER_ENABLE`. Nessun
`CLK_ENABLE`. Poiche' `int3472-discrete` registra il clock dentro
`skl_int3472_register_gpio_clock()`, chiamato solo per i GPIO di tipo
`CLK_ENABLE`, sembrava che il sensore posteriore restasse senza clock.

Non e' cosi'. Esiste `skl_int3472_register_dsm_clock()`, pensato esattamente per
questo caso, che registra il clock se il `_DSM` supporta la funzione 1. Nella
DSDT del CHUWI, DSC0 alla query (`Arg2 == 0`) **ritorna `0x03`** — bit 0 e bit 1
alzati, cioe' funzione 1 presente. Il ramo e' inoltre protetto da
`PCHS == PCHP || PCHS == PCHN`, e su questa macchina `PCHS = 0x03 = PCHN`
(Alder Lake-N): condizione soddisfatta.

Quindi il clock viene registrato per entrambi i sensori. Un problema in meno.

## 6. Verifica non riuscita: i registri ICLK non sono leggibili

Tentativo di leggere lo stato reale dei registri del clock, per vedere quale
frequenza il BIOS abbia selezionato.

Indirizzo ricavato dalla DSDT — `OperationRegion (CKOR, SystemMemory, SBRG +
(ICKP << 16) + 0x8000, 0x40)` — con i valori letti dalla NVS di piattaforma
(`PNVB = 0x758BFB18`, letterale nella DSDT):

```
PCHS = 0x03        PCHN, Alder Lake-N          (conferma che il parsing e' giusto)
SBRG = 0xFD000000  SBREG_BAR
ICKP = 0xAD        port ID ISCLK
       -> CKOR @ 0xFDAD8000
```

La finestra restituisce pero' **tutti `0xff`, per tutti i 64 byte**. Causa: il
**P2SB e' nascosto** — `00:1f.1` non compare in `lspci` — e in `/proc/iomem` la
risorsa `PNP0C02:02` copre `fd000000-fd68ffff`, che **non include**
`0xfdad8000`.

**La verifica e' inconclusa**, non negativa: non prova che i registri siano a
`0xff`, prova solo che da qui non si leggono.

> **Da ricontrollare quando la catena camera si accendera' davvero.** Se le
> scritture ACPI verso `SBREG_BAR` non arrivassero a destinazione con il P2SB
> nascosto, `CLKC` non abiliterebbe nulla e il sensore resterebbe senza clock —
> con un fallimento silenzioso, senza messaggi d'errore, che assomiglierebbe a
> un problema di tabelle registri pur non essendolo. Prima di dare la colpa ai
> registri, verificare che il clock ci sia.

## 7. `CJAK519`: la nota in reference/README.md era sbagliata

`reference/README.md` elenca fra le cose da non portare in mainline l'hack
`use_independent_gpio` di `int3472/discrete.c`, che matcha sul **nome del modulo
sensore** `CJAK519` invece che sull'`_HID`, e lo liquida come «quasi certamente
diverso sul CHUWI».

La NVS dice il contrario: `L1M0..MF` del sensore frontale e' **`CJAK519`**,
identico. L'hack riguarda quindi esattamente questo hardware e va capito prima
di scartarlo. (Il modulo posteriore si chiama invece `GC8034`.)

---

## 8. Lavoro anteriore: esiste, ma non risolve il problema

Cercando chi si agganci all'`_HID` ACPI — chiunque lo faccia e' per definizione
su una piattaforma IPU a 19,2 MHz — sono emersi tre repository di **pdamonte**,
tutti aggiornati al 2026-06-22, zero stelle, nessuna issue:

| Repo | Cosa contiene |
|---|---|
| `pdamonte/gc8034-dkms` | driver GC8034 con `_HID` `GCTI8034`, pacchetto DKMS |
| `pdamonte/gc5035-dkms` | idem per `GCTI5035` (file `gti5035.c`) |
| `pdamonte/ipu-bridge-gc-cameras-akmod` | akmod Fedora con le voci `ipu-bridge` |

Il README del primo suggerisce esattamente la riga che serve a noi:

```c
IPU_SENSOR_CONFIG("GCTI8034", 1, 336000000),
```

**Ma il problema del clock non e' risolto**, verificato confrontando i sorgenti
e non i README:

- `gc8034_global_regs_4lane` e' **identica byte per byte** a quella del BSP
  Rockchip: 233 registri, nessuno modificato.
- `GC8034_XVCLK_FREQ` vale ancora `24000000`; idem `GC5035_XVCLK_FREQ` nel
  companion, che quindi **non** deriva dalla patch Intel ma anch'esso da
  Rockchip.
- Sul disallineamento il codice si limita a un avviso:
  `dev_warn(dev, "xvclk mismatched, modes are based on 24MHz")`.

Sono quindi port del BSP Rockchip con incollata la glue ACPI, che dichiarano
336 MHz all'IPU mentre la PLL riceve 19,2 MHz invece dei 24 per cui i blob sono
tarati. Se davvero funzionassero, sarebbe **l'ipotesi B** del punto 4 a essere
vera — ma non c'e' alcuna prova che siano stati provati: nessuna stella,
nessuna issue, un solo commit visibile, e quel `dev_warn` suggerisce che
l'autore avesse notato il problema senza affrontarlo.

Utili comunque come **riferimento per la glue ACPI**, e come conferma che
qualcun altro ha incontrato lo stesso muro. Non come sorgente di valori.

Attenzione in caso di riuso: i tre repo non dichiarano una licenza nei metadati
GitHub, pur includendo un file `LICENSE`. Da chiarire prima di prendere anche
una sola riga, e comunque il codice a monte resta quello Rockchip, con la
catena di attribuzione descritta in `reference/README.md`.

## Dove lascia il progetto

| | Stato |
|---|---|
| GC5035 frontale | **Nessun ostacolo noto.** 2 lane = 2, tabelle gia' a 19,2 MHz |
| GC8034 posteriore | **Ostacolo reale.** 4 lane = 4, ma tabelle solo a 24 MHz |

Piste per il GC8034, riordinate dopo l'analisi del clock:

1. **Provare l'ipotesi B**: forzare `bit0 = 0` (24 MHz) e usare le tabelle
   Rockchip cosi' come sono. Se funziona, il problema sparisce e la patch da
   scrivere e' quella al clock di `int3472`, non alle tabelle del sensore.
   Richiede prima i GPIO, quindi `pinctrl-alderlake`.
2. **Provare l'ipotesi A**: tabelle Rockchip a 19,2 MHz senza modifiche. Se i
   frame sono corrotti o il CSI-2 va in timeout, servono i quattro registri
   ritarati.
3. Un altro BSP dello stesso sensore tarato a 19,2 MHz — restano da cercare i
   kernel vendor Amlogic, Allwinner, Unisoc, Spreadtrum e MediaTek. La ricerca
   su GitHub per `gc8034` restituisce **solo** fork del driver Rockchip, e
   `gc8034 19200000` non da' alcun risultato.
4. Il driver Windows di **questo** tablet. Da notare: sul disco non ne resta
   traccia — la partizione originale e' stata sovrascritta, `sda` ha solo una
   ESP e una ext4 — quindi andrebbe scaricato dal supporto CHUWI.
5. Register guide GalaxyCore, da chiedere al produttore.

Le prime due sono esperimenti da fare in casa, e non erano disponibili prima di
sapere che lo IMGCLKOUT ha due frequenze.

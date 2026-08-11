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
possibili, e mainline ne sceglie uno fisso. Poiche' lo stesso codice riporta
come rate il valore dell'`SSDB`, la lettura coerente e' che `bit0 = 1`
corrisponda ai 19,2 MHz dichiarati.

**Non esiste un percorso supportato per ottenere 24 MHz su questa piattaforma.**
Il GC8034 dovra' funzionare a 19,2 MHz, e le tabelle vanno ritarate: non e' una
preferenza, e' un vincolo.

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

## Dove lascia il progetto

| | Stato |
|---|---|
| GC5035 frontale | **Nessun ostacolo noto.** 2 lane = 2, tabelle gia' a 19,2 MHz |
| GC8034 posteriore | **Ostacolo reale.** 4 lane = 4, ma tabelle solo a 24 MHz |

Piste per il GC8034, in ordine di costo crescente:

1. Un altro BSP dello stesso sensore tarato a 19,2 MHz — vale la pena cercare
   fra i kernel vendor Amlogic, Allwinner, Unisoc, Spreadtrum e MediaTek.
2. Il driver Windows di **questo** tablet: se contiene le tabelle, sono per
   definizione quelle giuste per questo modulo, questo clock e queste lane.
3. Tentativo empirico sui quattro registri del punto 3, una volta che la
   macchina sara' in grado di alimentare i sensori.
4. Register guide GalaxyCore, da chiedere al produttore.

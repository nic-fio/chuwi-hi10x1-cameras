# 03 — Piano upstream

Cosa esattamente inviare a mainline perche' questa sequenza funzioni su un
kernel vanilla:

```
menuconfig -> VIDEO_GC5035, VIDEO_GC8034, PINCTRL_ALDERLAKE, VIDEO_INTEL_IPU6
make && make modules_install && reboot
apt install libcamera-tools pipewire-libcamera
# le fotocamere funzionano
```

## Perimetro: cosa NON va inviato

Chiudere subito il perimetro evita lavoro inutile. E' gia' tutto in mainline:

- **IPU6 + ISYS** — `drivers/media/pci/intel/ipu6/`
- **`ipu-bridge`** — esiste, va solo esteso (Serie 3)
- **`pinctrl-alderlake` con `INTC1057`** — dalla 5.18
- **firmware `ipu6ep_fw.bin`** — in `linux-firmware` e in Debian
- **userspace** — `libcamera` 0.4.0-7 con software ISP e `pipewire-libcamera`
  sono gia' pacchettizzati in Debian 13

Il buco e' **solo**: due driver sensore e due voci nel bridge.

---

## Serie 1 — `media: i2c: Add GC5035 image sensor driver`

| File | Contenuto |
|---|---|
| `Documentation/devicetree/bindings/media/i2c/galaxycore,gc5035.yaml` | binding, richiesto anche per uso solo-ACPI |
| `drivers/media/i2c/gc5035.c` | il driver |
| `drivers/media/i2c/Kconfig` | `VIDEO_GC5035` — **la voce che comparira' in menuconfig** |
| `drivers/media/i2c/Makefile` | `obj-$(CONFIG_VIDEO_GC5035) += gc5035.o` |
| `MAINTAINERS` | voce di manutenzione |

## Serie 2 — `media: i2c: Add GC8034 image sensor driver`

Struttura identica, `VIDEO_GC8034`.

## Serie 3 — `media: ipu-bridge: Add GC5035 and GC8034 sensor configs`

Un solo file: `drivers/media/pci/intel/ipu-bridge.c`. La macro, da
`include/media/ipu-bridge.h:20`, prende HID, **numero di link-frequency** e i
valori in hertz — non il numero di lane:

```c
#define IPU_SENSOR_CONFIG(_HID, _NR, ...)  \
	(const struct ipu_sensor_config) { .hid = _HID, .nr_link_freqs = _NR, \
	                                   .link_freqs = { __VA_ARGS__ } }
```

### Da dove viene la link frequency — correzione a quanto scritto prima

Una versione precedente di questo documento diceva che i valori "si leggono
dalla DSDT". **E' sbagliato**, e il file stesso lo dichiara. Commento normativo
sopra la tabella (`ipu-bridge.c:39-50`, verificato verbatim su mainline 7.2):

> *Extend this array with ACPI Hardware IDs of devices known to be working plus
> the number of link-frequencies **expected by their drivers**, along with the
> frequency values in hertz. This is somewhat opportunistic way of adding
> support for this for now **in the hopes of a better source for the
> information (possibly some encoded value in the SSDB buffer that we're
> unaware of) becoming apparent in the future**.*
>
> *Do not add an entry for a sensor that is not actually supported.*
>
> *Please keep the list sorted by ACPI HID.*

Tre conseguenze operative:

1. **La fonte canonica e' il driver**, non la DSDT. Il commento ammette
   esplicitamente che il valore **non** e' ricavabile dall'SSDB. Nel messaggio
   di commit si cita quindi `gc5035_link_freqs[] = { 438000000 }`, non un campo
   dell'SSDB. La DSDT resta utile come **conferma incrociata** (numero di lane),
   non come fonte.
2. **Ordinamento alfabetico per HID.** La tabella oggi inizia con `HIMX11B1`
   (riga 53): `GCTI5035` e `GCTI8034` vanno **prima di tutte le voci esistenti**.
3. *"Do not add an entry for a sensor that is not actually supported"* e' l'unico
   ostacolo formale all'invio anticipato — vedi sotto.

### Insidia DDR: fattore 2

`V4L2_CID_LINK_FREQ` e' il **clock DDR**, mentre i mode descriptor dei vendor
pubblicano il **bit rate per lane**, che e' il doppio. Per il GC5035:
876 Mbps/lane ÷ 2 = **438 MHz**. Prendere il valore del descrittore alla lettera
significa far girare la D-PHY dell'ISYS a velocita' doppia rispetto al sensore,
e non viene mai composto un frame. E' un errore gia' visto upstream (patch
HM1092) e il sintomo e' esattamente lo `ENOLINK` di questo progetto.

### Il valore puo' essere machine-specific

Precedente da tenere presente: `fb16c04a538e` cambia la link frequency di
`ov2740` a 180 MHz per i ThinkPad che usano `ipu-bridge`, mentre sui Chromebook
— dove il grafo viene da ACPI — resta 360 MHz. **Quindi i 438 MHz sono il
valore Intel per ADL-M e vanno confermati sul CHUWI**, non dati per buoni.

### Quando inviarla

Entrambi i pattern esistono upstream:

- **bridge-only, standalone**: lt6911uxe, T4KA3, MT9M114, OV05C10, OV5675 —
  sensori senza plumbing di alimentazione particolare
- **dentro la serie del driver o dell'enablement di piattaforma**: OV5670 su
  Dell 7212, OV8858 su Latitude 5285, IMX471 su X1 Carbon G14 — tutti casi in
  cui serviva anche `int3472`

Siccome la patch Intel per il GC5035 alza `INT3472_MAX_SENSOR_GPIOS` da 3 a 4,
**il GC5035 sul CHUWI ricade quasi certamente nel secondo gruppo**: serie
multi-patch.

Precedente esatto per il nostro caso: la patch HM1092 e' stata inviata prima
come `[PATCH 2/2]` col driver, poi **re-inviata da sola come `[PATCH v2]` con
una nota che dichiarava la dipendenza dal driver ancora in review**. E' lo
split deliberato, ed e' la strategia consigliata.

Se la Serie 3 arriva **dopo o insieme** ai driver, l'obiezione *"not actually
supported"* non si pone. Se si volesse anticiparla, si cita `440de616e76e` (che
ha importato in blocco HID dal driver out-of-tree senza giustificare i numeri) e
il fatto verificabile che `SONY471A` e `OVTI05C1` sono in tabella oggi senza che
`imx471.o`/`ov05c10.o` esistano in `drivers/media/i2c/Makefile`.

### Raccomandazione: partire dal solo GC5035

La link frequency del GC8034 sul CHUWI non e' difendibile: i valori Rockchip
(336/634 MHz) vengono da una piattaforma diversa e non esiste un driver Intel di
riferimento. **Inviare la Serie 3 con il solo `GCTI5035`** e rimandare il
`GCTI8034` a quando il suo driver sara' testato sull'hardware.

### Avvertenza: la macro potrebbe cambiare

Sakari Ailus ha proposto (30 luglio 2026) di estenderla con PCI ID e flag:

```c
IPU_SENSOR_CONFIG_MATCH_FL(_HID, _ID, _FLAGS, _NR, ...)
```

Se viene applicata prima della Serie 3, le voci vanno riscritte in quella forma.
**Da ricontrollare al rebase su `media_stage` immediatamente prima dell'invio.**

### Cosa non serve

Ogni commit che aggiunge una voce ha toccato **solo** `ipu-bridge.c`: nessun
`MAINTAINERS` (il file non e' coperto da nessun `F:`), nessun binding, nessuna
documentazione, nessun Kconfig, nessuna tabella HID duplicata in `ipu6/` o
`ipu7/`. Le review sono tipicamente un `Reviewed-by` secco piu' nit
sull'ordinamento.

## Serie 4 — quirk `int3472` *(condizionale)*

Serve solo se i `_DSM` di `DSC0`/`DSC1` usano tipi di funzione GPIO non
riconosciuti da `intel_skl_int3472_discrete`. Si stabilisce leggendo la DSDT.
Puo' benissimo non servire.

---

## Contenuto obbligatorio di ciascun driver

Il documento normativo esiste e va letto per primo:
**`Documentation/driver-api/media/camera-sensor.rst`**
(https://docs.kernel.org/driver-api/media/camera-sensor.html).

Stato verificato sul kernel 7.2, non su ricordi:

| Elemento | Stato | Nota |
|---|---|---|
| **`.enable_streams`/`.disable_streams`** | **obbligatorio** | `.s_stream` e' marcato *DEPRECATED* in `v4l2-subdev.h:454`. Usare `v4l2_subdev_s_stream_helper` per i chiamanti legacy |
| **`.init_state`** | **obbligatorio** | `.init_cfg` **non esiste piu'**; non deve toccare l'hardware |
| **`v4l2_subdev_state` centralizzato** | **obbligatorio** | niente mutex propria: `sd->state_lock = ctrl_handler.lock` |
| **runtime PM** | **obbligatorio** | abilitato in probe, disabilitato in remove, con autosuspend |
| **`.s_power`** | **vietato** | deprecato, rimosso |
| **PM di sistema** | **da NON implementare** | testuale in `camera-sensor.rst` |
| **helper CCI** | de facto obbligatorio | 43 Kconfig fanno `select V4L2_CCI_I2C` |
| **`get_selection`** CROP / CROP_BOUNDS / CROP_DEFAULT / NATIVE_SIZE | richiesto in review | `CROP_BOUNDS` = `NATIVE_SIZE` = pixel array intero |
| **PIXEL_RATE, LINK_FREQ, HBLANK, VBLANK, EXPOSURE, ANALOGUE_GAIN** | **obbligatori** | `LINK_FREQ` e' un menu int **read-only** |
| **`enum_frame_interval`** | **sconsigliato** per sensori raw | il frame rate si controlla con VBLANK |
| **ORIENTATION / ROTATION** | meccanismo obbligatorio | `v4l2_fwnode_device_parse()`; su x86 li fornisce ipu-bridge da `_PLD` e SSDB |
| **`v4l2-compliance`** | **obbligatorio, 0 failed** | *"Those tests need to pass before the patches go upstream"* |
| **`checkpatch --strict --max-line-length=80`**, build `W=1` con sparse e smatch | obbligatori | `maintainer-entry-profile.rst` |
| **`MAINTAINERS`** | **obbligatorio** | senza `T: git` se non si ha commit access. Serie gia' bloccate solo per questo |
| **Binding YAML per device solo-ACPI** | **non obbligatorio**, raccomandato | vedi sotto |

### Binding YAML: la risposta documentata

Sakari Ailus, thread OV05C10 (maggio 2025): *"I don't think there should be a
need for an I²C ID in any case, having just ACPI `_HID` is fine. **DT bindings
would of course be a plus**."*

Precedenti in mainline **senza** alcun YAML: `t4ka3`, `lt6911uxe`, `ov01a10`,
`ov2740`, `ov9734`, `ov13b10`, `hi556`, `hi847`, `imx208`, `imx319`, `gc0310`.

Nello stesso thread Krzysztof Kozlowski ha respinto **il binding** (proprieta'
inventate), non l'assenza di binding: **un binding fatto male costa piu' di
nessun binding**. Per GC5035 e GC8034, che hanno anche uso device-tree reale
(Rockchip), il binding conviene comunque — ma va scritto sul modello di
`galaxycore,gc05a2.yaml`, gia' accettato per lo stesso vendor.

### I rilievi che tornano in ogni review

Estratti da email reali di Sakari Ailus e Laurent Pinchart, 2024-2026:

1. Propagare l'errore col parametro `&ret` di `cci_write()`, non `NULL` seguito
   da un `if (ret)` dopo ogni chiamata
2. Runtime PM abilitato **prima** di registrare il subdev async
3. Con autosuspend: `pm_runtime_get_if_active()`, **non** `_if_in_use()`; in
   remove anche `pm_runtime_dont_use_autosuspend()`
4. Eliminare `cur_mode` e ogni stato dalla struct del device: derivarlo dallo
   state con `v4l2_find_nearest_size()`
5. `v4l2_link_freq_to_bitmap()` al posto del doppio ciclo di validazione
6. `V4L2_CID_PIXEL_RATE` e' il rate del **pixel array**, non del bus CSI-2
7. Controllare il valore di ritorno di `__v4l2_ctrl_modify_range()`
8. Polarita' del reset GPIO: `gpiod_set_value_cansleep(reset, 1)` = reset
   **attivo**. Errore ricorrente, contestato proprio sul `gc08a3`
9. Niente `clk_set_rate()` manuale: `devm_v4l2_sensor_clk_get()`
10. Dump di registri "magici": spezzare in tre liste (power-on, clock e link
    frequency, mode) e fattorizzare i comuni
11. Include in ordine alfabetico, `ret` dichiarato per ultimo, via i
    `dev_info()` di debug

### La domanda sulla provenienza arriva sempre

Sakari, sulla serie HM1092: *"**Is there copyright for this code?**"*
Jacopo Mondi, su IMX519: *"Should you retain the copyright as well?"*

Non viene mai citata formalmente la DCO: e' una domanda diretta a cui bisogna
avere la risposta **gia' pronta nella cover letter**. Per questo progetto la
provenienza e' articolata (Bitland, Google/ChromiumOS, Rockchip) e va
dichiarata spontaneamente. Vedi `reference/README.md`.

### Insidia specifica x86

`gc08a3.c` e `gc05a2.c` mainline sono nati su MediaTek/device-tree e danno per
scontati i regolatori. Su x86 quei regolatori li fornisce `INT3472` e l'ambiente
ACPI e' diverso. I driver devono tollerare entrambi i mondi — e' lo stesso
adattamento che de Goede fece per `ov2680` e `ov5693`.

---

## Da dove partire per il codice

Non si parte da zero: **`gc08a3.c` e `gc05a2.c` sono gia' in mainline**
(Zhi Mao, MediaTek), stesso produttore, gia' conformi agli standard attuali.

| Sensore | Registri e sequenze | Struttura e stile |
|---|---|---|
| **GC5035** | patch out-of-tree Intel `ipu6-drivers/patch/gc5035-on-adlm/` | `gc05a2.c` mainline |
| **GC8034** | driver BSP Rockchip `gc8034.c` | `gc08a3.c` mainline |

> **Attenzione a due trappole nei file di riferimento.**
>
> 1. `gc05a2.c` e `gc08a3.c` usano ancora `.s_stream`, oggi deprecato. Per un
>    driver nuovo servono `.enable_streams`/`.disable_streams`. Sono ottimi
>    template per struttura, controlli e uso di CCI — **non** per l'API di
>    streaming.
> 2. Per il lato x86/ACPI il modello migliore non e' nessuno dei due, ne'
>    `ov2740.c`: e' **`drivers/media/i2c/t4ka3.c`** (merged in 7.1). E'
>    ACPI-only, usa CCI, state centralizzato, `enable_streams`, selection
>    completo e runtime PM moderno. Il suo messaggio di commit e' di fatto la
>    checklist di modernizzazione che i revisori chiedono.
>
> Nota anche che `int3472_sensor_configs[]` — su cui si appoggia l'hack della
> patch Intel — **e' stato rimosso in 6.5**. Oggi il nome del supply deriva dal
> tipo di GPIO in `int3472_get_con_id_and_polarity()`, e il regolatore viene
> registrato sia in minuscolo sia in maiuscolo, proprio per non costringere i
> driver ad adeguarsi. Non riproporre quell'hack upstream.

**Provenienza**: il codice Rockchip e' GPL-2.0, quindi riutilizzabile, ma va
mantenuta la catena di attribuzione (`Co-developed-by`, `Signed-off-by`, credito
all'autore originale). Cosi' com'e' non passerebbe comunque: i driver BSP sono
blob di registri senza controlli V4L2, con ioctl custom e senza runtime PM.

**Ostacolo reale**: GalaxyCore non pubblica datasheet. Per il GC8034 il driver
Rockchip espone exposure/gain/VTS, sufficiente a costruire controlli veri; per
il GC5035 la patch Intel copre buona parte. Dove i registri restano opachi:
confronto tra mode table, oppure richiesta al vendor.

---

## Processo

1. Sviluppo e test su **vanilla** o sul tree `media_stage` — **non** sul 7.0
   locale, che ha un `.config` difettoso
2. `scripts/get_maintainer.pl` sulle patch
3. `scripts/checkpatch.pl --strict`
4. `v4l2-compliance` sul device
5. `b4` per gestire le serie
6. Invio a `linux-media@vger.kernel.org`
7. Follow-up su patchwork

---

## Il percorso fino a Linus

L'invio alla mailing list e' l'inizio, non la fine. Una patch accettata attraversa
**tre tree** prima di essere in un kernel rilasciato:

```
patch inviata
   |
   v
linux-media@vger.kernel.org        review pubblica, N giri di revisione
   |                               (patchwork traccia lo stato)
   v
media_stage                        il maintainer la applica qui
   |  git.linuxtv.org/media_stage.git
   |  <- qui girano build-bot, sparse, smatch, kernel test robot
   v
tree "media"                       raccolta per la merge window
   |
   v  pull request del maintainer dei media a Linus
   |
torvalds/linux                     merge window (~2 settimane dopo ogni vX.Y)
   |
   v  7 -rc, ~7 settimane
vX.Y                               release ufficiale: il codice e' in mainline
   |
   v
Debian / Ubuntu / Fedora           arriva agli utenti senza fare altro
```

### Tempi realistici — misurati, non stimati

Nove serie reali di driver sensore nuovi, accettate fra il 2024 e il 2026:

| Sensore | Autore | Revisioni | v1 → applicata | Release |
|---|---|---|---|---|
| OS05B10 | H. Bhavani (Silicon Signals) | 10 | **34 gg** | v7.0 |
| VD55G1 | B. Mugnier (ST) | 7 | **39 gg** | v6.16 |
| OV02E10 | Linaro | RFC→v4 | **39 gg** | v6.16 |
| OV2735 | H. Palaniya | 9 | **64 gg** | v6.18 |
| IMX111 | S. Ryhel (**indipendente**) | 5 | **86 gg** | v6.19 |
| **GC05A2** | Zhi Mao (MediaTek) | 7 | **103 gg** | v6.11 |
| S5KJN1 | Linaro | 4 | **106 gg** | v7.0 |
| **GC08A3** | Zhi Mao (MediaTek) | 9 | **214 gg** | v6.11 |
| VD56G3 | ST | 8 | **384 gg** | v6.16 |

Mediana: **86 giorni** dalla v1 all'applicazione. Piu' altri **60-120 giorni**
fra "applicata" e il tag di release. Totale realistico: **5-7 mesi**, non gli
8-12 che questo documento stimava prima di avere i dati.

Tre cose che i numeri dicono e le stime non dicevano:

- **Il numero di revisioni non predice la durata.** OS05B10 ha fatto 10 giri in
  34 giorni; GC08A3 ne ha fatti 9 in 214. Conferma diretta che la variabile
  dominante e' la latenza di risposta dell'autore, non la qualita' della v1.
- **Non serve un'azienda alle spalle.** IMX111 e' di uno sviluppatore
  indipendente, applicata in 86 giorni.
- **Applica quasi sempre Hans Verkuil** (9 casi su 11), non Sakari Ailus, che
  e' il revisore principale ma non il committer.

`RESEND` e' uno strumento legittimo e usato per sbloccare serie ignorate.

### Il rischio vero non e' il rifiuto, e' il silenzio

In patchwork lo stato `rejected` e' quasi solo pulizia di routine. **Quasi
nessun driver sensore viene formalmente rifiutato: muoiono in `new` o
`changes-requested`.** Non arriva un NAK, non arriva niente.

Casi reali:

- **AR0233** (2024): v2 gia' scritta in stile moderno, **nessuna risposta
  umana**, solo i bot. Morta per assenza di uno sponsor.
- **IMX492** (2022): ~30 rilievi in una sola review, mai una v2. Driver vendor
  incompleto spedito troppo presto.
- **IMX728**: tabella registri di **8000+ voci**. Laurent Pinchart:
  *"This table is way too big… doesn't this table also contain tuning data for
  your specific camera?"* Tre sottomettitori in 12 mesi, ognuno riparte da v1.
  Per confronto `gc05a2.c` ha ~420 registri e nessun dato di tuning.

### Precedente da conoscere: il GC5035 e' gia' morto una volta

Serie V3 di Xingyu Wu (Bitland, agosto 2020), ripresa da **Tomasz Figa
(Google/ChromiumOS) come v4 il 2 settembre 2020**. Review di Sakari Ailus e Rob
Herring, ultimo messaggio l'8 settembre 2020, poi silenzio. Il driver non e' mai
entrato.

Due conseguenze pratiche: i revisori se ne ricorderanno, e conviene **citare
esplicitamente quella serie nella cover letter** spiegando cosa e' cambiato
(hardware disponibile per i test, codice riscritto sugli standard attuali).

**Il GC8034 invece e' terreno vergine**: nessuna submission e' mai esistita.
Paradossalmente e' la strada piu' pulita delle due.

### Come si scompone il tempo

| Segmento | Durata | Chi lo controlla |
|---|---|---|
| Scrittura + test locale dei due driver | 1-3 mesi | **l'autore** |
| Cicli di review (5-10 versioni) | 3-8 mesi | **per lo piu' l'autore** |
| `media_stage` -> tree `media` -> merge window | 1-2 mesi | nessuno, cadenza fissa |
| Merge window -> tag `vX.Y` finale | ~2 mesi | nessuno |

Gli ultimi due segmenti sono **~3-4 mesi incomprimibili**: il kernel esce ogni
~9-10 settimane e chi manca una merge window aspetta la successiva. E' il
pavimento, non c'e' modo di scendere sotto.

#### La variabile dominante: il tempo di risposta dell'autore

I mesi in review sono **latenza, non lavoro**. In un ciclo tipico il revisore
risponde in 1-3 settimane; l'autore spesso in 2-3 mesi. Su dieci giri, la
differenza tra rispondere in 4 giorni e rispondere in 2 mesi e' la differenza
tra **4 mesi e 2 anni di calendario, a parita' di lavoro svolto**.

Le serie che ci mettono due anni quasi mai sono serie difficili: sono serie
seguite male. Questo e' il singolo fattore su cui vale la pena essere
disciplinati — piu' della qualita' della prima versione.

#### Cosa accorcia, concretamente

- **Le serie non sono sequenziali in review.** Serie 1 e 2 possono stare in
  revisione contemporaneamente. La Serie 3 (`ipu-bridge`, due voci in una
  tabella) e' di tipo che passa in 1-2 giri — settimane, non mesi — ma va
  sincronizzata con le altre perche' da sola sarebbe codice morto.
- **Partire da un template recente vale mesi.** `gc05a2.c` e `gc08a3.c` sono
  gia' conformi agli standard attuali e sono dello stesso vendor: buona parte
  dei commenti che un revisore farebbe su un driver scritto da zero non arriva
  proprio. E' una delle ragioni per cui il GC5035 (Fase 2) va per primo.
- **L'hardware in mano taglia il giro piu' lungo.** Il ping-pong che allunga di
  piu' e' quello sulle domande a cui l'autore non sa rispondere.

#### Il rischio di sforamento

Il **GC8034** e' il pezzo che puo' uscire da questa stima: registri da un BSP
Rockchip senza datasheet, e se exposure/gain non sono ricavabili si apre una
discussione dai tempi non prevedibili. Ragione in piu' per **non legarlo alla
stessa timeline del GC5035**: la Serie 1 non deve aspettare la Serie 2.

### Come si verifica che sia davvero fatto

Non ci si fida di "il maintainer ha detto ok". Si verifica:

```bash
# 1. e' in media_stage?
git clone https://git.linuxtv.org/media_stage.git
git -C media_stage log --oneline -- drivers/media/i2c/gc5035.c

# 2. e' nel tree di Linus?
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
git -C linux log --oneline -- drivers/media/i2c/gc5035.c

# 3. in quale release e' comparsa?
git -C linux describe --contains <sha>

# 4. la prova finale, su un tag di release, senza patch:
git -C linux checkout vX.Y
grep VIDEO_GC5035 linux/drivers/media/i2c/Kconfig
```

---

## Cosa fa accettare una patch (oltre al codice)

Il codice corretto e' necessario ma non sufficiente. Le serie muoiono piu'
spesso per ragioni di processo che per ragioni tecniche.

- **`Signed-off-by` con nome reale.** E' la Developer's Certificate of Origin:
  una dichiarazione che si ha il diritto di contribuire quel codice. Niente
  pseudonimi, niente indirizzi usa-e-getta. Per il codice derivato dal BSP
  Rockchip serve anche `Co-developed-by` + `Signed-off-by` dell'autore
  originale, con la sua email vera.
- **Email plain text.** Client che riscrivono le righe o inviano HTML rendono
  la patch inapplicabile e la serie viene scartata senza commenti.
  `git send-email`, testato prima su se stessi.
- **Un commit = una modifica logica.** Driver, Kconfig/Makefile, MAINTAINERS e
  binding sono commit separati nella stessa serie.
- **Il binding YAML prima del driver** nell'ordine della serie, e
  `make dt_binding_check` pulito.
- **Rispondere a tutti i commenti.** Anche a quelli che si respinge, con la
  motivazione. Un commento senza risposta blocca la serie a tempo indefinito:
  nessuno riprende in mano un thread lasciato a meta'.
- **Versioni incrementali nello stesso thread** (`v2`, `v3`, ...) con changelog.
  Reinviare come serie nuova azzera il contesto e irrita i revisori.
- **Non discutere lo stile.** Su preferenze di stile del maintainer si cede e
  si va avanti; l'energia si spende sulle questioni tecniche vere.
- **Riportare i tag ottenuti.** `Reviewed-by`, `Acked-by`, `Tested-by` raccolti
  vanno inclusi nelle versioni successive: sono il credito accumulato e
  segnalano che la serie sta maturando.

## Dopo il merge: l'impegno di manutenzione

La voce in `MAINTAINERS` non e' una firma d'autore, e' un impegno a rispondere
ai bug report per gli anni a venire. Se diventa insostenibile, si cede
esplicitamente con una patch a `MAINTAINERS` — non si sparisce.

## Aspettative realistiche

**5-15 revisioni per serie e' la norma su linux-media, non un segnale di
errore.** I revisori (Sakari Ailus in primis) sono rigorosi. Per i tempi, vedi
"Tempi realistici" sopra: il numero di giri conta meno della velocita' con cui
si chiude ciascuno.

Il vantaggio decisivo del progetto: **l'hardware c'e'**. La ragione piu' comune
per cui questi driver muoiono in review e' che nessuno puo' testarli. Un autore
che risponde "provato sull'hardware, ecco l'output di `v4l2-compliance`" ha un
peso che nessuna argomentazione teorica eguaglia.

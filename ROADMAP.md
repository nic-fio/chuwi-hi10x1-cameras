# ROADMAP

Fasi in ordine di dipendenza. Ogni fase ha un criterio di completamento
verificabile — niente "fatto al 90%".

---

## Fase 0 — Ambiente di sviluppo utilizzabile

Senza questo non e' possibile testare nulla.

- [x] **Journal persistente** — attivo dal 2026-08-11.
      `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`
      (il ring buffer si satura in poche ore e nasconde i messaggi di boot —
      e' cosi' che il Blocco 1 era sfuggito alla prima analisi). Ora serve a
      conservare i messaggi di boot del kernel nuovo anche dopo essere tornati
      al 7.0
- [x] ~~**Sbloccare i GPIO sul kernel locale** — `fix-pinctrl-alderlake.sh`~~
      **Non praticabile**: `/root/linux-7.0` non esiste e
      `/lib/modules/7.0/build` e' un symlink rotto, quindi non si possono
      compilare moduli per il kernel in esecuzione. Sostituito dalla Fase 1:
      il kernel vanilla nasce gia' con `PINCTRL_ALDERLAKE=y`, il che risolve i
      semafori 1-3 insieme. Vedi `docs/01-hardware.md`.
- [x] **Estrarre la DSDT** — fatto: `data/dsdt/dsdt.aml`, decompilata in
      `data/dsdt-analisi/` (`LNK0.dsl`, `LNK1.dsl`, `DSC0.dsl`, `DSC1.dsl`,
      `gnvs-offsets.txt`)
- [x] **Analizzare i nodi camera** — fatto, con **esito negativo**: nella DSDT
      i parametri **non ci sono**. `_HID`, `_CRS`, `SSDB`, `CLDB` e i `_DSM`
      sono tutti parametrizzati da variabili (`L1NL`, `L1CK`, `L1A0`, `L1DI`,
      `C1F*`…) che il BIOS scrive in **ACPI NVS** al boot. Nella DSDT sono solo
      dichiarate
- [x] **Leggere i valori dalla ACPI NVS** — `sudo ./scripts/read-camera-nvs.py`
      preceduto da **un boot del 7.0 con `iomem=relaxed`**. Primo tentativo
      fallito (`/dev/mem` -> `EPERM` per `IO_STRICT_DEVMEM=y`, `/proc/kcore` non
      copre la memoria E820-reserved, `acpidbg` non compilato, `acpi_call` non
      costruibile), ma la conclusione che ne era stata tratta — "serve un kernel
      nuovo" — era **sbagliata**: basta un parametro di boot sul kernel che c'e'
      gia'. Dimostrazione dal sorgente in `docs/06-azioni-root.md`, punto 2-bis
- [x] **Decidere se serve la Serie 4** (quirk `int3472`) — **no**. `C1GP` = 2,
      sotto la soglia di 6 del bug del `_DSM` duplicato, e i tipi GPIO usati
      (`0x00 RESET`, `0x0b POWER_ENABLE`) sono gia' gestiti da
      `int3472-discrete`. Confermato dai fatti: i sensori si accendono e
      catturano senza alcuna modifica a `int3472`

**COMPLETA** — 2026-08-11. I parametri CSI-2 di entrambi i sensori sono in
`docs/05-parametri-sensori.md`, il verdetto sulla Serie 4 e' «non serve», e
quello sullo scenario PLL e' in `docs/08-prova-hardware.md`: le tabelle a
24 MHz funzionano a 19,2 MHz, con i tempi scalati di 0,8.

### Sospetto chiuso: i sensori hanno eccome la risorsa I2C

Era il rischio piu' grosso della fase — «i sensori sono dichiarati presenti ma
senza `I2cSerialBus`, quindi nessun driver potrebbe mai agganciarsi». Nasceva
dall'assenza di client I2C sul 7.0, e dal fatto che nel `_CRS` di `LNK1`
esisteva un ramo (`L1DI == Zero`) che restituiva un buffer vuoto.

**Smentito due volte.** La NVS dice `L0DI` = 2 e `L1DI` = 1, non zero. E sul
kernel Debian i client ci sono:

```
/sys/bus/i2c/devices/i2c-GCTI5035:00   -> i2c-3, 0x3f
/sys/bus/i2c/devices/i2c-GCTI8034:00   -> i2c-2, 0x37
```

La causa dell'assenza sul 7.0 era una sola, ed era `pinctrl-alderlake`: niente
gpiochip `INTC1057` -> `int3472-discrete` in probe rimandata per sempre -> la
`_DEP` dei `GCTI*` mai soddisfatta -> nessuna enumerazione I2C. Un difetto di
`.config`, non di firmware.

---

## Fase 1 — Kernel vanilla di riferimento — **ABBANDONATA (2026-08-11)**

> **Provata e ritirata nella stessa giornata.** Il kernel
> `7.2.0-rc7-intelcam-geffb39a5b9a0` e' stato costruito, installato sulla ESP
> come immagine aggiuntiva e avviato a mano dalla UEFI Shell alle **18:08:52**
> del 2026-08-11. Il sistema e' rimasto su ~4 minuti, con wifi funzionante, e si
> e' spento in modo ordinato alle 18:12:49. Alle 18:13:30 la macchina era di
> nuovo sul 7.0, ripartito da solo: `startup.nsh` non era mai stato toccato.
>
> **Due cause indipendenti, entrambe di `.config`:**
>
> 1. **`CONFIG_DRM_I915=y`.** Un driver built-in fa probe prima che il rootfs
>    sia montato, quindi non trova `/lib/firmware`: DMC e GuC non caricati,
>    `GT0: Failed to initialize GPU, declaring it wedged`, schermo inservibile e
>    30 call trace a seguire. Il firmware e' installato e sul 7.0 funziona,
>    perche' li' `i915` e' un **modulo**
> 2. **`# CONFIG_BT is not set`** — terza trappola di `localmodconfig`. Su
>    questo tablet tastiera e mouse sono Bluetooth: senza stack BT **nessun
>    dispositivo di input**. Riferito dall'utente e confermato sulla config
>    archiviata
>
> Schermo morto piu' input morto = tablet inservibile, ed e' il motivo per cui
> la Fase 1 e' stata abbandonata. Il wifi invece funzionava
> (`wlo1: authenticated` alle 18:08:57), ma senza schermo ne' tastiera non era
> constatabile.
>
> Entrambe le correzioni sono ora **imposte e verificate da
> `scripts/build-kernel.sh`**, che si rifiuta di compilare se mancano. Journal
> in `data/boot-7.2-fallito.log`, analisi in `docs/06-azioni-root.md` punto 4.
>
> Poi la ESP e' stata ripulita: `vmlinuz-intelcam` e `intelcam.nsh` non ci sono
> piu', `vmlinuz`/`initrd.img`/`bootx64.efi` del 7.0 sono intatti e verificati,
> `startup.nsh` punta all'UUID giusto. **Decisione: non si riprova.**
>
> **La fase era comunque basata su una premessa falsa.** Serviva a sbloccare la
> lettura della NVS (Fase 0) e i semafori 1-3 (`PINCTRL_ALDERLAKE`). Per la NVS
> basta `iomem=relaxed` sul 7.0 — vedi punto 2-bis di `docs/06-azioni-root.md`.
> Per i semafori serve davvero un kernel con `PINCTRL_ALDERLAKE`, ma quello e'
> un problema di **test locale**, non di lavoro upstream: i driver si scrivono e
> si inviano contro `/home/nicfio/linux` senza che quel kernel giri qui.
>
> Cio' che resta valido di questa fase e' sotto: il tree, la `.config` e le
> conoscenze sul boot di questa macchina (bzImage vs vmlinux, PARTUUID
> `dc363afc-02`, la UEFI Shell interrompibile con ESC). Non e' lavoro sprecato —
> e' il tree su cui i due driver compilano.

### Cosa era stato fatto

- [x] Clonare vanilla — fatto: `/home/nicfio/linux`, mainline 7.2 (shallow).
      `/root/linux-7.0` non esiste piu', quindi non c'era alternativa
- [x] `.config` con `PINCTRL_ALDERLAKE`, `VIDEO_INTEL_IPU6`,
      `INTEL_SKL_INT3472`, `IPU_BRIDGE`, `I2C_DESIGNWARE_PLATFORM`, e i due
      template `VIDEO_GC05A2`/`VIDEO_GC08A3` — riproducibile con
      `./scripts/build-kernel.sh`, copia in `config/`
- [x] `.config` estesa per **sbloccare la lettura della NVS**: `ACPI_DEBUGGER=y`,
      `ACPI_DEBUGGER_USER=m`, `IO_STRICT_DEVMEM` disabilitato. Senza questi il
      kernel nuovo erediterebbe lo stesso muro del 7.0 e la Fase 0 resterebbe
      bloccata anche dopo il boot
> **`localmodconfig` ha una seconda trappola, peggiore della prima.** La config
> generata non aveva **ne' console su framebuffer ne' driver wifi**: senza
> `FRAMEBUFFER_CONSOLE` lo schermo diventa nero appena `i915` prende il
> controllo (nessun prompt di login), senza `iwlwifi` non c'e' rete e quindi
> nemmeno SSH come riserva. Insieme: si sarebbe avviato alla cieca, senza modo
> di sapere se aveva funzionato. Trovata prima del riavvio il 2026-08-11 e
> corretta in `build-kernel.sh`, che ora la verifica esplicitamente.

- [x] Build completata — `7.2.0-rc7-intelcam-geffb39a5b9a0` (#3), 2026-08-11.
      `bzImage` con entry point EFI handoff a 32 e 64 bit; `EXT4_FS`, `ATA`,
      `SATA_AHCI`, `BLK_DEV_SD`, `MSDOS_PARTITION` tutti `=y`, quindi **nessun
      initrd necessario**. Il disco e' MBR (`dos`) su AHCI, coerente.
      Costruiti `gc5035.ko`, `gc8034.ko`, `intel-ipu6.ko`, `acpi_dbg.ko`,
      `iwlwifi.ko`; `pinctrl-alderlake` e `fbcon` sono built-in. Config
      archiviata in `config/intelcam-7.2.0-rc7.config`
- [x] **Installazione** — fatta, e **senza modificare nulla**. Il bootloader si
      e' rivelato essere la **UEFI Shell** (`EFI/BOOT/bootx64.efi`, 1 MB) che
      esegue `startup.nsh` in automatico. Siccome `startup.nsh` si interrompe
      con ESC, non serviva editarlo: basta aggiungere l'immagine e lanciarla a
      mano. Sulla ESP ora ci sono `vmlinuz-intelcam` (md5 verificato) e
      `intelcam.nsh`; `startup.nsh` e' bit-identico all'originale, quindi il
      7.0 resta il default e riparte da solo. Moduli in
      `/lib/modules/7.2.0-rc7-intelcam-geffb39a5b9a0` (30). Procedura completa
      in `docs/06-azioni-root.md`, punto 4.
      **Poi disinstallato**: i due file non sono piu' sulla ESP
- [x] Boot tentato il 2026-08-11 alle 18:08 — **fallito** (`DRM_I915=y` senza
      initrd), ma con due risultati acquisiti e conservati nel journal:
      **`ipu-bridge` riconosce `GCTI5035:00` e `GCTI8034:00` e dichiara
      "Connected 2 cameras"** — il semaforo 4 era `[OK]` — e per contro
      **nessun client I2C, nessun probe di `gc5035`/`gc8034`**, che conferma il
      sospetto della Fase 0
- [ ] ~~`collect-diag.sh` con semafori 1-3 `[OK]`~~ — non raggiungibile senza
      questo kernel. I semafori 1-3 restano `[KO]` e il progetto va avanti lo
      stesso: sono diagnostica locale, non requisiti upstream
- [ ] Installare `v4l-utils` (`v4l2-ctl`, `v4l2-compliance`, `media-ctl`) —
      **assenti** sulla macchina. **Questo serve ancora**, indipendentemente dal
      kernel: e' l'output che i revisori chiedono. Spostato in Fase 2

**Chiusa come**: abbandonata. Nessun criterio di completamento da soddisfare.

---

## Fase 2 — GC5035 (frontale) — il piu' facile

Si parte da qui perche' esiste gia' codice Intel da cui prendere i registri.

> **Precedente da conoscere: questo driver e' gia' morto una volta.** Serie di
> Xingyu Wu (Bitland, agosto 2020), ripresa da Tomasz Figa (Google/ChromiumOS)
> come v4 il 2 settembre 2020; review di Sakari Ailus e Rob Herring, ultimo
> messaggio l'8 settembre 2020, poi silenzio. I revisori se ne ricorderanno:
> conviene citare quella serie nella cover letter e dire cosa e' cambiato —
> l'hardware c'e' per i test, e il codice e' riscritto sugli standard attuali.
>
> Il GC8034 (Fase 3) non ha invece **nessun** precedente: terreno vergine.

- [x] Scheletro da `gc05a2.c` mainline — `patches/wip/gc5035.c`, 854 righe,
      compila su 7.2, `W=1` pulito, `checkpatch --strict` pulito, alias ACPI
      `acpi*:GCTI5035:*` corretto. **Non funzionante**: tabelle registri
      segnaposto e guadagno limitato a 1x. Vedi `patches/wip/README.md`
- [x] Registri e mode dalla patch Intel `gc5035-on-adlm` — importati e
      **verificati sul silicio**, con le righe di copyright di Bitland, Google
      e Intel conservate nel file. L'attribuzione e' a posto: vedi
      `reference/README.md`, sezione «Cosa serve davvero»
- [x] Adattamento ADL-M -> ADL-N
- [x] Controlli V4L2 completi — `ANALOGUE_GAIN` implementato e misurato:
      16x chiesti, 15,7x ottenuti
- [x] Runtime PM, helper CCI, match table ACPI + OF
- [x] Binding YAML — scritto e validato con `make dt_binding_check`
- [x] Voce `GCTI5035` in `ipu_supported_sensors[]` — bozza applicata al tree
- [x] **Prima immagine catturata** — 2026-08-11, 2592x1944 SGRBG10,
      `data/prima-cattura-2026-08-11/gc5035-soffitto.png`
- [x] `v4l2-compliance` — 45/46. L'unico fallimento (eventi sui controlli)
      e' condiviso con `gc05a2`, `gc08a3`, `ov2740`, `ov08x40` e `t4ka3`
- [x] `checkpatch.pl --strict` pulito

**COMPLETA** — 2026-08-11: fotogramma riconoscibile dalla frontale, su kernel
Debian 6.12 con i driver caricati come moduli fuori albero (`build-6.12/`).

Corretta anche la link frequency, che la patch Intel dichiarava a 438 MHz:
quella vera e' **422,4 MHz**, cioe' `19,2 MHz x 22`, e il driver ora la ricava
dal clock invece di scriverla a mano. Vedi `docs/08-prova-hardware.md`.

---

## Fase 3 — GC8034 (posteriore) — il piu' duro

Nessun codice x86/ACPI esistente. Solo il BSP Rockchip device-tree.

> **Si e' sovrapposta alla Fase 2, non l'ha seguita.** I due driver sono stati
> scritti e provati insieme, e viaggiano nella stessa serie. Le fasi sono
> numerate per dipendenza logica, non per esecuzione seriale.

- [x] Scheletro da `gc08a3.c` mainline — `patches/wip/gc8034.c`, 897 righe,
      compila, `W=1` e `checkpatch --strict` puliti. **Ora testato.**
      `ANALOGUE_GAIN` verificato: 7,66x chiesti, 7,9x misurati
- [x] Registri dal BSP Rockchip — importati e **funzionanti sul silicio**,
      nonostante siano tarati a 24 MHz e qui l'MCLK sia 19,2. Resta aperta
      la riga di copyright Rockchip, conservata nel file nuovo
- [x] Stessa checklist della Fase 2 — `v4l2-compliance` 45/46,
      **prima immagine** 3264x2448 SRGGB10 il 2026-08-11
- [x] Voce `GCTI8034` in `ipu_supported_sensors[]` — bozza applicata al tree
- [x] **Deciso come dichiarare la link frequency: derivata a runtime** da
      `clk_get_rate()`, moltiplicatore 14. Cosi' lo stesso driver vale sui
      19,2 MHz di IPU6 e sui 24 MHz di un device-tree. Scalato allo stesso modo
      il pixel rate d'array e l'attesa di 8192 cicli prima del primo I2C, che
      il BSP aveva fissato in microsecondi a 24 MHz

**COMPLETA** — 2026-08-11: fotogramma riconoscibile dalla posteriore a 8 MP.

Il rischio numero uno del progetto — «le uniche tabelle disponibili sono a
24 MHz e questa piattaforma da' 19,2» — si e' rivelato **inesistente**: le
tabelle funzionano cosi' come sono, con tutti i tempi scalati di 0,8.

---

## Fase 4 — Userspace

- [ ] `apt install libcamera-tools pipewire-libcamera gstreamer1.0-libcamera`
- [ ] `cam -l` elenca entrambi i sensori
- [ ] Software ISP produce un'immagine corretta (bilanciamento, colori)
- [ ] Verifica in un'applicazione reale (GNOME Camera / browser via PipeWire)

**Completa quando**: una videochiamata nel browser usa la camera frontale.

---

## Fase 5 — Invio upstream

### Prerequisiti formali (una volta sola, prima del primo invio)

Sono i motivi piu' banali per cui una serie viene ignorata senza nemmeno essere
letta. Vanno sistemati prima, non alla terza revisione.

- [ ] **Identita' reale**: `git config user.name` e `user.email` con nome e
      cognome veri. Pseudonimi e indirizzi usa-e-getta non sono accettati: il
      `Signed-off-by` e' una dichiarazione legale (DCO)
- [x] **DCO compreso**: `Documentation/process/submitting-patches.rst`,
      sezione "Sign your work". Letta il 2026-08-11, e la clausola **(b)** ha
      chiuso un blocco che il progetto credeva di avere: il riuso di codice
      GPL-2.0 dentro il kernel **non richiede il permesso di nessuno**, basta
      conservare i copyright e dichiarare la provenienza. Vedi
      `reference/README.md`, sezione «Cosa serve davvero»
- [ ] **Email in plain text**, niente HTML, niente riscrittura delle righe,
      niente allegati. `git send-email` funzionante e testato su se' stessi
- [ ] **`b4` installato** e configurato
- [ ] Iscrizione a `linux-media@vger.kernel.org`

### Cosa si invia, e a chi — **tre invii indipendenti**

Deciso il 2026-08-11 dopo la revisione pre-invio. Il rischio da evitare e'
sempre lo stesso: una serie che aspetta un'altra somma due timeline invece di
sovrapporle, e basta che una si impantani perche' si fermi tutto.

1. [ ] **Serie media, 5 patch** a `linux-media` — `patches/wip/serie/`.
      I due binding, i due driver e le due voci di `ipu-bridge`, con cover
      letter. Le voci di `ipu-bridge` stanno **dentro** la serie e non a
      parte, perche' senza di loro i driver non sono provabili su IPU6 e la
      cover letter spiega perche' i numeri sono quelli.
2. [ ] **`int3472`, 1 patch** a `platform-driver-x86` — `patches/wip/int3472/`.
      Sottosistema diverso, nessun legame con le altre. Non serve piu' a far
      funzionare niente: resta perche' corregge un buco vero, cioe' una
      piattaforma che espone due frequenze e un kernel che ne offre una.
3. [ ] **Oops di `ipu6-isys`, 1 patch** a `linux-media` — `patches/wip/ipu6-fix/`.
      Non e' nostro codice: e' un NULL deref di mainline trovato provocandolo.
      Si invia **subito e da sola**, con il suo `Fixes:`. Una correzione di un
      crash non deve aspettare una serie di feature.

Destinatari gia' calcolati in `patches/wip/destinatari.txt`.

**Perche' non piu' "Serie 1, 2, 3, 4".** La numerazione vecchia descriveva
dipendenze che non esistono piu': la Serie 4 non serve, la Serie 0/int3472
nemmeno, e le due voci di `ipu-bridge` non sono codice morto perche' i driver
arrivano nella stessa serie.

Per ciascuna:

- [ ] `get_maintainer.pl`
- [ ] `checkpatch.pl --strict`
- [ ] cover letter con: hardware di test, cosa e' stato verificato, provenienza
      del codice riusato
- [ ] invio via `b4` a `linux-media@vger.kernel.org`
- [ ] copia in `upstream/` di quanto inviato
- [ ] feedback dei revisori archiviato in `upstream/`, revisione successiva

### Gestione della review — dove muoiono le serie

> **La variabile dominante e' il tempo di risposta**, non la qualita' della
> prima versione. Il revisore risponde in 1-3 settimane, l'autore spesso in
> 2-3 mesi: su dieci giri e' la differenza tra 4 mesi e 2 anni di calendario,
> a parita' di lavoro svolto. Obiettivo operativo: **`v(N+1)` entro una
> settimana** dal feedback, sempre. Se una settimana non basta, rispondere
> comunque nel thread dicendo che si sta lavorando.

- [ ] **Rispondere a ogni commento**, anche a quelli che si respingono, con la
      motivazione tecnica. Il silenzio su un commento blocca la serie
- [ ] **Un `v(N+1)` per ogni giro**, con changelog per-versione nella cover
      letter (`b4` lo gestisce) e link alla versione precedente
- [ ] **Ping dopo ~2 settimane** di silenzio, non prima
- [ ] **Non ripartire da capo**: stessa serie, stesso thread, versione
      incrementata. Reinviare come serie nuova azzera il contesto dei revisori
- [ ] Raccogliere e conservare i tag `Reviewed-by` / `Acked-by` / `Tested-by`
      ottenuti, e riportarli nelle versioni successive

**Completa quando**: ogni serie ha ricevuto un `Reviewed-by` dal maintainer di
competenza e nessun commento resta aperto.

---

## Fase 6 — Accettazione e integrazione in mainline

Qui il lavoro non e' piu' scrivere codice: e' seguire il codice lungo la catena
dei tree finche' non arriva a Linus. Sono passaggi che avvengono su tempi altrui.

- [ ] **Applicata in `media_stage`** — verificare con
      `git log --oneline --author=<propria-email>` su
      `https://git.linuxtv.org/media_stage.git`
- [ ] **Nessuna regressione segnalata** dai test automatici sul tree
      (build-bot, `smatch`, `sparse`, kernel test robot). Se arriva un report,
      la fix e' responsabilita' dell'autore ed e' urgente: una patch che rompe
      la build viene rimossa, non corretta da altri
- [ ] **Migrata nel tree `media`** e inclusa nella pull request del maintainer
      dei media verso Linus, nella merge window
- [ ] **Merge nel tree di Linus** — verificare su
      `git.kernel.org/.../torvalds/linux.git`:
      `git log --oneline -- drivers/media/i2c/gc5035.c`
- [ ] **Annotare la versione del kernel** in cui e' comparsa (`git describe
      --contains <sha>`) in `upstream/`
- [ ] **Presente nel tag di release finale** `vX.Y` (non solo in `-rc`)

**Completa quando**: `grep VIDEO_GC5035 drivers/media/i2c/Kconfig` trova la voce
su un clone pulito di `torvalds/linux` a un tag di release ufficiale.

---

## Fase 7 — Verifica finale

Riproduce da zero l'obiettivo dichiarato nel README, senza scorciatoie.

- [ ] Kernel vanilla **scaricato da kernel.org**, tag di release che include le
      serie, **nessuna patch locale applicata**
- [ ] Solo `.config`: `VIDEO_GC5035`, `VIDEO_GC8034`, `PINCTRL_ALDERLAKE`,
      `VIDEO_INTEL_IPU6`
- [ ] `collect-diag.sh` mostra **cinque `[OK]`**
- [ ] Entrambe le fotocamere catturano

**Obiettivo del progetto raggiunto.**

---

## Fase 8 — Dopo il merge (manutenzione)

L'accettazione crea un impegno: la voce `MAINTAINERS` dei due driver e' un
impegno a rispondere. Non e' facoltativo e non ha scadenza.

- [ ] Rispondere ai bug report sui due driver
- [ ] Verificare che non si rompano nelle release successive
- [ ] Se il ruolo non e' piu' sostenibile, cederlo esplicitamente con una patch
      a `MAINTAINERS`, non abbandonarlo

---

## Decisioni aperte

| Questione | Stato |
|---|---|
| Serve la Serie 4 (quirk `int3472`)? | **RISOLTA: no.** `C1GP` = 2 e i tipi GPIO usati sono gia' gestiti. Confermato dai fatti: le camere funzionano senza toccare `int3472` |
| I registri exposure/gain del GC8034 sono ricavabili dal BSP? | **RISOLTA: si'.** Exposure `0x03/0x04`, gain a indice su `0xb6` + tabella a 9 voci, blanking `0x07/0x08`. Guadagno poi **misurato**: 7,66x chiesti, 7,9x ottenuti |
| Le voci di `ipu-bridge`: patch a se' o dentro la serie? | **RISOLTA: dentro.** Arrivano nella stessa serie dei driver, quindi non sono codice morto e non c'e' niente da sincronizzare |
| La link frequency del CHUWI coincide con quella della patch Intel? | **RISOLTA: no, e la patch Intel sbaglia.** Misurata 422,4 MHz (`19,2 x 22`) contro i 438 dichiarati. Il GC8034 sta a 268,8 (`19,2 x 14`) contro i 336 del BSP |
| Come dichiarare la link frequency nei due driver? | **RISOLTA: derivata a runtime** da `clk_get_rate()`, moltiplicatori 22 e 14. Il modello del driver ora prevede il frame rate misurato |
| Contattare GalaxyCore per i datasheet? | **non serve piu' per far funzionare i sensori.** Resterebbe utile solo per documentare i blob PLL |
| Un solo maintainer per entrambi i driver? | proposta: si', l'autore del progetto |

## Rischi noti

- ~~**Le PLL non sono documentate — rischio tecnico numero uno.**~~
  **RIENTRATO il 2026-08-11.** Restano blob non commentati, ma non serve
  toccarli: le tabelle producono immagini corrette su questa piattaforma cosi'
  come sono. Non sapere *come* cambiare la link frequency non e' piu' un
  problema, perche' non c'e' motivo di cambiarla — basta **dichiararla giusta**,
  e ora si sa quanto vale perche' e' stata misurata. Vedi
  `docs/08-prova-hardware.md`.
- **Nessun datasheet pubblico GalaxyCore.** Non blocca piu' il funzionamento;
  resta un limite per la documentazione dei blob e per rispondere a un revisore
  che chieda «cosa fa questo registro».
- **Review lunga.** 5-15 revisioni per serie e' la norma su linux-media, non un
  segnale di errore.
- **Adattamento x86/ACPI.** I template mainline assumono device-tree e
  regolatori espliciti; su x86 li fornisce `INT3472`. Precedenti utili: il
  lavoro di de Goede su `ov2680` e `ov5693`.
- **Il kernel locale 7.0 ha un `.config` difettoso.** Non usarlo come
  riferimento per il lavoro upstream.

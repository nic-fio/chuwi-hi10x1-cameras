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
- [ ] **Leggere i valori dalla ACPI NVS** — `sudo ./scripts/read-camera-nvs.py`
      preceduto da **un boot del 7.0 con `iomem=relaxed`**. Primo tentativo
      fallito (`/dev/mem` -> `EPERM` per `IO_STRICT_DEVMEM=y`, `/proc/kcore` non
      copre la memoria E820-reserved, `acpidbg` non compilato, `acpi_call` non
      costruibile), ma la conclusione che ne era stata tratta — "serve un kernel
      nuovo" — era **sbagliata**: basta un parametro di boot sul kernel che c'e'
      gia'. Dimostrazione dal sorgente in `docs/06-azioni-root.md`, punto 2-bis
- [ ] **Decidere se serve la Serie 4** (quirk `int3472`) — dipende dai tipi
      GPIO in NVS, che lo script gia' confronta con `int3472.h`

**Completa quando**: i parametri CSI-2 di entrambi i sensori sono documentati in
`docs/05-parametri-sensori.md` — il file esiste gia', con le sezioni **[DSDT]**
ancora vuote — e il verdetto sullo scenario PLL e sulla Serie 4 e' scritto.
I semafori 1-3 si risolvono in Fase 1, non piu' qui.

> **Questa fase torna a essere la prima.** Dal 2026-08-11 non dipende piu' dalla
> Fase 1, che e' stata abbandonata: per leggere la NVS serve `iomem=relaxed`,
> non un kernel diverso. L'ordine di esecuzione reale e'
> **Fase 0 -> Fase 2/3 -> Fase 5**.

### Sospetto aperto: i sensori potrebbero non avere risorsa I2C

Raccolto da sysfs sul 7.0, senza root:

- `GCTI5035:00` e `GCTI8034:00` esistono, `_STA` = `0x0F` (presente, abilitato,
  funzionante). `_HID` e' `HCID(One)`, calcolata da `L1SM`: che il kernel ne
  ricavi `GCTI5035` **dimostra che la NVS e' popolata** e coerente
- i sei bus `Synopsys DesignWare` (`i2c-10`..`i2c-15`) sono registrati
- `intel_skl_int3472_discrete` e' caricato
- **nessun client I2C**: `/sys/bus/i2c/devices/` non ha voci `N-00XX`

Nel `_CRS` di `LNK1` (`data/dsdt-analisi/LNK1.dsl:136`) l'unico ramo che
restituisce un buffer vuoto e' `L1DI == Zero`. Se la NVS conferma `L*DI = 0`,
il firmware dichiara i sensori presenti **senza risorsa I2C**: nessun client,
nessun aggancio possibile, per qualunque driver. Da chiarire **prima** di
lavorare sulle tabelle registri.

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
- [ ] Registri e mode dalla patch Intel `gc5035-on-adlm` — **bloccato
      sull'attribuzione**, vedi `reference/README.md`
- [ ] Adattamento ADL-M -> ADL-N
- [ ] Controlli V4L2 completi (vedi `docs/03-piano-upstream.md`) — manca solo
      `ANALOGUE_GAIN`, oggi limitato a 1x perche' manca la tabella AGC
- [x] Runtime PM, helper CCI, match table ACPI + OF
- [x] Binding YAML — scritto, **non validato**: manca `dtschema`
- [x] Voce `GCTI5035` in `ipu_supported_sensors[]` — bozza applicata al tree
- [ ] **Prima immagine catturata** da `/dev/video*`
- [ ] `v4l2-compliance` pulito
- [ ] `checkpatch.pl --strict` pulito

**Completa quando**: si cattura un fotogramma riconoscibile dalla frontale su
kernel vanilla + patch locali.

---

## Fase 3 — GC8034 (posteriore) — il piu' duro

Nessun codice x86/ACPI esistente. Solo il BSP Rockchip device-tree.

> **Si sovrappone alla Fase 2, non la segue.** Appena la Serie 1 e' inviata
> (Fase 5), il GC5035 entra in una fase di attesa fatta di giri di review:
> quel tempo si usa per scrivere il GC8034. Le fasi sono numerate per
> dipendenza logica, non per esecuzione seriale.

- [x] Scheletro da `gc08a3.c` mainline — `patches/wip/gc8034.c`, 897 righe,
      compila, `W=1` e `checkpatch --strict` puliti. **Non testato.**
      `ANALOGUE_GAIN` qui e' gia' implementato davvero, non un segnaposto
- [ ] Registri dal BSP Rockchip, **con attribuzione corretta** (GPL-2.0:
      `Co-developed-by` / `Signed-off-by`, credito all'autore originale)
- [ ] Stessa checklist della Fase 2
- [x] Voce `GCTI8034` in `ipu_supported_sensors[]` — bozza applicata al tree

**Completa quando**: si cattura un fotogramma dalla posteriore.

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
- [ ] **DCO compreso**: `Documentation/process/submitting-patches.rst`,
      sezione "Sign your work"
- [ ] **Email in plain text**, niente HTML, niente riscrittura delle righe,
      niente allegati. `git send-email` funzionante e testato su se' stessi
- [ ] **`b4` installato** e configurato
- [ ] Iscrizione a `linux-media@vger.kernel.org`

### Ordine di invio — **non sequenziale**

L'elenco numerato indica le dipendenze, **non un ordine da rispettare uno alla
volta**. Aspettare che la Serie 2 sia pronta prima di inviare la Serie 1
significa sommare due timeline invece di sovrapporle, e la Serie 2 e' quella a
rischio di sforamento (vedi `docs/03-piano-upstream.md`, "Il rischio di
sforamento"): i registri del GC8034 vengono da un BSP senza datasheet.

1. [ ] Serie 1 — `media: i2c: Add GC5035 image sensor driver`
      **Si invia appena e' pronta.** Non attende la Serie 2.
2. [ ] Serie 2 — `media: i2c: Add GC8034 image sensor driver`
      In review **in parallelo** alla Serie 1. Se si impantana sui registri,
      non trascina con se' le altre.
3. [ ] Serie 3 — `media: ipu-bridge: ...`
      Unica vera dipendenza. Da sola sarebbe codice morto, quindi si sincronizza
      con **la prima delle due che entra in `media_stage`**, aggiungendo in quel
      momento solo la voce del sensore gia' accettato. La seconda voce segue
      quando la sua serie e' accettata. Vedi sotto.
4. [ ] Serie 4 — quirk `int3472`, solo se necessaria. Indipendente dalle altre:
      si invia quando serve, non in coda.

**Decisione sulla Serie 3 — una patch o due.** Se le Serie 1 e 2 procedono con
tempi simili, una sola patch con entrambe le voci. Se la Serie 2 rallenta —
scenario da mettere in conto — si spezza in due patch da una voce ciascuna,
per non tenere in ostaggio il GC5035. Da decidere al momento, sulla base di
dove stanno le due serie, non ora.

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

L'accettazione crea un impegno: la voce `MAINTAINERS` delle Serie 1 e 2 e' un
impegno a rispondere. Non e' facoltativo e non ha scadenza.

- [ ] Rispondere ai bug report sui due driver
- [ ] Verificare che non si rompano nelle release successive
- [ ] Se il ruolo non e' piu' sostenibile, cederlo esplicitamente con una patch
      a `MAINTAINERS`, non abbandonarlo

---

## Decisioni aperte

| Questione | Stato |
|---|---|
| Serve la Serie 4 (quirk `int3472`)? | dipende dai `_DSM` nella DSDT — Fase 0 |
| I registri exposure/gain del GC8034 sono ricavabili dal BSP? | **RISOLTA: si'.** Exposure `0x03/0x04`, gain a indice su `0xb6` + tabella a 9 voci, blanking `0x07/0x08`. Vedi `docs/05-parametri-sensori.md` |
| Serie 3: una patch con due voci o due patch da una? | da decidere in Fase 5, in base a quanto divergono i tempi di Serie 1 e 2 |
| La link frequency del CHUWI coincide con quella della patch Intel? | **da cui dipende tutto** — vedi Rischi. Si sa solo dopo la DSDT |
| Contattare GalaxyCore per i datasheet? | da valutare se i registri restano opachi |
| Un solo maintainer per entrambi i driver? | proposta: si', l'autore del progetto |

## Rischi noti

- **Le PLL non sono documentate — rischio tecnico numero uno.** Per entrambi i
  sensori i registri che determinano PLL e timing D-PHY sono blob senza
  commenti (GC5035: `0xf4`, `0xf5`, `0xf6`, `0xf8`, `0xf9`, `0xd3`, `0xee` e il
  blocco MIPI in pagina 3). Conseguenza concreta: **non si sa come cambiare la
  link frequency.** I 438 MHz della patch Intel sono un blob, non un calcolo.
  Se la DSDT del CHUWI dichiara un valore diverso — o un numero di lane diverso
  — non e' ricavabile quali byte toccare. Si scopre in quale scenario siamo
  solo estraendo la DSDT. Vedi `docs/05-parametri-sensori.md`.
- **Nessun datasheet pubblico GalaxyCore.** Mitigazione: confronto tra mode
  table, driver esistenti dello stesso vendor, eventuale contatto col vendor.
- **Review lunga.** 5-15 revisioni per serie e' la norma su linux-media, non un
  segnale di errore.
- **Adattamento x86/ACPI.** I template mainline assumono device-tree e
  regolatori espliciti; su x86 li fornisce `INT3472`. Precedenti utili: il
  lavoro di de Goede su `ov2680` e `ov5693`.
- **Il kernel locale 7.0 ha un `.config` difettoso.** Non usarlo come
  riferimento per il lavoro upstream.

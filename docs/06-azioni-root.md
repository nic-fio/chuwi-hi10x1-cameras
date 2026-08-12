# 06 — Azioni che richiedono root

> **Documento in gran parte storico.** E' stato scritto quando la macchina
> avviava il kernel **7.0 compilato a mano**. Dal 2026-08-11 sera avvia il
> kernel **Debian 6.12.86**, che ha `pinctrl-alderlake` e con esso l'intera
> catena camera funzionante: i punti 1, 2, 2-bis e 3 sono chiusi, il 4 e' una
> procedura fallita e annullata, e il 5 — «installare un kernel di
> distribuzione» — e' stato fatto ed e' quello che ha sbloccato il progetto.
>
> Resta utile per due cose, entrambe difficili da ricostruire: **come si avvia
> davvero questa macchina** (UEFI Shell, `startup.nsh`, PARTUUID
> `dc363afc-02`, bzImage contro vmlinux) e **perche' certe deduzioni erano
> sbagliate**. Per lo stato attuale vedi `docs/08-prova-hardware.md`; per
> avviare il kernel di debug, `docs/10-kernel-di-debug.md`.

Raccolte qui perche' su questa macchina `sudo` chiede la password e non e'
automatizzabile. In ordine di dipendenza.

Per lanciarle dentro una sessione Claude Code, prefisso `!`:
`! sudo ./scripts/dump-dsdt.sh`

---

## 1. Journal persistente — 10 secondi, fallo per primo

```bash
sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald
```

Il ring buffer si satura in poche ore. E' il motivo per cui il Blocco 1 era
sfuggito alla prima analisi: i messaggi di boot dell'IPU6 erano gia' stati
sovrascritti. Senza questo, ogni debug successivo parte cieco.

---

## 2. Estrarre la DSDT — **il passo che sblocca il progetto**

```bash
sudo ./scripts/dump-dsdt.sh
```

Legge `/sys/firmware/acpi/tables/DSDT` (root-only), decompila con `iasl` e
isola i nodi camera. Produce `data/dsdt/camera-nodes.dsl`.

Da li' si compilano le righe **[DSDT]** di `05-parametri-sensori.md`, e
soprattutto si scopre **se la link frequency del CHUWI coincide con quella
della patch Intel**. Se non coincide, i registri PLL sono blob non documentati
e serve il register guide GalaxyCore: cambia la fattibilita' del progetto.

Nessun rischio: legge e basta.

---

## 2-bis. Leggere i parametri dei sensori dalla ACPI NVS — **il passo che sblocca il progetto**

> Primo tentativo fallito sul 7.0 (tabella sotto), poi **risolto**: serve un
> riavvio del 7.0 con `iomem=relaxed`, non un kernel diverso. Se hai fretta,
> salta alla sezione "Come farlo".

```bash
sudo ./scripts/read-camera-nvs.py
```

La DSDT si e' rivelata insufficiente: `_HID`, `_CRS`, `SSDB`, `CLDB` e i `_DSM`
sono tutti parametrizzati da variabili che il BIOS scrive in ACPI NVS al boot.
Ma la `OperationRegion` GNVS ha un indirizzo fisico letterale (`0x75886000`),
quindi quei valori si leggono dalla memoria della macchina in esecuzione.

Da qui escono **numero di lane, MCLK, indirizzo I2C e funzioni GPIO** di
entrambi i sensori, piu' i verdetti su Serie 4 e sul bug del firmware.

### Esito del tentativo (2026-08-11)

Lo script e' corretto ma **entrambe le sue strade sono chiuse dal kernel 7.0**:

| Strada | Esito | Perche' |
|---|---|---|
| `/dev/mem` | `EPERM` | il 7.0 ha `IO_STRICT_DEVMEM=y`: la regione NVS e' claimed da un driver, quindi esclusiva. `STRICT_DEVMEM` da solo la consentirebbe |
| `/proc/kcore` | nessun `PT_LOAD` copre `0x75886000` | la ACPI NVS e' memoria E820-reserved: **non e' nella mappa diretta**, quindi kcore non la espone. Non e' un difetto dello script |
| `acpidbg` | `/sys/kernel/debug/acpi/` **vuota** | il 7.0 non ha `CONFIG_ACPI_DEBUGGER` |
| modulo `acpi_call` | impossibile | headers del 7.0 spariti, vedi ROADMAP Fase 0 |

### La conclusione qui sopra era sbagliata: basta un parametro di boot

Da questo esito era stato dedotto "non ci sono altre strade sul kernel in
esecuzione, serve il kernel vanilla del punto 4". **Non e' vero**, e la
correzione e' importante perche' quella deduzione e' l'unico motivo per cui
esisteva la Fase 1.

`IO_STRICT_DEVMEM` **non e' una decisione di compilazione definitiva**: e'
subordinata a una variabile che si spegne dalla riga di comando del kernel.
Catena verificata sul sorgente in `/home/nicfio/linux` (mainline 7.2):

```c
/* kernel/resource.c:2153 — il parametro */
static int __init strict_iomem(char *str)
{
	if (strstr(str, "relaxed"))
		strict_iomem_checks = 0;
	...
}

/* kernel/resource.c:1918 — dentro resource_is_exclusive() */
if (!strict_iomem_checks || !(p->flags & IORESOURCE_BUSY))
	continue;                    /* <-- con relaxed salta OGNI risorsa */
if (IS_ENABLED(CONFIG_IO_STRICT_DEVMEM) || p->flags & IORESOURCE_EXCLUSIVE) {
	err = true;                  /* <-- il ramo che oggi da' EPERM */
	break;
}
```

Con `iomem=relaxed` il `continue` precede il test su `CONFIG_IO_STRICT_DEVMEM`:
il flag compilato resta `y` ma **non viene mai raggiunto**, `err` resta `false`,
`iomem_is_exclusive()` risponde `false` e `devmem_is_allowed()`
(`arch/x86/mm/init.c:886`) ritorna 1. La lettura passa.

L'altro controllo di `devmem_is_allowed()`, quello su `IORESOURCE_SYSTEM_RAM`,
non ci riguarda: la ACPI NVS e' E820-reserved, quindi **non** e' System RAM ed
e' `REGION_DISJOINT`. E' lo stesso motivo per cui `/proc/kcore` non la vede.

Che `/dev/mem` risponda `EPERM` e non `ENOENT` dimostra fra l'altro che sul 7.0
`CONFIG_DEVMEM=y` e il dispositivo esiste: viene rifiutata la singola lettura,
non l'apertura.

### Come farlo — nessun file da modificare

Stesso trucco del punto 4: la UEFI Shell si interrompe con **ESC** e accetta un
comando a mano, quindi si avvia **lo stesso identico kernel di sempre** con un
parametro in piu'. Niente da installare, niente da editare, niente da
ripristinare.

1. Riavviare. Alla UEFI Shell premere **ESC** entro il countdown
2. Al prompt digitare (e' la riga di `startup.nsh` piu' `iomem=relaxed`):

```
fs0:
vmlinuz initrd=initrd.img root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw iomem=relaxed
```

Qui `root=UUID=` va bene — a differenza del punto 4, **l'initrd c'e'** ed e' udev
a risolvere l'UUID. Non togliere `initrd=initrd.img`.

3. A sistema avviato:

```bash
sudo ./scripts/read-camera-nvs.py
```

Lo script non va toccato: `read_via_devmem()` e' gia' la sua strada 1.

**Se qualcosa va storto**: riavviare e lasciar scorrere `startup.nsh`. Il boot
normale torna esattamente com'era — `iomem=relaxed` non e' persistente, vive
solo per quell'avvio.

**Costo se fallisce**: un riavvio. **Costo del kernel nuovo per lo stesso
risultato**: una build da un'ora, un'installazione e il pomeriggio del
2026-08-11.

### Quello che si e' comunque imparato, senza root

Fatti raccolti da sysfs, che restringono il problema:

- `/sys/bus/acpi/devices/GCTI5035:00` e `GCTI8034:00` **esistono**, con
  `status` = `0x0F` (presente, abilitato, funzionante). Siccome `_HID` non e'
  una stringa fissa ma `HCID(One)` calcolata da `L1SM`, il fatto che il kernel
  ne ricavi `GCTI5035` dimostra che **il BIOS ha popolato la NVS** e che i
  valori sono sensati
- i sei bus `Synopsys DesignWare` (`i2c-10`..`i2c-15`) sono **registrati**, e
  `intel_skl_int3472_discrete` e' **caricato**
- eppure **non esiste alcun client I2C**: `ls /sys/bus/i2c/devices/` non mostra
  nessuna voce `N-00XX`

Nel `_CRS` di `LNK1` (`data/dsdt-analisi/LNK1.dsl`, riga 136) l'unico ramo che
restituisce un buffer vuoto e' `L1DI == Zero`. Ipotesi di lavoro, **da
confermare leggendo la NVS**: i sensori sono dichiarati presenti ma senza
risorsa I2C, quindi nessun client viene creato e nessun driver potrebbe
agganciarsi — indipendentemente da quanto sia corretto il driver.

Se si conferma, e' un problema che viene **prima** delle tabelle registri.

### Nota di contorno

`sudo` stampa `impossibile risolvere l'host CHUWI` a ogni invocazione: manca la
riga in `/etc/hosts`. Innocuo ma rumoroso, e rallenta ogni `sudo` di qualche
secondo per il timeout della risoluzione.

```bash
echo "127.0.1.1 CHUWI" | sudo tee -a /etc/hosts
```

---

## 3. Pacchetti mancanti

```bash
sudo apt install v4l-utils libncurses-dev rsync
```

- `v4l-utils` — `v4l2-ctl`, `media-ctl`, `v4l2-compliance`. Senza questi non si
  puo' testare nulla ne' produrre l'output che i revisori upstream chiedono
- `libncurses-dev` — serve per `make menuconfig`
- `rsync` — usato da alcuni target di installazione del kernel

Per la Fase 4, piu' avanti:

```bash
sudo apt install libcamera-tools pipewire-libcamera gstreamer1.0-libcamera
```

---

## 4. Installare il kernel vanilla — **FATTO, FALLITO, ANNULLATO (2026-08-11)**

> **Procedura eseguita il 2026-08-11, poi annullata.** Il kernel
> `7.2.0-rc7-intelcam-geffb39a5b9a0` e' stato costruito, copiato sulla ESP e
> avviato a mano alle **18:08:52**. Il sistema e' rimasto in piedi **~4 minuti**
> (spegnimento ordinato alle 18:12:49, `systemd-shutdown`, wifi che si
> deautentica: non un crash). Rientro sul 7.0 alle 18:13:30 **senza dover
> ripristinare nulla**, esattamente come previsto qui sotto.
>
> Journal completo in `data/boot-7.2-fallito.log` (2615 righe), analisi nel
> paragrafo seguente. **La causa e' un errore di `.config` in una riga**, e il
> boot ha comunque prodotto il risultato piu' importante del progetto finora.
>
> ESP poi ripulita a mano: `vmlinuz-intelcam` e `intelcam.nsh` rimossi,
> `vmlinuz` + `initrd.img` + `EFI/BOOT/bootx64.efi` del 7.0 intatti,
> `startup.nsh` bit-identico all'originale e con l'UUID giusto. Verificato.
>
> **E soprattutto: non serviva.** L'unico motivo per cui esisteva era sbloccare
> la lettura della NVS, e per quella basta `iomem=relaxed` (punto 2-bis).
>
> Il testo resta perche' i fatti che contiene sono veri e servono a chiunque
> debba avviare qualcosa su questa macchina: bzImage vs vmlinux, PARTUUID
> `dc363afc-02`, la UEFI Shell interrompibile con ESC.

### Perche' e' fallito: `DRM_I915=y` senza initrd

Il ragionamento "niente initrd = un modo di fallire in meno" (punto 2 qui sotto)
e' giusto per il **disco**, ma ha un rovescio che era stato ignorato: **il
firmware**. Un driver built-in fa probe **prima che il rootfs sia montato**,
quindi `/lib/firmware` non esiste ancora e ogni `request_firmware()` fallisce.

Nel kernel nuovo `i915` era built-in (nella lista `Modules linked in` del
journal non compare, mentre sul 7.0 c'e' `i915(+)`). Conseguenza a catena:

```
i915 0000:00:02.0: Direct firmware load for i915/adlp_dmc.bin failed with error -2
i915 0000:00:02.0: [drm] Failed to load DMC firmware (-ENOENT). Disabling runtime power management.
i915 0000:00:02.0: [drm] *ERROR* GT0: GuC firmware i915/tgl_guc_70.bin: fetch failed -ENOENT
i915 0000:00:02.0: [drm] *ERROR* GT0: Enabling uc failed (-5)
i915 0000:00:02.0: [drm] *ERROR* GT0: Failed to initialize GPU, declaring it wedged!
```

**I file ci sono**: `/lib/firmware/i915/adlp_dmc.bin`, `adlp_guc_70.bin` e
compagnia sono installati (`firmware-intel-graphics`, `firmware-misc-nonfree`).
Sul 7.0 `i915` e' un modulo, udev lo carica a rootfs montato e infatti si legge
`Finished loading DMC firmware i915/adlp_dmc.bin (v2.20)`. Stesso hardware,
stesso firmware, esito opposto: cambia solo **quando** avviene il probe.

GPU wedged significa schermo inservibile. Da li' in poi il journal e' una
sequenza di 30 call trace, l'ultimo in `fbcon_blank` -> `do_unblank_screen` ->
`vt_ioctl`: la console che cerca di disegnare su una GPU dichiarata morta.

Le tre correzioni possibili, in ordine di preferenza:

| | Come | Nota |
|---|---|---|
| `CONFIG_DRM_I915=m` | come sul 7.0 | la piu' semplice; udev lo carica dopo il rootfs |
| `CONFIG_EXTRA_FIRMWARE` | firmware dentro il bzImage | mantiene il boot senza initrd |
| generare un initrd | `mkinitramfs` | rinuncia al vantaggio di partenza |

Vale per **qualunque** driver built-in che chieda firmware, non solo `i915`.

### La seconda causa, indipendente: `# CONFIG_BT is not set`

Riferita dall'utente ("non vedeva piu' tastiera e mouse bluetooth") e confermata
su `config/intelcam-7.2.0-rc7.config`: l'**intero stack Bluetooth** era stato
tolto da `localmodconfig`. Su questo tablet tastiera e mouse sono Bluetooth,
quindi il kernel nuovo non aveva **nessun dispositivo di input**.

E' la **terza** trappola di `localmodconfig`, dopo `FRAMEBUFFER_CONSOLE` e
`iwlwifi`. Il modello di errore e' sempre lo stesso: `localmodconfig` tiene solo
i moduli caricati **nell'istante in cui gira**, e tutto cio' che in quel momento
e' inattivo sparisce senza avviso. Non e' una svista da correggere una volta: e'
il comportamento dello strumento.

Schermo wedged **piu'** input assente = tablet inservibile. Sono due difetti
scorrelati che si sono sommati, ed e' il motivo per cui la Fase 1 e' stata
chiusa. `scripts/build-kernel.sh` ora impone `BT`, `BT_HCIBTUSB`, `BT_HIDP` e
`DRM_I915=m`, e **si rifiuta di compilare** se mancano.

### Due cose che NON erano la causa

- **`drm_WARN_ON(tc->mode == TC_PORT_LEGACY)` a `intel_tc.c:933`, preceduto da
  `Port F/TC#3: timeout waiting for PHY ready`.** Sembra grave ed e' il primo
  WARNING del log, ma **compare identico sul 7.0** (`intel_tc.c:934`, riga
  diversa solo perche' cambia la versione). E' rumore preesistente di questo
  hardware, non una regressione del kernel nuovo
- **`cfg80211: failed to load regulatory.db`.** `/lib/firmware/regulatory.db`
  manca davvero — il pacchetto `wireless-regdb` non e' installato — ma manca
  anche al 7.0 e il wifi funziona lo stesso. Nel boot fallito `wlo1` era
  associato a un AP: la rete c'era

### Cosa quel boot ha dimostrato — ed e' molto

Questa e' la parte che vale la pena salvare. Dal journal, kernel nuovo:

```
intel-ipu6 0000:00:05.0: Found supported sensor GCTI5035:00
intel-ipu6 0000:00:05.0: Found supported sensor GCTI8034:00
intel-ipu6 0000:00:05.0: Connected 2 cameras
intel-ipu6 0000:00:05.0: Sending BOOT_LOAD to CSE
intel-ipu6 0000:00:05.0: CSE authenticate_run done
intel-ipu6 0000:00:05.0: IPU6-v3[462e] hardware version 5
```

**Le due voci aggiunte a `ipu_supported_sensors[]` funzionano.** Non e' una
supposizione: `ipu-bridge` ha riconosciuto entrambi gli `_HID`, ha costruito i
software node e ha dichiarato due camere connesse. E' il **semaforo 4**, e in
quel boot era `[OK]`. Il firmware dell'IPU6 si autentica e l'ISP e' vivo.

I moduli `gc5035` e `gc8034` erano caricati (si leggono in `Modules linked in`).

### E cosa NON ha dimostrato — il sospetto resta in piedi

Nel journal **non c'e' una sola riga** di:

- creazione di client I2C (nessun `i2c-N` con indirizzo, nessuna enumerazione
  ACPI di `I2cSerialBus`)
- probe di `gc5035` o `gc8034` — i moduli erano caricati ma **non hanno mai
  fatto bind a niente**
- `INTC1057` che si aggancia, o comparsa di un `gpiochip`

Coerente con il sospetto del punto 2-bis: **i sensori sono dichiarati presenti
ma senza risorsa I2C**, quindi nessun client viene creato e nessun driver puo'
agganciarsi, per quanto corretto sia. Un driver perfetto non cambierebbe nulla.

**Questo e' il motivo per cui leggere la NVS resta il prossimo passo, e non e'
una formalita': e' la domanda da cui dipende la fattibilita' del progetto.**

Prima di tutto: `./scripts/build-kernel.sh` (non serve root, ~30-60 min).

Contesto di boot di questa macchina, verificato:

- `/boot` e' vuoto — nessun kernel, nessun initrd
- la ESP (`/dev/sda1`, 2 GB vfat) **non e' montata** e `/etc/fstab` e' vuoto
- **nessun bootloader installato come pacchetto** (ne' grub ne' systemd-boot)
- boot via **script EFI custom** che invoca direttamente l'immagine grazie
  all'EFI stub:
  `vmlinuz initrd=initrd.img root=UUID=bbf08cd1-… rw quiet hostname=CHUWI`
- **non esiste un kernel di riserva**: c'e' solo il 7.0 compilato a mano, e i
  suoi sorgenti sono spariti

Se si sovrascrive l'immagine attuale e la nuova non parte, **la macchina non fa
piu' boot** e serve una chiavetta di ripristino.

### Tre cose da sapere prima di copiare qualcosa

**1. Il file da copiare e' `arch/x86/boot/bzImage`, non `vmlinux`.**
Lo stub EFI e' nel `bzImage` (immagine PE/COFF avviabile da firmware).
`vmlinux` e' l'ELF non compresso e **non e' avviabile da EFI**. Nel cmdline
attuale il file si chiama `vmlinuz`: e' un `bzImage`.

**2. Questo kernel non ha bisogno di initrd.** Verificato sulla `.config`:

| | |
|---|---|
| `CONFIG_EFI_STUB` | `y` — avviabile direttamente dal firmware |
| `CONFIG_EFI_PARTITION` / `CONFIG_MSDOS_PARTITION` | `y` |
| `CONFIG_EXT4_FS` | `y` — root montabile senza moduli |
| `CONFIG_ATA`, `CONFIG_SATA_AHCI`, `CONFIG_BLK_DEV_SD`, `CONFIG_SCSI` | `y` |

Niente initramfs significa un modo di fallire in meno: nessun `update-initramfs`
da azzeccare, nessun modulo mancante al boot.

**3. Ma allora serve `root=PARTUUID=`, non `root=UUID=`.**
Il kernel **non** risolve gli UUID di filesystem da solo: lo fa udev dentro
l'initramfs. Senza initrd, `root=UUID=bbf08cd1-…` produce
`VFS: Unable to mount root fs`.

Identificatori di questa macchina (disco **MBR**, non GPT — il PARTUUID e'
firma-disco + numero partizione):

| Partizione | Filesystem UUID | PARTUUID | Uso |
|---|---|---|---|
| `sda1` | `D944-91C5` | `dc363afc-01` | ESP, vfat |
| `sda2` | `bbf08cd1-b31b-4a2f-8f42-9659c613ae4a` | **`dc363afc-02`** | root, ext4 |

Riga da usare: `root=PARTUUID=dc363afc-02 rw`.

### Com'e' fatto davvero il boot (ispezionato il 2026-08-11)

Contenuto della ESP:

```
/mnt/esp/EFI/BOOT/bootx64.efi   1.045.440 byte  -> e' la UEFI Shell, non un bootloader
/mnt/esp/startup.nsh            155 byte        -> eseguito in automatico dalla Shell
/mnt/esp/vmlinuz                9,8 MB          -> il 7.0, bzImage
/mnt/esp/initrd.img             86 MB
/mnt/esp/live.img               1,19 GB         -> residuo del setup live originale
/mnt/esp/OVMF.fd, settings.dconf
```

Spazio libero: **812 MB**. Il `bzImage` nuovo ne occupa 15.

`startup.nsh`:

```
#vmlinuz initrd=initrd.img boot=live quiet hostname=CHUWI
vmlinuz initrd=initrd.img root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw quiet hostname=CHUWI
```

La prima riga e' commentata: e' il boot dell'immagine live. La seconda e' quella
attiva. Nota che **il boot attuale un initrd ce l'ha**, ed e' per questo che
`root=UUID=` gli funziona: a risolvere l'UUID e' udev dentro l'initrd.

Catena completa: firmware -> `EFI/BOOT/BOOTX64.EFI` (Shell) -> `startup.nsh` ->
`vmlinuz`.

### Perche' questo rende il passo molto meno rischioso

La UEFI Shell **interrompe `startup.nsh` se si preme ESC** durante il countdown,
e lascia un prompt da cui si lancia qualunque immagine a mano.

Quindi non serve modificare niente: si aggiunge un file con un nome nuovo e lo
si avvia digitandolo. `startup.nsh` resta intatto, il 7.0 resta il default, e
**se il kernel nuovo non parte basta riavviare** — non c'e' nulla da
ripristinare. Il piano originale (editare lo script per aggiungere una voce) era
scritto prima di sapere che il bootloader fosse una shell interattiva: e'
inutilmente piu' rischioso.

### Procedura, un passo alla volta

```bash
# 4a. montare la ESP
sudo mkdir -p /mnt/esp && sudo mount /dev/sda1 /mnt/esp
```

```bash
# 4b. backup del solo file che potrebbe servire — 155 byte
sudo cp -a /mnt/esp/startup.nsh /mnt/esp/startup.nsh.orig
cp /mnt/esp/startup.nsh /home/nicfio/INTEL-CAMERA/data/startup.nsh.orig
```

Backup dell'intera ESP non serve: **non si sovrascrive nulla**, si aggiunge un
file. E 1,3 GB di cui 1,19 di `live.img` che non viene toccato.

```bash
# 4c. immagine nuova, nome NUOVO — non tocca vmlinuz
sudo cp /home/nicfio/linux/arch/x86/boot/bzImage /mnt/esp/vmlinuz-intelcam
sync
```

```bash
# 4d. moduli (non servono al boot, servono alle camere)
sudo make -C /home/nicfio/linux modules_install
# installa in /lib/modules/7.2.0-rc7-intelcam-geffb39a5b9a0
```

```bash
# 4e. riavviare
sudo reboot
```

### Al riavvio, a mano

1. Alla comparsa della UEFI Shell premere **ESC** entro il countdown per saltare
   `startup.nsh`
2. Al prompt `Shell>` digitare:

```
fs0:
vmlinuz-intelcam root=PARTUUID=dc363afc-02 rw
```

Tre dettagli, e sono i tre modi realistici di non fare boot:

- **`bzImage`, non `vmlinux`.** Lo stub EFI e' nel `bzImage`. `vmlinux` e' l'ELF
  non compresso e il firmware non lo avvia. Verificato sull'immagine costruita:
  ha gli entry point *EFI handoff* a 32 e 64 bit
- **`root=PARTUUID=`, non `root=UUID=`.** Il kernel nuovo non ha initrd, e senza
  udev non risolve gli UUID di filesystem: `root=UUID=` darebbe
  `VFS: Unable to mount root fs`. Il disco e' MBR (`dos`), quindi il PARTUUID e'
  firma-disco + numero partizione: **`dc363afc-02`**, verificato con `lsblk`
- **niente `initrd=`, niente `quiet`.** L'initrd non serve (`EXT4_FS`, `ATA`,
  `SATA_AHCI`, `BLK_DEV_SD`, `MSDOS_PARTITION` sono tutti `=y`), e al primo boot
  i messaggi vanno visti

`hostname=CHUWI` era un parametro di `live-boot`: su un boot normale non serve.

### Se non parte

**Riavviare e lasciar scorrere `startup.nsh`**: riparte il 7.0. Nessun file e'
stato modificato, quindi non c'e' niente da ripristinare e non serve una
chiavetta.

---

## 5. Kernel di distribuzione — **FATTO, ed e' quello che ha sbloccato tutto**

> **Eseguito il 2026-08-11 sera.** La macchina avvia ora
> `6.12.86+deb13-amd64`, il kernel Debian. Con lui `pinctrl-alderlake` c'e',
> il gpiochip `INTC1057` nasce, `int3472-discrete` esce dalla probe rimandata,
> l'ACPI crea i client I2C dei due sensori e i semafori 1-3 sono passati a
> `[OK]` per la prima volta. Da li' in poi, in una sera, i driver hanno fatto
> probe e catturato. Vedi `docs/08-prova-hardware.md`.
>
> Il testo qui sotto e' quello scritto **prima**, quando questa strada era
> ancora un'ipotesi archiviata come "non urgente". Vale la pena rileggerlo per
> una ragione sola: la conclusione era giusta e la priorita' era sbagliata.
> Era la cosa piu' importante da fare, ed era in fondo alla lista.

### Il testo originale — decaduto con il punto 4

Prevedeva `collect-diag.sh` con i semafori 1-3 a `[OK]` grazie a
`PINCTRL_ALDERLAKE` built-in. Senza quel kernel **restano `[KO]`**: niente
`gpiochip`, `INTC1057:00` senza driver, gli `INT3472` senza GPIO.

Va detto chiaramente cosa significa e cosa no:

- **Significa** che i sensori non si possono alimentare qui, quindi i driver
  `gc5035`/`gc8034` non sono testabili **su questa macchina** finche' non gira
  un kernel con `PINCTRL_ALDERLAKE`
- **Non significa** che il progetto sia fermo. L'obiettivo e' il tree di Linus,
  e il codice si scrive, compila e invia contro `/home/nicfio/linux`
- `collect-diag.sh` resta utile lo stesso: fotografa lo stato ACPI/I2C, che e'
  il dato che serve adesso

Il test locale torna in gioco quando ci sara' un kernel con `PINCTRL_ALDERLAKE`
che **fa boot** — il candidato ovvio e' quello di Debian
(`apt install linux-image-amd64 linux-headers-amd64`): viene con i suoi headers,
non e' compilato a mano e non e' mai stato provato qui. Da verificare prima di
installarlo, perche' e' l'unica cosa che conta:

```bash
apt download linux-image-amd64        # metapacchetto, tira il pacchetto reale
grep -E 'PINCTRL_ALDERLAKE|IO_STRICT_DEVMEM' /boot/config-<versione>
```

Non e' urgente e non e' in questa fase.

---

## 6. Riprodurre l'oops di `subdev_open()` — **fa oopsare il kernel apposta**

```bash
sudo ./scripts/riproduci-oops-subdev.sh gc5035 200
```

E' l'unica cosa in questo repository che rompe qualcosa di proposito, quindi va
detto per esteso cosa fa e cosa costa.

**Cosa fa**: riaggancia il sensore in ciclo mentre quattro processi aprono ogni
`/dev/v4l-subdev*`, finche' uno dei due si infila nella finestra in cui
`sd->v4l2_dev` e' gia' `NULL` e il nodo c'e' ancora. Il 2026-08-12 ci ha messo
**sette cicli**.

**Cosa costa**:

- il kernel stampa un `BUG:` e va in stato `D` (`Tainted: [D]=DIE`). Da li' in
  poi ogni oops successivo e' meno informativo, e un `WARNING` di qualcun altro
  puo' essere confuso col nostro;
- **ogni colpo perde un minor di `/dev/v4l-subdev` per sempre**, con il
  `video_device` attaccato. Si vede dai buchi nella numerazione;
- non serve riavviare — dopo due oops la macchina ha continuato a catturare —
  ma la memoria persa la restituisce solo un riavvio.

**Quando ha senso**: per confermare la diagnosi di A2 a chi chiede una prova, o
per verificare che `patches/wip/subdev-fix/` la chiuda davvero. Non per
abitudine, e non "per vedere se funziona ancora".

---

## Opzionale — evitare di ridigitare la password

```bash
sudo visudo -f /etc/sudoers.d/intel-camera
```

```
nicfio ALL=(root) NOPASSWD: /home/nicfio/INTEL-CAMERA/scripts/dump-dsdt.sh, \
                            /home/nicfio/INTEL-CAMERA/scripts/collect-diag.sh
```

Vale solo per quei due script. **Avvertenza**: gli script restano scrivibili
dall'utente, quindi chi puo' modificarli ottiene root. Accettabile su una
macchina di sviluppo personale, non su una condivisa.

Non memorizzare la password in un file, in una variabile d'ambiente o nella
memoria di un assistente: sono tutti posti in chiaro, meno protetti di
`/etc/shadow`.

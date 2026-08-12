# 10 — Il kernel di debug: come avviarlo e cosa cercarci

Serve a chiudere il buco piu' grande della revisione pre-invio: il kernel
Debian in uso non ha **nessuno** strumento di analisi dinamica, quindi tutto
quello che si e' detto su memoria e locking dei due driver e' ispezione, non
misura. Questo kernel li ha tutti.

```bash
./scripts/build-kernel.sh --debug        # non serve root, ~1-2 ore
```

**Gia' costruito il 2026-08-11 sera.** Non serve rifarlo:

| | |
|---|---|
| Versione | `7.2.0-rc7-intelcam-debug-gc61216fb5a24` |
| Immagine | `/home/nicfio/linux/arch/x86/boot/bzImage`, 29 MB |
| Avviabile da EFI | si', entry point handoff a 32 e 64 bit verificati |
| Driver | `gc5035.ko` e `gc8034.ko` costruiti **in albero**, non fuori |
| Config archiviata | `config/intelcam-7.2.0-rc7-debug.config` |

Contiene i due driver nella versione finale, con tutte le correzioni della
revisione. **Non** contiene la patch a `ipu6-isys`: quella sta su un branch a
parte, `ipu6-npd-fix`, perche' e' un invio separato.

Cosa aggiunge, e cosa trova ciascuno:

| Strumento | Trova |
|---|---|
| `KASAN` (generic, inline) | use-after-free, doppi free, overflow di slab e di stack |
| `UBSAN` | overflow di interi, shift fuori range, indici fuori dagli array |
| `PROVE_LOCKING` (lockdep) | inversioni di lock, ricorsioni, lock presi in contesto sbagliato |
| `DEBUG_ATOMIC_SLEEP` | dormire dove non si puo' — `usleep_range` in atomico |
| `DEBUG_KMEMLEAK` | memoria allocata e mai liberata, che KASAN non vede |
| `DEBUG_OBJECTS` | oggetti usati dopo la distruzione: timer, work, mutex |
| `DETECT_HUNG_TASK` | task bloccati piu' di 120 s, come quello lasciato dall'oops |

`PANIC_ON_OOPS` e' **disattivato apposta**: se qualcosa esplode, serve che la
macchina resti in piedi abbastanza da leggere il journal.

## PRONTO ALL'AVVIO — 2026-08-12, ore 08:56

> **I passi 1 e 2 qui sotto sono gia' stati fatti.** Manca solo il riavvio.
>
> | Cosa | Stato |
> |---|---|
> | Immagine sulla ESP | `/mnt/esp/vmlinuz-debug`, 29 MB, con le due correzioni dentro |
> | Moduli installati | `/lib/modules/7.2.0-rc7-intelcam-debug-gc61216fb5a24-dirty` |
> | `startup.nsh` | **intatto**, md5 `78c831bb7c3f537b1c8bdae19025bfe3` |
> | Correzioni A1 e A2 | applicate **non committate** in `/home/nicfio/linux` |
> | `PARTUUID` di root | `dc363afc-02`, verificato con `lsblk` |
> | KMEMLEAK | attivo di suo, nessun parametro da aggiungere |
> | `PANIC_ON_OOPS` | disattivato: un oops non spegne la macchina |
>
> **Le due righe da digitare** dopo aver premuto ESC al conto alla rovescia:
>
> ```
> fs0:
> vmlinuz-debug root=PARTUUID=dc363afc-02 rw
> ```
>
> **Una volta dentro** (il prompt dira' `7.2.0-rc7-intelcam-debug`):
>
> ```bash
> uname -r                                   # deve dire 7.2.0-rc7-intelcam-debug-...
> sudo modprobe gc5035 gc8034                # qui sono IN-TREE, niente build-6.12
> sudo ./scripts/prova-completa.sh
> sudo ./scripts/misura-guadagno.sh          # con la luce accesa
> sudo dmesg | grep -E "KASAN|UBSAN|lockdep|BUG:|WARNING:|possible recursive"
> echo scan | sudo tee /sys/kernel/debug/kmemleak && sudo cat /sys/kernel/debug/kmemleak
> ```
>
> **Nota per la sessione dopo il riavvio**: questa conversazione girava sul
> tablet, quindi il riavvio l'ha interrotta. Il contesto e' tutto qui e in
> `docs/09-revisione-preinvio.md`. Le due correzioni nell'albero del kernel
> sono **non committate** apposta: committarle cambierebbe la stringa di
> versione e costringerebbe a ricompilare tutto.
>
> Per tornare a Debian: riavviare e lasciar scorrere `startup.nsh`.

## Avviarlo — richiede te davanti alla tastiera

Non lo si puo' rendere il default e non lo si vuole: e' un kernel da
laboratorio, lento, ed e' costruito a mano. La macchina continua ad avviare il
kernel Debian da sola, come adesso.

**`startup.nsh` non va toccato.** L'immagine si aggiunge con un nome nuovo e la
si lancia a mano dalla UEFI Shell. Se non parte, si riavvia e riparte Debian:
non c'e' niente da ripristinare. E' la stessa procedura che il 2026-08-11 ha
permesso di recuperare un boot fallito senza chiavetta.

### 1. Installare moduli e immagine

```bash
sudo make -C /home/nicfio/linux modules_install
sudo mkdir -p /mnt/esp && sudo mount /dev/sda1 /mnt/esp
ls -la /mnt/esp                      # guardare PRIMA cosa c'e'
sudo cp /home/nicfio/linux/arch/x86/boot/bzImage /mnt/esp/vmlinuz-debug
sync && sudo umount /mnt/esp
```

Nome nuovo, `vmlinuz-debug`: **non** sovrascrive `vmlinuz`, che e' il kernel
Debian con cui la macchina si avvia.

### 2. Al riavvio

Alla comparsa della UEFI Shell, premere **ESC** entro il countdown per saltare
`startup.nsh`, poi al prompt `Shell>`:

```
fs0:
vmlinuz-debug root=PARTUUID=dc363afc-02 rw
```

Tre dettagli, e sono i tre modi realistici di non fare boot:

- **`root=PARTUUID=`, non `root=UUID=`.** Questo kernel parte senza initrd e
  senza udev non risolve gli UUID di filesystem. Il disco e' MBR, quindi il
  PARTUUID e' firma-disco piu' numero di partizione: **`dc363afc-02`**
- **niente `initrd=`, niente `quiet`.** L'initrd non serve — `EXT4_FS`, `ATA`,
  `SATA_AHCI`, `BLK_DEV_SD` e `MSDOS_PARTITION` sono tutti `=y`, e
  `build-kernel.sh` si rifiuta di compilare se cosi' non fosse — e i messaggi
  al primo avvio vanno visti
- **`bzImage`, non `vmlinux`.** Lo stub EFI e' nel `bzImage`

### 3. Se non parte

Riavviare e lasciar scorrere `startup.nsh`. Torna Debian. Nessun file e' stato
modificato.

## Cosa fare una volta dentro

```bash
cd /home/nicfio/linux && sudo make modules_install     # se non gia' fatto
sudo modprobe gc5035 gc8034                            # ora sono IN-TREE
sudo ./scripts/prova-completa.sh
```

Qui i driver sono compilati **dentro** il kernel di prova, non fuori albero:
sparisce anche l'ultimo dubbio residuo, cioe' che l'header di compatibilita'
di `build-6.12/` mascheri qualcosa.

Poi, in ordine di quanto sono informativi:

> **Prima di tutto: applicare le due correzioni di mainline**, `ipu6-fix/` e
> `subdev-fix/`. Senza, questa sessione misura i difetti di qualcun altro. Il
> bind/unbind fa oopsare il kernel da solo per **A2** — basta udev che apre il
> nodo — e un oops interrompe la prova a meta' lasciando in giro riferimenti
> che poi KMEMLEAK segnala come perdite nostre. Non lo sono.
>
> ```bash
> cd /home/nicfio/linux
> git am /home/nicfio/INTEL-CAMERA/patches/wip/{ipu6-fix,subdev-fix}/*.patch
> ```

1. **Ripetere tutto il ciclo normale** — carica, cattura, guadagno,
   compliance, bind/unbind — e guardare `dmesg`. Con KASAN e lockdep attivi,
   un difetto che prima passava inosservato adesso stampa. Il guadagno chiede
   una luce accesa davanti ai sensori: al buio la misura non si fa, e dal
   2026-08-12 `prova-completa.sh` lo dice invece di dare `[KO]`.
2. **`unbind` durante lo streaming.** E' il test che dice se i **nostri**
   driver reggono quello scenario. Con `ipu6-fix/` applicata non lascia piu'
   la macchina da riavviare; senza, si', e allora si riproduce soltanto A1.
3. **KMEMLEAK dopo un ciclo completo**:

   ```bash
   echo scan | sudo tee /sys/kernel/debug/kmemleak
   sudo cat /sys/kernel/debug/kmemleak
   ```

   Da fare dopo dieci cicli di bind/unbind: e' li' che una perdita si accumula
   abbastanza da vedersi. **Una perdita in quel punto e' gia' nota e non e'
   nostra**: ogni oops di A2 lascia appeso per sempre un `video_device` con il
   suo minor, e si vede a occhio nudo dai buchi in `/dev/v4l-subdev*`. Con
   `subdev-fix/` applicata quel rumore sparisce e quello che resta e' materiale
   da guardare davvero.
4. **Cercare i messaggi che contano**:

   ```bash
   sudo dmesg | grep -E "KASAN|UBSAN|lockdep|BUG:|WARNING:|possible recursive"
   ```

Se dopo tutto questo non esce niente, allora — e solo allora — si puo' scrivere
in una cover letter che i driver sono stati provati con KASAN e lockdep. Prima
no.

#!/bin/bash
# build-kernel.sh — kernel vanilla di sviluppo per il progetto INTEL-CAMERA.
#
# Progetto INTEL-CAMERA — CHUWI Hi10 X1
#
# PERCHE' ESISTE:
#
# Questa macchina non ha sorgenti kernel utilizzabili: /lib/modules/7.0/build
# punta a /root/linux-7.0 che NON esiste piu'. Non e' quindi possibile
# compilare moduli per il kernel in esecuzione. L'unica strada e' costruire un
# kernel vanilla completo — che e' comunque la Fase 1 della ROADMAP.
#
# COSA FA:
#   1. clona (se manca) il mainline vanilla in $KDIR
#   2. genera una .config tarata su questa macchina
#   3. compila
#
# NON installa nulla: l'installazione richiede root ed e' un passo separato
# e piu' delicato (vedi in fondo).
#
# Uso:  ./scripts/build-kernel.sh [--debug] [KDIR]
#       KDIR default: /home/nicfio/linux
#
# --debug aggiunge KASAN, UBSAN, lockdep, KMEMLEAK e compagnia. Serve a una
# cosa sola: cercare nei driver del progetto i difetti che l'ispezione non
# trova — use-after-free, doppi free, corse, inversioni di lock. Il kernel
# Debian di distribuzione non ha nessuna di queste opzioni, quindi finche' non
# si avvia questo, tutto cio' che si dice su memoria e locking e' un'opinione.
#
# Costa: build piu' lenta, immagine piu' grande, macchina molto piu' lenta
# all'uso. E' un kernel da laboratorio, non da tutti i giorni.

set -eu

DEBUG=0
if [ "${1:-}" = "--debug" ]; then
    DEBUG=1
    shift
fi

KDIR="${1:-/home/nicfio/linux}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="$(nproc)"

# ---------------------------------------------------------------------------
# 1. sorgenti
# ---------------------------------------------------------------------------
if [ ! -d "$KDIR/.git" ]; then
    echo "== clone vanilla in $KDIR (shallow) =="
    git clone --depth=1 --single-branch --branch master \
        https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git "$KDIR"
else
    echo "== sorgenti gia' presenti in $KDIR =="
fi

cd "$KDIR"
echo "versione: $(make -s kernelversion)"

# ---------------------------------------------------------------------------
# 2. configurazione
# ---------------------------------------------------------------------------
echo
echo "== configurazione =="

make x86_64_defconfig

# localmodconfig riduce ai soli driver effettivamente in uso su questa
# macchina: la build passa da ~1h a pochi minuti.
#
# ATTENZIONE — trappola verificata sul campo: localmodconfig si basa sui
# moduli CARICATI. Siccome il kernel attuale non ha pinctrl-alderlake, la
# config generata eredita lo stesso difetto (CONFIG_PINCTRL finisce
# disabilitato del tutto). I simboli qui sotto vanno quindi forzati DOPO.
if [ -r /proc/modules ]; then
    lsmod > /tmp/lsmod-intelcam.txt
    yes '' 2>/dev/null | make LSMOD=/tmp/lsmod-intelcam.txt localmodconfig || true
fi

# --- fondamenta: la QUARTA trappola di localmodconfig ----------------------
#
# Trovata il 2026-08-11 rigenerando la config sul kernel Debian. Qui
# i2c-designware-platform e' built-in, quindi non compare fra i moduli
# caricati e localmodconfig lo butta via. Con lui se ne vanno COMMON_CLK e
# REGULATOR, e da li' crolla tutto il resto in cascata:
#
#   COMMON_CLK=n -> HAVE_CLK=n -> VIDEO_CAMERA_SENSOR non e' selezionabile
#                -> spariscono TUTTI i driver di sensore e V4L2_CCI_I2C
#   COMMON_CLK=n -> I2C_DESIGNWARE_PLATFORM dipende da (ACPI && COMMON_CLK)
#                -> nessun bus I2C -> nessun sensore enumerato
#   COMMON_CLK=n, REGULATOR=n -> INTEL_SKL_INT3472 non e' selezionabile
#
# Cinque simboli mancanti, una sola causa. Vanno forzati per primi, perche'
# tutti gli --enable successivi dipendono da questi.
./scripts/config --enable COMMON_CLK
./scripts/config --enable REGULATOR
./scripts/config --enable REGULATOR_FIXED_VOLTAGE
./scripts/config --enable LEDS_CLASS
./scripts/config --enable VIDEO_CAMERA_SENSOR
./scripts/config --module I2C_DESIGNWARE_CORE
./scripts/config --module I2C_DESIGNWARE_PLATFORM

# --- catena GPIO: il semaforo 1 della diagnosi -----------------------------
# INTC1057 (Alder Lake-N) e' mappato su adln_soc_data in
# drivers/pinctrl/intel/pinctrl-alderlake.c. Senza questi, int3472 resta in
# deferred probe e i sensori non ricevono clock/reset.
./scripts/config --enable PINCTRL
./scripts/config --enable PINCTRL_INTEL
./scripts/config --enable PINCTRL_ALDERLAKE

# --- power/clock dei sensori ----------------------------------------------
./scripts/config --module INTEL_SKL_INT3472

# --- catena media ----------------------------------------------------------
for s in MEDIA_SUPPORT MEDIA_CONTROLLER MEDIA_CAMERA_SUPPORT \
         MEDIA_PCI_SUPPORT VIDEO_V4L2_SUBDEV_API VIDEO_CAMERA_SENSOR; do
    ./scripts/config --enable "$s"
done
./scripts/config --module VIDEO_INTEL_IPU6
./scripts/config --module IPU_BRIDGE

# --- template dei due driver da scrivere ----------------------------------
# Non servono a questa macchina: si compilano per avere i template sempre
# verificati e per confrontare il codice nuovo con il loro.
./scripts/config --module VIDEO_GC05A2
./scripts/config --module VIDEO_GC08A3

# --- i due driver del progetto --------------------------------------------
# Esistono solo se le patch locali sono applicate al tree (voci in
# drivers/media/i2c/Kconfig). Se mancano, olddefconfig le scarta in silenzio
# e la verifica al punto 3 se ne accorge.
./scripts/config --module VIDEO_GC5035
./scripts/config --module VIDEO_GC8034

# --- lettura della ACPI NVS a runtime -------------------------------------
# Su questa macchina i parametri dei sensori (lane, MCLK, indirizzo I2C,
# funzioni GPIO) NON sono nella DSDT: sono variabili che il BIOS scrive in
# ACPI NVS al boot. Servono due strade per leggerle, entrambe chiuse sul
# kernel 7.0 preinstallato:
#
#   1. /dev/mem sulla regione NVS. Il 7.0 ha IO_STRICT_DEVMEM=y, che la
#      blocca con EPERM perche' e' claimed da un driver. Qui basta lasciare
#      IO_STRICT_DEVMEM disabilitato (default): STRICT_DEVMEM da solo
#      consente le regioni non-RAM come la NVS.
#   2. acpidbg, che valuta _CRS/SSDB/_DSM come li vede il kernel. Strada
#      migliore della prima: non dipende dalla tabella di offset GNVS, che
#      va rifatta a ogni aggiornamento di BIOS.
./scripts/config --disable IO_STRICT_DEVMEM
./scripts/config --enable ACPI_DEBUGGER
./scripts/config --module ACPI_DEBUGGER_USER

# --- I2C: i sensori stanno su designware ----------------------------------
# Attenzione: i2c-designware-platform NON basta. E' il driver del controller,
# ma su Alder Lake-N i due controller sono dispositivi PCI (00:15.x), non
# platform: chi li vede e crea il platform device e' intel-lpss-pci, cioe'
# MFD_INTEL_LPSS_PCI. Senza di lui il driver designware c'e' e non si aggancia
# a niente, non nasce alcun bus, e i sensori non vengono mai enumerati.
#
# Costato un boot il 2026-08-12: il kernel di debug era partito senza LPSS e
# /sys/bus/i2c/devices conteneva solo SMBus e i bus della grafica. La verifica
# al punto 3 non se n'era accorta perche' guardava solo DESIGNWARE_PLATFORM.
# Built-in e non modulo: questo kernel parte senza initrd.
./scripts/config --enable X86_INTEL_LPSS
./scripts/config --enable MFD_INTEL_LPSS
./scripts/config --enable MFD_INTEL_LPSS_PCI
./scripts/config --enable MFD_INTEL_LPSS_ACPI
./scripts/config --enable I2C_DESIGNWARE_CORE
./scripts/config --enable I2C_DESIGNWARE_PLATFORM

# i2cget di prova-completa.sh legge il chip ID dal bus: serve /dev/i2c-*.
./scripts/config --enable I2C_CHARDEV

# --- perche' la macchina resti USABILE dopo il boot ------------------------
# Seconda trappola di localmodconfig, scoperta sul campo il 2026-08-11 e ben
# piu' cattiva della prima: la config generata NON aveva ne' console su
# framebuffer ne' driver wifi.
#
#   - senza FRAMEBUFFER_CONSOLE, i915 prende lo schermo e non resta alcuna
#     console testuale: schermo nero, nessun prompt di login. Si avvia alla
#     cieca, senza sapere se e' andata bene
#   - senza iwlwifi non c'e' rete, quindi niente SSH come via di riserva
#
# Insieme: nessun modo di capire cosa e' successo. Da verificare a ogni
# rigenerazione della config, non una volta sola.
./scripts/config --enable DRM_FBDEV_EMULATION
./scripts/config --enable FRAMEBUFFER_CONSOLE
./scripts/config --enable FRAMEBUFFER_CONSOLE_DETECT_PRIMARY

# CNVi Wi-Fi 8086:54f0 su questa macchina -> iwlwifi + iwlmvm
./scripts/config --module CFG80211
./scripts/config --module MAC80211
./scripts/config --module IWLWIFI
./scripts/config --module IWLMVM
./scripts/config --enable IWLWIFI_OPMODE_MODULAR

# Terza trappola di localmodconfig, costata il boot fallito del 2026-08-11:
# la config generata aveva "# CONFIG_BT is not set", cioe' l'intero stack
# Bluetooth via. Su questo tablet tastiera e mouse sono Bluetooth: senza BT
# non c'e' NESSUN dispositivo di input, e la macchina e' inservibile anche se
# tutto il resto funziona.
./scripts/config --module BT
./scripts/config --module BT_HCIBTUSB
./scripts/config --module BT_HIDP
./scripts/config --enable BT_BREDR
./scripts/config --enable BT_LE

# --- i915 DEVE essere un modulo, non built-in -----------------------------
# L'altra causa del boot fallito del 2026-08-11, indipendente dalla precedente.
# Un driver built-in fa probe PRIMA che il rootfs sia montato, quindi
# /lib/firmware non esiste ancora e request_firmware() fallisce. Con
# DRM_I915=y: DMC e GuC non caricati -> "GT0: Failed to initialize GPU,
# declaring it wedged" -> schermo inservibile. Il firmware e' installato: il
# problema e' QUANDO avviene il probe, non SE il file c'e'.
#
# Vale per qualunque driver built-in che chieda firmware. Se un giorno si
# aggiunge un initrd, questo vincolo cade — ma finche' si parte senza initrd
# e' obbligatorio.
./scripts/config --module DRM_I915

# --- i due driver del progetto, se il tree li ha ---------------------------
# localmodconfig non li abilita in modo affidabile e senza di loro il kernel
# di prova non serve a niente. Su un tree vanilla pulito i simboli non
# esistono e --enable non fa nulla di male.
for s in VIDEO_GC5035 VIDEO_GC8034; do
    grep -q "config ${s#CONFIG_}" drivers/media/i2c/Kconfig 2>/dev/null &&
        ./scripts/config --module "$s"
done

# --- strumentazione, solo con --debug --------------------------------------
#
# KASAN in modalita' generic (non SW_TAGS, che su x86 non c'e'). KFENCE no:
# campiona, e qui serve deterministico. PROVE_LOCKING tira dentro lockdep,
# DEBUG_ATOMIC_SLEEP prende i "sleeping while atomic", KMEMLEAK le perdite che
# KASAN non vede perche' non sono errori di accesso.
DEBUG_SYMS="KASAN KASAN_GENERIC KASAN_INLINE UBSAN UBSAN_BOUNDS UBSAN_SHIFT
            DEBUG_KERNEL PROVE_LOCKING LOCKDEP DEBUG_ATOMIC_SLEEP
            DEBUG_MUTEXES DEBUG_SPINLOCK DEBUG_LIST DEBUG_OBJECTS
            DEBUG_OBJECTS_FREE DEBUG_KMEMLEAK DEBUG_SG SCHED_STACK_END_CHECK
            DEBUG_PLIST DEBUG_WW_MUTEX_SLOWPATH DETECT_HUNG_TASK
            PANIC_ON_OOPS_VALUE STACKTRACE FRAME_POINTER"
if [ "$DEBUG" -eq 1 ]; then
    echo
    echo "== strumentazione di debug =="
    for s in $DEBUG_SYMS; do ./scripts/config --enable "$s"; done
    # Un oops NON deve fermare la macchina: serve leggere il journal dopo.
    ./scripts/config --disable PANIC_ON_OOPS
    # KMEMLEAK ha bisogno di spazio per la sua contabilita'.
    ./scripts/config --set-val DEBUG_KMEMLEAK_MEM_POOL_SIZE 65536
    ./scripts/config --set-str LOCALVERSION "-intelcam-debug"
else
    ./scripts/config --set-str LOCALVERSION "-intelcam"
fi

make olddefconfig

# ---------------------------------------------------------------------------
# 3. verifica della config PRIMA di compilare
# ---------------------------------------------------------------------------
echo
echo "== verifica simboli obbligatori =="
FAIL=0
check() {
    if grep -qE "^CONFIG_$1=" .config; then
        printf "  [OK] %-26s %s\n" "$1" "$(grep -E "^CONFIG_$1=" .config)"
    else
        printf "  [KO] %-26s NON IMPOSTATO\n" "$1"
        FAIL=1
    fi
}
for s in PINCTRL PINCTRL_INTEL PINCTRL_ALDERLAKE INTEL_SKL_INT3472 \
         VIDEO_INTEL_IPU6 IPU_BRIDGE V4L2_CCI_I2C \
         I2C_DESIGNWARE_PLATFORM MFD_INTEL_LPSS_PCI I2C_CHARDEV \
         VIDEO_GC05A2 VIDEO_GC08A3 \
         ACPI_DEBUGGER ACPI_DEBUGGER_USER \
         FRAMEBUFFER_CONSOLE DRM_FBDEV_EMULATION IWLWIFI IWLMVM \
         BT BT_HCIBTUSB BT_HIDP; do
    check "$s"
done

# Non basta che ci sia: DRM_I915 dev'essere =m. Con =y il boot del 2026-08-11
# e' morto con la GPU wedged. Questo controllo esiste solo per quello.
if grep -qE '^CONFIG_DRM_I915=m' .config; then
    printf "  [OK] %-26s CONFIG_DRM_I915=m (modulo, firmware caricabile)\n" "DRM_I915"
else
    printf "  [KO] %-26s %s\n" "DRM_I915" \
           "$(grep -E '^(CONFIG_DRM_I915=|# CONFIG_DRM_I915 )' .config || echo 'assente')"
    echo "       built-in senza initrd = firmware non caricabile = GPU wedged."
    echo "       Vedi docs/06-azioni-root.md, punto 4."
    FAIL=1
fi

# --- puo' montare la root da solo? ----------------------------------------
# Questo kernel si avvia SENZA initrd, quindi tutto cio' che serve a montare
# /dev/sda2 deve essere built-in, non modulo. Se localmodconfig ne trasforma
# uno in =m — e ext4 e ahci sono moduli sul kernel Debian, quindi puo'
# succedere — il boot muore con "VFS: Unable to mount root fs" e la macchina
# va recuperata a mano. Meglio scoprirlo qui.
echo
echo "== avvio senza initrd: tutto built-in? =="
for s in EXT4_FS ATA SATA_AHCI BLK_DEV_SD SCSI MSDOS_PARTITION EFI_STUB; do
    if grep -qE "^CONFIG_$s=y" .config; then
        printf "  [OK] %-26s =y\n" "$s"
    else
        printf "  [KO] %-26s %s\n" "$s" \
               "$(grep -E "^CONFIG_$s=" .config || echo 'assente')"
        echo "       serve =y: senza initrd un modulo qui non e' caricabile."
        FAIL=1
    fi
done

# Con --debug i simboli di strumentazione sono il motivo per cui si compila:
# se olddefconfig ne ha buttato via qualcuno, meglio saperlo adesso che dopo
# un'ora di build e un riavvio.
if [ "$DEBUG" -eq 1 ]; then
    echo
    echo "== verifica strumentazione =="
    for s in KASAN PROVE_LOCKING DEBUG_ATOMIC_SLEEP DEBUG_KMEMLEAK UBSAN \
             DEBUG_OBJECTS DETECT_HUNG_TASK; do
        check "$s"
    done
fi

[ "$FAIL" -eq 0 ] || { echo; echo "Config incompleta: non compilo."; exit 1; }

# I due driver del progetto non sono in mainline: mancano su un tree pulito.
# Assenti la build e' comunque valida (serve per i semafori 1-3), quindi qui
# si avvisa e basta, non si interrompe.
echo
echo "== driver del progetto (assenti su un tree vanilla pulito) =="
for s in VIDEO_GC5035 VIDEO_GC8034; do
    if grep -qE "^CONFIG_$s=" .config; then
        printf "  [OK]   %-14s %s\n" "$s" "$(grep -E "^CONFIG_$s=" .config)"
    else
        printf "  [--]   %-14s assente: patch locali non applicate al tree\n" "$s"
    fi
done

# La NVS si legge solo se la regione non e' esclusiva. Se questo compare a
# [KO], sul kernel nuovo /dev/mem tornera' a dare EPERM come sul 7.0.
echo
if grep -qE "^CONFIG_IO_STRICT_DEVMEM=y" .config; then
    echo "  [KO]   IO_STRICT_DEVMEM=y -> la ACPI NVS restera' illeggibile via /dev/mem"
else
    echo "  [OK]   IO_STRICT_DEVMEM disabilitato -> ACPI NVS leggibile via /dev/mem"
fi

SUFFIX=""
[ "$DEBUG" -eq 1 ] && SUFFIX="-debug"
cp .config "$PROJECT_DIR/config/intelcam-$(make -s kernelversion)$SUFFIX.config"

# ---------------------------------------------------------------------------
# 4. build
# ---------------------------------------------------------------------------
echo
echo "== build con -j$JOBS (nice, per non bloccare il tablet) =="
nice -n 15 make -j"$JOBS"

echo
echo "Fatto:"
echo "  $KDIR/arch/x86/boot/bzImage"
echo
cat <<'EOF'
INSTALLAZIONE — richiede root, e su questa macchina NON e' banale:

  - /boot e' vuoto, la ESP (sda1) non e' montata
  - nessun bootloader installato come pacchetto
  - il boot avviene via EFI stub: cmdline "vmlinuz initrd=initrd.img root=UUID=..."

Quindi l'immagine e l'initrd vivono direttamente sulla ESP. Procedura:

  sudo mount /dev/sda1 /mnt              # ispezionare PRIMA cosa c'e'
  ls -la /mnt                            # capire i nomi in uso
  # backup dell'immagine attuale prima di sovrascrivere qualsiasi cosa
  sudo make -C /home/nicfio/linux modules_install
  sudo make -C /home/nicfio/linux install     # oppure copia manuale su ESP
  sudo update-initramfs -c -k <versione>

NON sovrascrivere il kernel funzionante: aggiungere una voce separata, cosi'
resta sempre un'immagine con cui riavviare se la nuova non parte.
EOF

#!/bin/bash
# collect-diag.sh — raccolta riproducibile dello stato della catena camera IPU6.
#
# Progetto INTEL-CAMERA — CHUWI Hi10 X1 (Intel N100 / Alder Lake-N)
#
# Uso:
#   ./scripts/collect-diag.sh            # raccolta senza privilegi
#   sudo ./scripts/collect-diag.sh       # include dmesg e journal del kernel
#
# Scrive in data/<timestamp>/ e aggiorna il symlink data/latest.
# Eseguire dopo OGNI modifica al kernel per confrontare gli stati.

set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$PROJECT_DIR/data/$STAMP"
mkdir -p "$OUT"

KREL="$(uname -r)"
MODDIR="/lib/modules/$KREL"

say() { printf '\n===== %s =====\n' "$1"; }

# ---------------------------------------------------------------- identità
{
    say "KERNEL"
    uname -a
    echo "kernel release: $KREL"
    say "OS"
    cat /etc/os-release
    say "DMI"
    for f in sys_vendor product_name product_version board_name \
             bios_version bios_date chassis_type; do
        [ -r "/sys/class/dmi/id/$f" ] && echo "$f: $(cat "/sys/class/dmi/id/$f")"
    done
    say "CPU"
    grep -m1 'model name' /proc/cpuinfo
    grep -c ^processor /proc/cpuinfo | sed 's/^/cores(logical): /'
    say "CMDLINE"
    cat /proc/cmdline
} > "$OUT/00-system.txt" 2>&1

# ------------------------------------------------------------------- ACPI
# I due sensori vivono qui. status=15 -> presente e abilitato, status=0 -> assente.
{
    say "ACPI DEVICES (hid | status | path)"
    for d in /sys/bus/acpi/devices/*/; do
        n=$(basename "$d")
        case "$n" in ACPI0007*|device:*|LNX*) continue ;; esac
        printf '%-16s | status=%-3s | %s\n' \
            "$n" "$(cat "$d/status" 2>/dev/null)" "$(cat "$d/path" 2>/dev/null)"
    done | sort

    say "CAMERA-RELEVANT ACPI (GCTI/INT347x/OVTI/INTC1057)"
    for d in /sys/bus/acpi/devices/*/; do
        n=$(basename "$d")
        case "$n" in
            GCTI*|INT347*|OVTI*|INTC1057*|INT33BE*|TXNW*)
                printf '%-16s | status=%-3s | %s\n' \
                    "$n" "$(cat "$d/status" 2>/dev/null)" "$(cat "$d/path" 2>/dev/null)"
                ;;
        esac
    done
} > "$OUT/01-acpi.txt" 2>&1

# ---------------------------------------------------------------- IPU6/V4L2
{
    say "PCI (IPU6 = classe 0480 / device 8086:462e)"
    lspci -nn

    say "IPU6 DRIVER BINDING"
    ls -l /sys/bus/pci/devices/0000:00:05.0/driver 2>&1 | sed 's/.*-> //'
    cat /sys/bus/pci/devices/0000:00:05.0/uevent 2>/dev/null

    say "V4L2 NODES"
    for d in /sys/class/video4linux/*/; do
        echo "$(basename "$d"): $(cat "$d/name" 2>/dev/null)"
    done | sort -V
    echo "--- subdev sensore presenti? (atteso: nessuno finche' mancano i driver)"
    for d in /sys/class/video4linux/v4l-subdev*/; do
        cat "$d/name" 2>/dev/null
    done | grep -viE 'CSI2' || echo "NESSUN subdev sensore"

    say "MEDIA DEVICES"
    ls -l /dev/media* 2>&1

    say "FIRMWARE IPU"
    ls -l /lib/firmware/intel/ipu/ 2>&1

    say "MODULI CARICATI (camera chain)"
    lsmod | grep -Ei 'ipu|v4l|videobuf|videodev|^mc |int3472|pinctrl' || true
} > "$OUT/02-ipu6.txt" 2>&1

# ------------------------------------------------------- driver disponibili
{
    say "SENSOR DRIVER PRESENTI IN drivers/media/i2c"
    ls "$MODDIR/kernel/drivers/media/i2c/" 2>&1
    echo "--- totale: $(ls "$MODDIR/kernel/drivers/media/i2c/" 2>/dev/null | wc -l)"

    say "CERCA I DRIVER CHE SERVONO (gc5035 / gc8034)"
    find "$MODDIR" \( -iname '*gc5035*' -o -iname '*gc8034*' \) 2>/dev/null \
        || echo "(find non ha prodotto output)"
    grep -riE 'gc5035|gc8034' "$MODDIR/modules.alias" "$MODDIR/modules.builtin" 2>/dev/null \
        || echo "ASSENTI: nessun modulo/builtin per gc5035 o gc8034"

    say "HID SUPPORTATI DA ipu-bridge"
    strings "$MODDIR/kernel/drivers/media/pci/intel/ipu-bridge.ko" 2>/dev/null \
        | grep -E '^(OVTI|INT3|INTC|HIMX|GCTI|SONY|XMCC)[0-9A-Za-z]{4,6}$' | sort -u
    echo "--- GCTI presenti nella tabella?"
    strings "$MODDIR/kernel/drivers/media/pci/intel/ipu-bridge.ko" 2>/dev/null \
        | grep -E '^GCTI' || echo "NO: ipu-bridge non conosce GCTI5035 / GCTI8034"

    say "PINCTRL: chi rivendica INTC1057?"
    grep -iE 'INTC105[5-7]|INTC1085|INT34C[56]' "$MODDIR/modules.alias" 2>/dev/null \
        || echo "(nessun alias)"
    echo "--- driver pinctrl intel compilati:"
    ls "$MODDIR/kernel/drivers/pinctrl/intel/" 2>&1
    echo "--- pinctrl-alderlake presente?"
    find "$MODDIR" -iname '*alderlake*' 2>/dev/null \
        | grep . || echo "ASSENTE: CONFIG_PINCTRL_ALDERLAKE non compilato"
} > "$OUT/03-drivers.txt" 2>&1

# -------------------------------------------------------------- GPIO/INT3472
{
    say "GPIO CHIP PRESENTI"
    ls /sys/bus/gpio/devices/ 2>&1
    echo "(atteso finche' manca pinctrl-alderlake: nessuno)"

    say "INT3472 PLATFORM DEVICES"
    for d in /sys/bus/platform/devices/INT3472*; do
        [ -e "$d" ] || continue
        echo "--- $d"
        echo "path:   $(cat "$d/firmware_node/path" 2>/dev/null)"
        echo "status: $(cat "$d/firmware_node/status" 2>/dev/null)"
        echo "driver: $(ls -l "$d/driver" 2>/dev/null | sed 's/.*-> //' || echo 'NON AGGANCIATO')"
    done

    say "INTC1057 (GPIO controller ADL-N)"
    d=/sys/bus/platform/devices/INTC1057:00
    if [ -e "$d" ]; then
        echo "driver: $(ls -l "$d/driver" 2>/dev/null | sed 's/.*-> //' || echo 'NON AGGANCIATO')"
    else
        echo "device non presente"
    fi

    say "I2C CLIENTS"
    ls -l /sys/bus/i2c/devices/ 2>&1
} > "$OUT/04-gpio-int3472.txt" 2>&1

# ------------------------------------------------------------- test cattura
{
    say "TEST CATTURA /dev/video0"
    echo "atteso allo stato attuale: ENOLINK 'Link has been severed'"
    if command -v ffmpeg >/dev/null; then
        ffmpeg -hide_banner -loglevel error -f v4l2 -i /dev/video0 \
               -frames:v 1 -y "$OUT/capture-test.jpg" 2>&1 | head -10
        [ -s "$OUT/capture-test.jpg" ] && echo "!!! CATTURA RIUSCITA !!!" \
                                       || rm -f "$OUT/capture-test.jpg"
    else
        echo "ffmpeg non installato"
    fi
} > "$OUT/05-capture-test.txt" 2>&1

# ------------------------------------------------------------------- kernel log
if [ "$(id -u)" -eq 0 ]; then
    dmesg > "$OUT/06-dmesg-full.txt" 2>&1
    journalctl -k -b > "$OUT/07-journal-full.txt" 2>&1
    # I WARNING i915 hanno un footer "Modules linked in:" che contiene ipu6 e
    # int3472 e inquina ogni ricerca. Si scarta la riga di intestazione e le sue
    # continuazioni, riconoscibili dai due spazi dopo "kernel:".
    grep -iE 'ipu6|ipu-bridge|int3472|csi2|isys|GCTI|pinctrl|GPIO chip|deferred probe' \
        "$OUT/07-journal-full.txt" \
        | grep -vE 'Modules linked in|kernel:  ' \
        | awk '!seen[$0]++' > "$OUT/08-journal-camera.txt" 2>&1
else
    echo "Eseguito senza root: dmesg e journal non raccolti." \
        > "$OUT/06-kernel-log-MANCANTE.txt"
    echo "Rilanciare con: sudo $0" >> "$OUT/06-kernel-log-MANCANTE.txt"
fi

# ------------------------------------------------------------------- sommario
{
    echo "INTEL-CAMERA — snapshot $STAMP"
    echo "kernel: $KREL"
    echo
    echo "Semafori (OK = risolto, KO = ancora bloccante):"

    if find "$MODDIR" -iname '*alderlake*' 2>/dev/null | grep -q .; then
        echo "  [OK] pinctrl-alderlake compilato"
    else
        echo "  [KO] pinctrl-alderlake ASSENTE  -> INTC1057 senza driver"
    fi

    if [ -n "$(ls /sys/bus/gpio/devices/ 2>/dev/null)" ]; then
        echo "  [OK] gpiochip presente"
    else
        echo "  [KO] nessun gpiochip           -> int3472 non puo' agganciarsi"
    fi

    if ls -l /sys/bus/platform/devices/INT3472:01/driver >/dev/null 2>&1; then
        echo "  [OK] INT3472:01 agganciato"
    else
        echo "  [KO] INT3472:01 NON agganciato -> niente clock/reset ai sensori"
    fi

    if strings "$MODDIR/kernel/drivers/media/pci/intel/ipu-bridge.ko" 2>/dev/null \
        | grep -q '^GCTI'; then
        echo "  [OK] ipu-bridge conosce i GCTI"
    else
        echo "  [KO] ipu-bridge senza voci GCTI -> nessun grafo fwnode CSI-2"
    fi

    if grep -qiE 'gc5035|gc8034' "$MODDIR/modules.alias" 2>/dev/null; then
        echo "  [OK] driver sensore presenti"
    else
        echo "  [KO] gc5035/gc8034 ASSENTI      -> nessun subdev sensore"
    fi

    echo
    echo "File raccolti:"
    ls -1 "$OUT"
} | tee "$OUT/SOMMARIO.txt"

ln -sfn "$STAMP" "$PROJECT_DIR/data/latest"
echo
echo "Snapshot in: $OUT"
echo "Symlink:     $PROJECT_DIR/data/latest"

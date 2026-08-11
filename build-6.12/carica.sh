#!/bin/bash
# carica.sh — mette in piedi la catena camera completa sul kernel in esecuzione.
#
# Progetto INTEL-CAMERA. Sostituisce ipu-bridge di distribuzione con quello che
# conosce i due _HID GCTI*, poi carica i due driver di sensore.
#
# Va rifatto dopo ogni riavvio: qui non si installa niente. E' voluto —
# l'obiettivo del progetto e' mainline, non un'installazione locale.
#
# Uso:  sudo ./carica.sh  [-d]     (-d = scarica tutto e ripristina Debian)

set -eu

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }

scarica() {
    # In ordine inverso di dipendenza. || true: se un modulo non c'e', amen.
    for m in gc5035 gc8034 intel_ipu6_isys intel_ipu6 ipu_bridge; do
        rmmod "$m" 2>/dev/null || true
    done
}

if [ "${1:-}" = "-d" ]; then
    scarica
    modprobe ipu_bridge && modprobe intel_ipu6 && modprobe intel_ipu6_isys
    echo "ripristinato lo stato di Debian"
    exit 0
fi

for m in gc5035.ko gc8034.ko ipu-bridge.ko; do
    [ -f "$DIR/$m" ] || { echo "manca $DIR/$m — lancia prima 'make'"; exit 1; }
done

scarica

# v4l2-cci non e' una dipendenza dichiarata dei .ko fuori albero: senza questo
# insmod fallisce con "Unknown symbol cci_read".
modprobe v4l2-cci

insmod "$DIR/ipu-bridge.ko"
modprobe intel_ipu6
modprobe intel_ipu6_isys
insmod "$DIR/gc5035.ko"
insmod "$DIR/gc8034.ko"

sleep 1

echo
echo "--- sensori agganciati:"
for d in /sys/bus/i2c/devices/i2c-GCTI*; do
    [ -e "$d" ] || continue
    if [ -L "$d/driver" ]; then
        drv=$(basename "$(readlink -f "$d/driver")")
    else
        drv="nessun driver"
    fi
    printf '  %-24s -> %s\n' "$(basename "$d")" "$drv"
done

deferred=$(cat /sys/kernel/debug/devices_deferred 2>/dev/null || true)
[ -n "$deferred" ] && { echo "--- probe rimandate:"; echo "$deferred"; }

echo "--- il grafo si ispeziona con: media-ctl -p"

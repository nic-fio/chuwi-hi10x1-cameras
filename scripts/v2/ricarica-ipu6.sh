#!/bin/bash
# ricarica-ipu6.sh — ricarica sensori e catena IPU6, per provare un altro
# ipu-bridge.ko (le frequenze del collegamento che il firmware dichiara ai
# sensori le scrive ipu-bridge al probe di intel_ipu6).
#
#   sudo scripts/v2/ricarica-ipu6.sh [ipu-bridge.ko]
#
# Con un file: lo installa in /lib/modules/$(uname -r)/updates. Senza: toglie
# quello in updates e torna al modulo del kernel. Le camere non devono essere
# in uso. Ordine: sensori fuori, catena IPU6 fuori, catena dentro (ipu-bridge
# crea i nodi software al probe di intel_ipu6), sensori dentro.
set -eu
U=/lib/modules/$(uname -r)/updates
if [ $# -ge 1 ]; then
    install -m 644 "$1" $U/ipu-bridge.ko
else
    rm -f $U/ipu-bridge.ko
fi
depmod
echo "ipu_bridge da: $(modinfo -n ipu_bridge)"

# il notifier dell'IPU6 tiene i moduli dei sensori: prima l'unbind
for s in gc5035 gc8034; do
    for d in /sys/bus/i2c/drivers/$s/i2c-GCTI*; do
        [ -e "$d" ] && basename "$d" > /sys/bus/i2c/drivers/$s/unbind
    done
done
rmmod gc5035 gc8034
rmmod intel_ipu6_isys intel_ipu6 ipu_bridge
modprobe intel_ipu6
modprobe intel_ipu6_isys || true
modprobe gc5035
modprobe gc8034
for i in $(seq 40); do
    n=$(media-ctl -p 2>/dev/null | grep -cE "entity.*: gc(5035|8034) " || true)
    [ "$n" -eq 2 ] && break
    sleep 0.5
done
media-ctl -p | grep -E "entity.*: gc(5035|8034) " || { echo "sensori non nel grafo"; exit 1; }
dmesg | grep -E "Found supported sensor|Connected [0-9] camera|gc5035|ipu-bridge|ipu_bridge" | tail -6

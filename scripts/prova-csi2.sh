#!/bin/bash
# prova-csi2.sh — da dove vengono gli errori CSI-2 "Transfer FIFO overflow" /
# "Inter-frame packet discarded" (L5, docs/08 e docs/13).
#
# Va lanciata SUBITO dopo l'avvio, prima di qualsiasi altra cattura: la prova
# A conta proprio sul fatto che il primo stream non abbia un arresto prima di
# se'. Su next il ricevitore IPU6 non azzera piu' gli errori all'avvio di uno
# stream (commit eb68e9f1c), quindi quelli registrati durante un arresto
# vengono stampati al primo fotogramma dello stream successivo.
#
#   A  10 stream gc5035, 3 s di pausa (il sensore si spegne in autosuspend)
#   B  come A con il sensore sempre acceso (power/control = on)
#   C  come A sul gc8034, porta a 4 lane
#   D  come A con gli stati C profondi vietati (/dev/cpu_dma_latency = 0)
#
# Lettura: errori mai nello stream 1 e poi negli stream >= 2 di A = errori
# dell'arresto trascinati dal ricevitore; B diverso da A = conta l'accensione
# del sensore; D senza errori = latenza di PM della piattaforma; C uguale ad A
# = non dipende dal gc5035. Tutto a zero = L5 non riprodotto.
#
# Uso:  sudo ./scripts/prova-csi2.sh [directory-di-uscita]

set -u
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$PROJECT_DIR/data/prova-csi2-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }

mark() { echo "PROVA-CSI2 $*" > /dev/kmsg; }
raccogli() { dmesg | grep -E "PROVA-CSI2|csi2-[0-9] error" > "$OUT/$1.txt"; }
giro() { # etichetta sensore
    local i
    for i in $(seq 1 10); do
        mark "$1 stream $i inizio"
        "$PROJECT_DIR/scripts/cattura.sh" "$2" 3 /dev/null >/dev/null 2>&1
        mark "$1 stream $i fine"
        sleep 3
    done
}

uname -r > "$OUT/kernel.txt"
modprobe -a gc5035 gc8034 2>/dev/null

dmesg -C; giro A gc5035; raccogli A

echo on > /sys/bus/i2c/devices/i2c-GCTI5035:00/power/control
dmesg -C; giro B gc5035; raccogli B
echo auto > /sys/bus/i2c/devices/i2c-GCTI5035:00/power/control

dmesg -C; giro C gc8034; raccogli C

python3 -c 'import os,struct,time; fd=os.open("/dev/cpu_dma_latency",os.O_WRONLY); os.write(fd,struct.pack("i",0)); time.sleep(600)' &
LAT=$!
dmesg -C; giro D gc5035; raccogli D
kill "$LAT" 2>/dev/null

for p in A B C D; do
    printf '%s: %d righe di errore CSI-2\n' "$p" "$(grep -c "csi2-[0-9] error" "$OUT/$p.txt")"
done | tee "$OUT/RIEPILOGO.txt"
echo "dettaglio in $OUT"

#!/bin/bash
# ae-finestra.sh — AE di libcamera con e senza gli helper gc5035/gc8034,
# una camera per volta, 90 fotogrammi per caso. Serve la luce del giorno:
# con la luce di sera l'AE va a fondo scala e non dice niente.
# Uso: scripts/ae-finestra.sh gc5035|gc8034 [directory]
set -u
P="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$1"; OUT="${2:-$P/data/ae-finestra-$(date +%Y%m%d)}"; mkdir -p "$OUT"
case "$S" in gc5035) C=1 ;; gc8034) C=2 ;; *) echo "gc5035 o gc8034"; exit 1 ;; esac
ORDINE="${ORDINE:-con-helper:libcamera senza-helper:libcamera-senza-helper}"
for v in $ORDINE; do
    f="$OUT/cam-$S-${v%%:*}-$(date +%H%M%S).log"
    "$HOME/src/${v#*:}/build/src/apps/cam/cam" -c $C --capture=90 --metadata >"$f" 2>&1
    grep -m1 "Using camera" "$f"
    python3 "$P/scripts/riassunto-ae-cam.py" "$f"
done

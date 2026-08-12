#!/bin/bash
# misura-guadagno.sh — solo il test del guadagno analogico, senza il resto.
#
# Progetto INTEL-CAMERA. E' la sezione GUADAGNO di prova-completa.sh estratta,
# perche' e' l'unica verifica che dipende dalla luce della stanza e ogni tanto
# va rifatta da sola. Non fa i cicli di bind/unbind, quindi non fa oopsare il
# kernel per A2 e non perde un minor di /dev/v4l-subdev.
#
# Serve una luce accesa davanti ai sensori. Al buio lo dice e non inventa un
# numero.
#
# Uso:  sudo ./scripts/misura-guadagno.sh

set -u

P="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$P/data/guadagno-$(date +%Y%m%d-%H%M%S)"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }
mkdir -p "$OUT"

declare -A NODE SUBDEV
for s in gc5035 gc8034; do
    line=$("$P/scripts/cattura.sh" "$s" 1 /dev/null 2>&1 | head -1)
    NODE[$s]=$(echo "$line" | grep -oE "/dev/video[0-9]+")
    ent=$(echo "$line" | sed 's/ ->.*//')
    SUBDEV[$s]=$(media-ctl -p 2>/dev/null | awk -v e="$ent" '
        $0 ~ "entity [0-9]+: "e" " {f=1} f && /device node name/ {print $NF; exit}')
    echo "$s -> ${NODE[$s]} (${SUBDEV[$s]})"
done

misura() {
    timeout 60 v4l2-ctl -d "$1" --stream-mmap --stream-count=2 --stream-to="$2" >/dev/null 2>&1
    python3 - "$2" <<'PY'
import array, sys
d = open(sys.argv[1], 'rb').read()
a = array.array('H'); a.frombytes(d[len(d)//2:len(d)//2*2])
sub = a[::17]
print(sum(sub)/len(sub) if sub else 0)
PY
}

for spec in "gc5035:256:4096" "gc8034:64:490"; do
    IFS=: read -r s gmin gmax <<<"$spec"
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    m1=$(misura "${NODE[$s]}" "$OUT/.g1.raw")
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmax 2>/dev/null
    m2=$(misura "${NODE[$s]}" "$OUT/.g2.raw")
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    python3 - "$s" "$m1" "$m2" "$gmin" "$gmax" <<'PY' | tee -a "$OUT/guadagno.txt"
import sys
s, m1, m2, gmin, gmax = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
s1, s2 = max(m1-64, 0.1), max(m2-64, 0.1)
got, want = s2/s1, gmax/gmin
d = abs(got-want)/want*100
if m2 - 64 < 4:
    print(f"[--] {s}: scena ancora troppo scura (segnale {m2:.1f} sul piedistallo 64)")
else:
    esito = "OK" if d <= 25 else "KO"
    print(f"[{esito}] {s}: segnale {m1:.1f} -> {m2:.1f}, rapporto {got:.2f}, atteso {want:.2f}, scarto {d:.1f}% (tolleranza 25%)")
PY
done
rm -f "$OUT/.g1.raw" "$OUT/.g2.raw"
echo "output in $OUT"

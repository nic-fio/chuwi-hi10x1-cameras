#!/bin/bash
# prova-binning.sh — prove del binning 2x2 del GC5035 (driver v2 + binning,
# ipu-bridge con 175,2 MHz), con esito automatico.
#
#   sudo scripts/v2/prova-binning.sh [CARTELLA]
#
# V4L2_COMPLIANCE= come per prova-completa-v2.sh (versione da git).
set -u
D=${1:-$(dirname "$0")/../../data/v2-binning-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$D"
Q=$(cd "$(dirname "$0")" && pwd)
VC=${V4L2_COMPLIANCE:-v4l2-compliance}
ok=0 ko=0
OK() { echo "  [OK] $*"; ok=$((ok + 1)); }
KO() { echo "  [KO] $*"; ko=$((ko + 1)); }

TOPO=$(media-ctl -p 2>/dev/null)
ENT=$(printf '%s\n' "$TOPO" | sed -n "s/^- entity [0-9]*: \(gc5035 [0-9]*-[0-9a-f]*\) .*/\1/p")
[ -n "$ENT" ] || { echo "gc5035 non e' nel grafo"; exit 1; }
SUB=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's|.*device node name \(/dev/v4l-subdev[0-9]*\).*|\1|p')
CSI=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 CSI2 [0-9]*\)":0.*/\1/p')
CAP=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CSI /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 ISYS Capture [0-9]*\)":0.*/\1/p' | head -1)
VID=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CAP /,/^$/p" | sed -n 's|.*device node name \(/dev/video[0-9]*\).*|\1|p')
MB=$(media-ctl -p 2>/dev/null | awk '/^bus info/ {print $3; exit}')

ctrl() { v4l2-ctl -d $SUB -C $1 2>/dev/null | awk -F': ' '{print $2}'; }

# formato: crop di default, poi set_fmt; pipeline al formato risultante
formato() { # LARG ALT
    v4l2-ctl -d $SUB --set-subdev-selection pad=0,target=crop,left=8,top=8,width=2592,height=1944
    v4l2-ctl -d $SUB --set-subdev-fmt pad=0,width=$1,height=$2,code=0x300a
    FMT=$(v4l2-ctl -d $SUB --get-subdev-fmt 0)
    FW=$(printf '%s\n' "$FMT" | sed -n 's|.*Width/Height *: *\([0-9]*\)/\([0-9]*\).*|\1|p')
    FH=$(printf '%s\n' "$FMT" | sed -n 's|.*Width/Height *: *\([0-9]*\)/\([0-9]*\).*|\2|p')
    media-ctl -l "\"$CSI\":1 -> \"$CAP\":0 [1]"
    for pad in "\"$CSI\":0" "\"$CSI\":1"; do media-ctl -V "$pad [fmt:SGRBG10_1X10/${FW}x${FH}]"; done
    v4l2-ctl -d $VID --set-fmt-video="width=$FW,height=$FH,pixelformat=BA10" >/dev/null
}
cattura() { # N USCITA
    v4l2-ctl -d $SUB -C exposure,analogue_gain,vertical_blanking,horizontal_blanking,pixel_rate,link_frequency > $2.txt 2>&1
    echo "formato ${FW}x${FH} bpl $(v4l2-ctl -d $VID --get-fmt-video | awk -F: '/Bytes per Line/ {gsub(/ /,"",$2); print $2}')" >> $2.txt
    timeout 20 v4l2-ctl -d $VID --stream-mmap --stream-count=$1 --stream-to=$2.raw --verbose 2>&1 |
        grep -oE "ts: [0-9.]+" | awk '{print $2}' > $2.ts || true
}
periodo() { python3 -I -c 'import sys,statistics; t=[float(x) for x in open(sys.argv[1])]; print("%d %.4f" % (len(t), statistics.median([b-a for a,b in zip(t,t[1:])])*1e3 if len(t)>1 else 0))' $1; }
vicino() { python3 -I -c 'import sys; a,b,t=map(float,sys.argv[1:]); sys.exit(0 if abs(a-b) <= t*abs(b) else 1)' "$@"; }

echo "===== A. SCELTA DEL BINNING"
v4l2-ctl -d $SUB --list-ctrls-menus 2>/dev/null | grep -A3 link_frequency > $D/menu.txt
grep -q '175200000' $D/menu.txt && OK "LINK_FREQ elenca 175,2 MHz" || KO "LINK_FREQ senza 175,2 MHz: $(tr '\n' ' ' < $D/menu.txt)"
formato 1296 972
[ "$FW" = 1296 ] && [ "$FH" = 972 ] && OK "set_fmt 1296x972 sul crop di default: formato ${FW}x${FH}" || KO "formato ${FW}x${FH} invece di 1296x972"
crop=$(v4l2-ctl -d $SUB --get-subdev-selection pad=0,target=crop | grep -oE "Left [0-9]+, Top [0-9]+, Width [0-9]+, Height [0-9]+")
[ "$crop" = "Left 8, Top 8, Width 2592, Height 1944" ] && OK "crop invariato: $crop" || KO "crop cambiato: $crop"
lf=$(ctrl link_frequency) pr=$(ctrl pixel_rate) hb=$(ctrl horizontal_blanking) vb=$(ctrl vertical_blanking)
[ "$lf" = 1 ] && OK "LINK_FREQ alla voce 1 (175,2 MHz)" || KO "LINK_FREQ alla voce $lf"
[ "$pr" = 70080000 ] && OK "PIXEL_RATE 70080000" || KO "PIXEL_RATE $pr"
[ "$hb" = 164 ] && OK "HBLANK 164 (riga di 1460)" || KO "HBLANK $hb"
[ "$vb" = 1024 ] && OK "VBLANK 1024 (1996 righe)" || KO "VBLANK $vb"

echo "===== B. CATTURA E TEMPI"
cattura 30 $D/bin
read -r n p <<<"$(periodo $D/bin.ts)"
att=$(python3 -I -c "print('%.4f' % ((1296+164)*(972+1024)/70.08e6*1e3))")
[ "$n" = 30 ] && OK "30/30 fotogrammi" || KO "$n/30 fotogrammi"
vicino $p $att 0.005 && OK "periodo $p ms, modello $att" || KO "periodo $p ms, modello $att"
v4l2-ctl -d $SUB --set-ctrl=vertical_blanking=2000
cattura 10 $D/bin-vb2000
read -r n p <<<"$(periodo $D/bin-vb2000.ts)"
att=$(python3 -I -c "print('%.4f' % ((1296+164)*(972+2000)/70.08e6*1e3))")
vicino $p $att 0.005 && OK "C. VBLANK 2000: periodo $p ms, modello $att" || KO "C. VBLANK 2000: periodo $p ms, modello $att"
v4l2-ctl -d $SUB --set-ctrl=vertical_blanking=1024

echo "===== E. ESPOSIZIONE IN RIGHE DEL SENSORE"
v4l2-ctl -d $SUB --set-ctrl=exposure=300; cattura 4 $D/bin-e300
v4l2-ctl -d $SUB --set-ctrl=exposure=600; cattura 4 $D/bin-e600
v4l2-ctl -d $SUB --set-ctrl=exposure=984
r=$(python3 -I - $D/bin-e300.raw $D/bin-e600.raw <<'EOF'
import sys, numpy as np
def m(f):
    a = np.fromfile(f, np.uint16).reshape(-1, 972, 1296)[-1].astype(float)
    return a
a, b = m(sys.argv[1]), m(sys.argv[2])
sel = (b < 900)            # niente pixel vicini alla saturazione
print("%.3f %.1f" % (((b[sel] - 64).mean()) / ((a[sel] - 64).mean()), (b[sel] - 64).mean()))
EOF
)
read -r rap seg <<<"$r"
vicino $rap 2 0.08 && OK "esposizione 600/300: segnale x$rap (atteso 2, segnale $seg)" || KO "esposizione 600/300: segnale x$rap (atteso 2, segnale $seg)"

echo "===== D. POSIZIONE E MEDIA (contro il modo pieno)"
formato 2592 1944
lf=$(ctrl link_frequency) pr=$(ctrl pixel_rate)
[ "$lf" = 0 ] && [ "$pr" = 168960000 ] && OK "F. ritorno a 2592x1944: LINK_FREQ voce 0, PIXEL_RATE 168960000" || KO "F. ritorno a 2592x1944: LINK_FREQ $lf, PIXEL_RATE $pr"
cattura 8 $D/pieno
read -r n p <<<"$(periodo $D/pieno.ts)"
att=$(python3 -I -c "print('%.4f' % ((2592+328)*(1944+64)/168.96e6*1e3))")
vicino $p $att 0.005 && OK "F. periodo a piena risoluzione $p ms, modello $att" || KO "F. periodo a piena risoluzione $p ms, modello $att"
formato 1296 972
cattura 8 $D/bin2
res=$(python3 -I - $D/pieno.raw $D/bin2.raw <<'EOF'
import sys, numpy as np
P = np.fromfile(sys.argv[1], np.uint16).reshape(-1, 1944, 2592)[2:].astype(float).mean(0)
B = np.fromfile(sys.argv[2], np.uint16).reshape(-1, 972, 1296)[2:].astype(float).mean(0)
# media dei quattro pixel dello stesso colore: blocchi 4x4 del mosaico pieno
M = np.zeros_like(B)
for py in (0, 1):
    for px in (0, 1):
        q = P[py::2, px::2]
        q = (q[0::2, 0::2] + q[0::2, 1::2] + q[1::2, 0::2] + q[1::2, 1::2]) / 4
        M[py::2, px::2] = q
best = None
for dy in range(-4, 5):
    for dx in range(-4, 5):
        a = M[8 + dy:-8 + dy or None, 8 + dx:-8 + dx or None]
        b = B[8:-8, 8:-8]
        r = np.corrcoef(a.ravel(), b.ravel())[0, 1]
        if best is None or r > best[0]:
            best = (r, dy, dx)
print("%.4f %d %d" % best)
EOF
)
read -r rr dy dx <<<"$res"
if [ "$dy" = 0 ] && [ "$dx" = 0 ] && python3 -I -c "import sys; sys.exit(0 if $rr > 0.9 else 1)"; then
    OK "binning = media 2x2 per colore del pieno, spostamento (0,0), r $rr"
else
    KO "spostamento ($dy,$dx), r $rr"
fi

echo "===== H. ENUMERAZIONE, ESPOSIZIONE MASSIMA, CICLI"
v4l2-ctl -d $SUB --list-subdev-framesizes pad=0,code=0x300a > $D/framesizes.txt 2>&1
grep -q '1296x972' $D/framesizes.txt && OK "enum_frame_size elenca 1296x972" || KO "enum_frame_size: $(tr '\n' ' ' < $D/framesizes.txt)"
formato 1296 972
v4l2-ctl -d $SUB --set-ctrl=exposure=1980
cattura 10 $D/bin-emax
read -r n p <<<"$(periodo $D/bin-emax.ts)"
vicino $p 41.585 0.005 && [ "$n" = 10 ] && OK "esposizione massima 1980: $n fotogrammi, periodo $p ms" || KO "esposizione massima 1980: $n fotogrammi, periodo $p ms"
v4l2-ctl -d $SUB --set-ctrl=exposure=984
# 20 avvii e arresti di fila (dentro il secondo di autosuspend)
bad=0
for i in $(seq 20); do
    cattura 3 $D/ciclo
    read -r n p <<<"$(periodo $D/ciclo.ts)"
    [ "$n" = 3 ] || bad=$((bad + 1))
    python3 -I -c 'import sys,numpy as np; a=np.fromfile(sys.argv[1],np.uint16).reshape(-1,972,1296); sys.exit(0 if a.shape[0]==3 and a[0].max()>0 and abs(float(a[0].mean())-float(a[2].mean()))<0.1*float(a[2].mean())+5 else 1)' $D/ciclo.raw || bad=$((bad + 1))
done
[ $bad = 0 ] && OK "20 cicli di avvio/arresto in binning, primo fotogramma come il terzo" || KO "20 cicli: $bad problemi"
# binning -> pieno -> binning senza spegnere il sensore
formato 2592 1944; cattura 3 $D/salto-pieno
formato 1296 972; cattura 3 $D/salto-bin
read -r n1 p1 <<<"$(periodo $D/salto-pieno.ts)"; read -r n2 p2 <<<"$(periodo $D/salto-bin.ts)"
[ "$n1" = 3 ] && [ "$n2" = 3 ] && vicino $p2 41.585 0.005 && OK "pieno -> binning senza spegnimento: periodo $p2 ms" || KO "salto di modo: $n1 e $n2 fotogrammi, periodo $p2 ms"

echo "===== G. V4L2-COMPLIANCE"
formato 1296 972
timeout 300 $VC -z $MB -u $SUB > $D/compliance-binning.txt 2>&1
t=$(grep -E '^Total' $D/compliance-binning.txt)
echo "$t" | grep -q 'Failed: 0, Warnings: 0' && OK "binning: $t" || KO "binning: $t"
formato 2592 1944
timeout 300 $VC -z $MB -u $SUB > $D/compliance-pieno.txt 2>&1
t=$(grep -E '^Total' $D/compliance-pieno.txt)
echo "$t" | grep -q 'Failed: 0, Warnings: 0' && OK "pieno: $t" || KO "pieno: $t"

echo "===== VERDETTO: $ok superate, $ko fallite — $D"
rm -f $D/*.raw

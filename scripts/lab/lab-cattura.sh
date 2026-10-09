#!/bin/bash
# lab-cattura.sh — cattura col driver DA LABORATORIO (patches/wip/lab).
#
#   sudo scripts/lab/lab-cattura.sh SENSORE LARG ALT CODICE NFRAME USCITA [REGS]
#
# SENSORE gc5035|gc8034; CODICE RGGB|GRBG|GBRG|BGGR; REGS: file con righe
# "pagina registro valore" scritte in /sys/kernel/debug/SENSORE-lab/regs
# prima dello stream (senza file: nessuna scrittura in piu').
# Scrive USCITA.raw (fotogrammi uint16 grezzi, righe di BPL byte) e USCITA.txt
# (formato, bytesperline, controlli, registri, timestamp dei buffer).
# Controlli ai default prima di catturare; esposizione/guadagno/vblank si
# possono forzare con LAB_CTRL="exposure=...,analogue_gain=...".

set -eu
S=$1 W=$2 H=$3 C=$4 N=$5 OUT=$6 REGS=${7:-}

case $C in
    RGGB) MBUS=SRGGB10_1X10 PIX=RG10 ;;
    GRBG) MBUS=SGRBG10_1X10 PIX=BA10 ;;
    GBRG) MBUS=SGBRG10_1X10 PIX=GB10 ;;
    BGGR) MBUS=SBGGR10_1X10 PIX=BG10 ;;
    *) echo "codice $C?"; exit 1 ;;
esac

DBG=/sys/kernel/debug/$S-lab/regs
[ -w $DBG ] || { echo "manca $DBG: driver da laboratorio non caricato?"; exit 1; }
if [ -n "$REGS" ]; then grep -v '^#' "$REGS" > $DBG; else echo > $DBG; fi

TOPO=$(media-ctl -p 2>/dev/null)
ENT=$(printf '%s\n' "$TOPO" | sed -n "s/^- entity [0-9]*: \($S [0-9]*-[0-9a-f]*\) .*/\1/p")
[ -n "$ENT" ] || { echo "$S non e' nel grafo"; exit 1; }
SUB=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's|.*device node name \(/dev/v4l-subdev[0-9]*\).*|\1|p')
CSI=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 CSI2 [0-9]*\)":0.*/\1/p')
CAP=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CSI /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 ISYS Capture [0-9]*\)":0.*/\1/p' | head -1)
VID=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CAP /,/^$/p" | sed -n 's|.*device node name \(/dev/video[0-9]*\).*|\1|p')

media-ctl -l "\"$CSI\":1 -> \"$CAP\":0 [1]"
for pad in "\"$ENT\":0" "\"$CSI\":0" "\"$CSI\":1"; do
    media-ctl -V "$pad [fmt:$MBUS/${W}x${H}]"
done
v4l2-ctl -d $VID --set-fmt-video="width=$W,height=$H,pixelformat=$PIX" >/dev/null

# Controlli dopo il formato (i limiti dipendono dall'altezza). Il vblank va
# per primo: il driver da laboratorio rifiuta un vblank che porta il massimo
# dell'esposizione sotto il suo default (fisso, pensato per l'altezza piena).
def=$(v4l2-ctl -d $SUB -l 2>/dev/null | awk '/flags=read-only/ {next} / default=/ { for (i = 1; i <= NF; i++) if ($i ~ /^default=/) { sub(/default=/, "", $i); printf "%s %s\n", $1, $i } }')
vb=$(printf '%s\n' "${LAB_CTRL:-}" | tr ',' '\n' | sed -n 's/^vertical_blanking=//p')
[ -n "$vb" ] || vb=$(printf '%s\n' "$def" | awk '$1 == "vertical_blanking" {print $2}')
[ -n "$vb" ] && v4l2-ctl -d $SUB --set-ctrl="vertical_blanking=$vb"
def=$(printf '%s\n' "$def" | awk '$1 != "vertical_blanking" && NF == 2 {printf "%s%s=%s", sep, $1, $2; sep = ","}')
[ -n "$def" ] && v4l2-ctl -d $SUB --set-ctrl="$def"
[ -n "${LAB_CTRL:-}" ] && v4l2-ctl -d $SUB --set-ctrl="$LAB_CTRL"
BPL=$(v4l2-ctl -d $VID --get-fmt-video | awk -F: '/Bytes per Line/ {gsub(/ /,"",$2); print $2}')

{
    echo "sensore $S $ENT $SUB $CSI $VID"
    echo "formato ${W}x${H} $C bpl $BPL n $N"
    echo "regs:"; cat $DBG
    echo "controlli:"; v4l2-ctl -d $SUB -C exposure,analogue_gain,vertical_blanking,horizontal_blanking,pixel_rate 2>/dev/null
} > $OUT.txt

if ! timeout 15 v4l2-ctl -d $VID --stream-mmap --stream-count=$N --stream-to=$OUT.raw --verbose 2>&1 \
        | grep -E "ts:|error|Error" > $OUT.ts; then
    true
fi
# rilettura dal sensore subito dopo lo stream on (driver da laboratorio con
# il file rilettura; "!" = valore diverso da quello scritto)
RB=/sys/kernel/debug/$S-lab/rilettura
if [ -r $RB ]; then { echo "rilettura:"; cat $RB; } >> $OUT.txt; fi
echo "timestamp:" >> $OUT.txt
grep -o "ts: [0-9.]*" $OUT.ts | awk '{print $2}' >> $OUT.txt || true
dmesg | tail -5 | grep -E "$S|lab|csi|isys" >> $OUT.txt || true
echo "$OUT.raw: $(stat -c%s $OUT.raw) byte (attesi $((BPL*H*N)))"

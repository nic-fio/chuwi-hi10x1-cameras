#!/bin/bash
# cattura-crop.sh — cattura con i driver v2, impostando il crop sul subdev.
#
#   sudo scripts/v2/cattura-crop.sh SENSORE LEFT TOP WIDTH HEIGHT NFRAME USCITA [CONTROLLI]
#
# Chiede al sensore il rettangolo di crop (VIDIOC_SUBDEV_S_SELECTION), legge
# quello che il driver ha davvero impostato e il formato che ne segue, porta
# la pipeline IPU6 a quel formato e cattura. CONTROLLI: "vertical_blanking=...,
# exposure=..." applicati dopo il crop. Scrive USCITA.raw e USCITA.txt nel
# formato di scripts/lab/lab-cattura.sh (gli analizzatori del laboratorio li
# leggono senza modifiche), con in piu' le righe "crop" e "chiesto".

set -eu
S=$1 L=$2 T=$3 W=$4 H=$5 N=$6 OUT=$7 CTRL=${8:-}

TOPO=$(media-ctl -p 2>/dev/null)
ENT=$(printf '%s\n' "$TOPO" | sed -n "s/^- entity [0-9]*: \($S [0-9]*-[0-9a-f]*\) .*/\1/p")
[ -n "$ENT" ] || { echo "$S non e' nel grafo"; exit 1; }
SUB=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's|.*device node name \(/dev/v4l-subdev[0-9]*\).*|\1|p')
CSI=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENT /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 CSI2 [0-9]*\)":0.*/\1/p')
CAP=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CSI /,/^$/p" | sed -n 's/.*-> "\(Intel IPU6 ISYS Capture [0-9]*\)":0.*/\1/p' | head -1)
VID=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CAP /,/^$/p" | sed -n 's|.*device node name \(/dev/video[0-9]*\).*|\1|p')

v4l2-ctl -d $SUB --set-subdev-selection pad=0,target=crop,left=$L,top=$T,width=$W,height=$H
CROP=$(v4l2-ctl -d $SUB --get-subdev-selection pad=0,target=crop | grep -oE "Left [0-9]+, Top [0-9]+, Width [0-9]+, Height [0-9]+")
FMT=$(v4l2-ctl -d $SUB --get-subdev-fmt 0)
FW=$(printf '%s\n' "$FMT" | sed -n 's|.*Width/Height *: *\([0-9]*\)/\([0-9]*\).*|\1|p')
FH=$(printf '%s\n' "$FMT" | sed -n 's|.*Width/Height *: *\([0-9]*\)/\([0-9]*\).*|\2|p')
CODE=$(printf '%s\n' "$FMT" | sed -n "s/.*Mediabus Code *: *0x[0-9a-f]* (MEDIA_BUS_FMT_\([A-Z0-9_]*\)).*/\1/p")
case $CODE in
    SRGGB10_1X10) C=RGGB PIX=RG10 ;;
    SGRBG10_1X10) C=GRBG PIX=BA10 ;;
    SGBRG10_1X10) C=GBRG PIX=GB10 ;;
    SBGGR10_1X10) C=BGGR PIX=BG10 ;;
    *) echo "codice $CODE?"; exit 1 ;;
esac

media-ctl -l "\"$CSI\":1 -> \"$CAP\":0 [1]"
for pad in "\"$CSI\":0" "\"$CSI\":1"; do
    media-ctl -V "$pad [fmt:$CODE/${FW}x${FH}]"
done
v4l2-ctl -d $VID --set-fmt-video="width=$FW,height=$FH,pixelformat=$PIX" >/dev/null
BPL=$(v4l2-ctl -d $VID --get-fmt-video | awk -F: '/Bytes per Line/ {gsub(/ /,"",$2); print $2}')

# controlli ai default, poi quelli chiesti
def=$(v4l2-ctl -d $SUB -l 2>/dev/null | awk '/flags=read-only/ {next} / default=/ { for (i = 1; i <= NF; i++) if ($i ~ /^default=/) { sub(/default=/, "", $i); printf "%s%s=%s", sep, $1, $i; sep = "," } }')
[ -n "$def" ] && v4l2-ctl -d $SUB --set-ctrl="$def"
[ -n "$CTRL" ] && v4l2-ctl -d $SUB --set-ctrl="$CTRL"

{
    echo "sensore $S $ENT $SUB $CSI $VID"
    echo "formato ${FW}x${FH} $C bpl $BPL n $N"
    echo "chiesto $L $T $W $H"
    echo "crop $CROP"
    echo "controlli:"; v4l2-ctl -d $SUB -C exposure,analogue_gain,vertical_blanking,horizontal_blanking,pixel_rate 2>/dev/null
} > $OUT.txt

timeout 15 v4l2-ctl -d $VID --stream-mmap --stream-count=$N --stream-to=$OUT.raw --verbose 2>&1 \
    | grep -E "ts:|error|Error" > $OUT.ts || true
echo "timestamp:" >> $OUT.txt
grep -o "ts: [0-9.]*" $OUT.ts | awk '{print $2}' >> $OUT.txt || true
echo "$OUT.raw: $(stat -c%s $OUT.raw) byte (attesi $((BPL*FH*N))) crop $CROP"

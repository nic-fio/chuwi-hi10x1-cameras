#!/bin/bash
# cattura.sh — configura la pipeline IPU6 e cattura da uno dei due sensori.
#
# Progetto INTEL-CAMERA. Fa da solo le tre cose che servono e che sono facili
# da sbagliare: abilita il link CSI2 -> nodo di cattura, propaga lo stesso
# formato lungo tutta la catena, e cattura sul nodo giusto.
#
# Uso:
#   ./cattura.sh gc5035 [n_frame] [uscita.raw]
#   ./cattura.sh gc8034 [n_frame] [uscita.raw]
#
# Poi:  scripts/raw-to-png.py uscita.raw LARG ALT PATTERN
#
# I nomi delle entita' e i numeri dei nodi NON sono stabili fra un boot e
# l'altro: vengono ricavati da 'media-ctl -p', non scritti a mano.

set -eu

SENSORE="${1:-}"
NFRAME="${2:-5}"

case "$SENSORE" in
    gc5035) W=2592; H=1944; MBUS=SGRBG10_1X10; PIXFMT=BA10; PATTERN=grbg ;;
    gc8034) W=3264; H=2448; MBUS=SRGGB10_1X10; PIXFMT=RG10; PATTERN=rggb ;;
    *) echo "uso: $0 {gc5035|gc8034} [n_frame] [uscita.raw]"; exit 1 ;;
esac

OUT="${3:-$SENSORE.raw}"

command -v media-ctl >/dev/null || { echo "manca v4l-utils"; exit 1; }
TOPO="$(media-ctl -p 2>/dev/null)" || { echo "nessun device media"; exit 1; }

# Nome completo dell'entita' sensore, indirizzo I2C compreso: "gc5035 3-003f".
ENTITA=$(printf '%s\n' "$TOPO" | sed -n "s/^- entity [0-9]*: \($SENSORE [0-9]*-[0-9a-f]*\) .*/\1/p")
[ -n "$ENTITA" ] || { echo "$SENSORE non e' nel grafo — hai lanciato build-6.12/carica.sh?"; exit 1; }

# Il CSI2 a cui e' cablato, e da li' il primo nodo di cattura a valle.
CSI=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $ENTITA /,/^$/p" \
      | sed -n 's/.*-> "\(Intel IPU6 CSI2 [0-9]*\)":0.*/\1/p')
[ -n "$CSI" ] || { echo "$ENTITA non e' collegato a nessun CSI2"; exit 1; }

CAPTURE=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CSI /,/^$/p" \
          | sed -n 's/.*-> "\(Intel IPU6 ISYS Capture [0-9]*\)":0.*/\1/p' | head -1)
VIDEO=$(printf '%s\n' "$TOPO" | sed -n "/^- entity .*: $CAPTURE /,/^$/p" \
        | sed -n 's|.*device node name \(/dev/video[0-9]*\).*|\1|p')
[ -n "$VIDEO" ] || { echo "non trovo il nodo di cattura a valle di $CSI"; exit 1; }

echo "$ENTITA -> $CSI -> $CAPTURE ($VIDEO)"

media-ctl -l "\"$CSI\":1 -> \"$CAPTURE\":0 [1]"
for pad in "\"$ENTITA\":0" "\"$CSI\":0" "\"$CSI\":1"; do
    media-ctl -V "$pad [fmt:$MBUS/${W}x${H}]"
done
v4l2-ctl -d "$VIDEO" --set-fmt-video="width=$W,height=$H,pixelformat=$PIXFMT" >/dev/null

v4l2-ctl -d "$VIDEO" --stream-mmap --stream-count="$NFRAME" --stream-to="$OUT"

echo "$OUT — $(stat -c%s "$OUT") byte, $NFRAME fotogrammi da ${W}x${H}"
echo "per guardarli:  scripts/raw-to-png.py $OUT $W $H $PATTERN"

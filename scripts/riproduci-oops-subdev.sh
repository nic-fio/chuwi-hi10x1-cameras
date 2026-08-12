#!/bin/bash
# riproduci-oops-subdev.sh — provoca a comando il NULL deref di subdev_open().
#
# Progetto INTEL-CAMERA. Reperto A2 di docs/09-revisione-preinvio.md.
#
# ATTENZIONE: questo script FA ANDARE IN OOPS IL KERNEL. E' quello che deve
# fare. L'oops uccide il processo che apriva il nodo, non il kernel: la
# macchina resta in piedi, ma ogni colpo perde per sempre un minor di
# /dev/v4l-subdev e le strutture agganciate. Non lanciarlo per sport.
#
# La finestra: v4l2_device_unregister_subdev() azzera sd->v4l2_dev PRIMA di
# togliere il nodo, quindi fra l'una e l'altra c'e' un /dev/v4l-subdevN
# apribile il cui sd->v4l2_dev e' gia' NULL. subdev_open() lo dereferenzia
# senza controllarlo. In mezzo c'e' anche media_device_unregister_entity(),
# che dorme: la finestra e' larga, e infatti la si becca da soli con udev.
#
# Uso:  sudo ./riproduci-oops-subdev.sh [gc5035|gc8034] [n_cicli]

set -u

SENSORE="${1:-gc5035}"
CICLI="${2:-200}"
APRITORI=4

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0 $*"; exit 1; }
[ -d "/sys/bus/i2c/drivers/$SENSORE" ] || { echo "$SENSORE non e' caricato"; exit 1; }

DEV=$(basename "$(ls -d "/sys/bus/i2c/drivers/$SENSORE"/i2c-GCTI* 2>/dev/null | head -1)" 2>/dev/null)
[ -n "$DEV" ] || { echo "$SENSORE non e' agganciato a nessun device"; exit 1; }

# Gli apritori: aprono e chiudono ogni /dev/v4l-subdev* il piu' in fretta
# possibile. Quello che becca la finestra viene ucciso dall'oops; e' il
# segnale che cerchiamo, non un errore dello script.
#
# exec: senza, il PID che bash registra e' quello della subshell e non quello
# di python, e alla fine restano in giro dei processi che nessuno uccide.
apritore() {
    exec python3 - <<'PY' >/dev/null 2>&1
import os, glob
while True:
    for n in glob.glob('/dev/v4l-subdev*'):
        try:
            os.close(os.open(n, os.O_RDWR))
        except OSError:
            pass
PY
}

echo "sensore   : $SENSORE ($DEV)"
echo "cicli max : $CICLI, con $APRITORI apritori"
echo

dmesg -C
PID=()
set +m                     # niente "Ucciso": l'apritore che muore e' il segnale
for _ in $(seq 1 $APRITORI); do apritore & PID+=($!); done
trap 'kill "${PID[@]}" 2>/dev/null; exit 130' INT TERM
trap 'kill "${PID[@]}" 2>/dev/null' EXIT

for i in $(seq 1 "$CICLI"); do
    echo "$DEV" > "/sys/bus/i2c/drivers/$SENSORE/unbind" 2>/dev/null
    echo "$DEV" > "/sys/bus/i2c/drivers/$SENSORE/bind"   2>/dev/null
    if dmesg | grep -q 'BUG: kernel NULL pointer'; then
        echo "riprodotto al ciclo $i"
        echo
        dmesg | grep -A 3 'BUG: kernel NULL pointer' | head -8
        exit 0
    fi
done

echo "non riprodotto in $CICLI cicli — la finestra c'e' lo stesso, vedi docs/09"
exit 1

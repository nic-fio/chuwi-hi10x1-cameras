#!/bin/bash
# fix-pinctrl-alderlake.sh — abilita il driver GPIO mancante sul kernel locale.
#
# Progetto INTEL-CAMERA — CHUWI Hi10 X1
#
# CONTESTO — leggere prima di eseguire:
#
# Questo NON e' materiale da inviare a mainline. CONFIG_PINCTRL_ALDERLAKE e il
# suo ID ACPI INTC1057 sono in mainline dalla 5.18. Che manchi su questa
# macchina e' un difetto del .config con cui e' stato compilato il kernel 7.0
# locale (build da /root/linux-7.0, tutti gli altri pinctrl Intel presenti,
# alderlake no).
#
# Serve pero' per SVILUPPARE: senza GPIO chip, int3472 non si aggancia e i
# sensori restano senza reset/powerdown/clock. Nessun driver sensore potrebbe
# essere testato.
#
# Compila solo drivers/pinctrl/intel: pochi minuti, nessun riavvio.
#
# ---------------------------------------------------------------------------
# STATO: NON UTILIZZABILE SU QUESTA MACCHINA — verificato il 2026-08-11
#
# Lo script presuppone di avere i sorgenti del kernel IN ESECUZIONE, per
# compilare un modulo con lo stesso vermagic. Su questa macchina non ci sono:
#
#     /lib/modules/7.0/build -> /root/linux-7.0     <-- symlink ROTTO
#     /root/linux-7.0                                <-- non esiste
#     /proc/config.gz                                <-- assente
#
# Senza sorgenti E senza la .config con cui il 7.0 e' stato compilato, non e'
# possibile produrre un modulo caricabile da questo kernel. Ricostruire la
# config a mano e sperare che il vermagic combaci non e' una strada seria.
#
# STRADA CORRETTA: ./scripts/build-kernel.sh
# Costruisce un kernel vanilla completo con CONFIG_PINCTRL_ALDERLAKE=y, che e'
# comunque la Fase 1 della ROADMAP e risolve i semafori 1-3 in un colpo solo.
#
# Questo file resta come documentazione del tentativo e per il caso in cui i
# sorgenti del 7.0 ricompaiano.
# ---------------------------------------------------------------------------
#
# Uso:  sudo ./scripts/fix-pinctrl-alderlake.sh [KERNEL_SRC]
#       KERNEL_SRC default: /lib/modules/$(uname -r)/build

set -eu

KSRC="${1:-/lib/modules/$(uname -r)/build}"

[ "$(id -u)" -eq 0 ] || { echo "Serve root. Rilancia con sudo."; exit 1; }

if [ ! -d "$KSRC" ]; then
    cat >&2 <<EOF
Sorgenti kernel non trovate in: $KSRC

$(if [ -L "$KSRC" ]; then echo "  (e' un symlink rotto -> $(readlink "$KSRC"))"; fi)

Non e' un problema risolvibile da questo script: senza i sorgenti e la .config
originali del kernel $(uname -r) non si puo' compilare un modulo compatibile.

Usa invece:  ./scripts/build-kernel.sh
Costruisce un kernel vanilla con PINCTRL_ALDERLAKE gia' abilitato e risolve i
semafori 1, 2 e 3 insieme. Vedi ROADMAP.md, Fase 1.
EOF
    exit 1
fi
[ -f "$KSRC/.config" ] || { echo "Manca $KSRC/.config"; exit 1; }

cd "$KSRC"

echo "== stato attuale del simbolo =="
grep -E 'PINCTRL_ALDERLAKE' .config || echo "(simbolo assente dal .config)"

echo
echo "== abilitazione come modulo =="
./scripts/config --module CONFIG_PINCTRL_ALDERLAKE
make olddefconfig
grep -E 'PINCTRL_ALDERLAKE' .config

echo
echo "== build del solo drivers/pinctrl/intel =="
make modules_prepare
make M=drivers/pinctrl/intel modules
make M=drivers/pinctrl/intel modules_install
depmod -a

echo
echo "== caricamento =="
modprobe pinctrl-alderlake

echo
echo "== verifica =="
echo "--- gpiochip:"
ls /sys/bus/gpio/devices/ 2>/dev/null || echo "NESSUNO (il fix non ha funzionato)"
echo "--- INTC1057 driver:"
ls -l /sys/bus/platform/devices/INTC1057:00/driver 2>/dev/null | sed 's/.*-> //' \
    || echo "NON agganciato"
echo "--- INT3472 driver:"
for d in /sys/bus/platform/devices/INT3472:0[12]; do
    [ -e "$d" ] || continue
    echo "$(basename "$d"): $(ls -l "$d/driver" 2>/dev/null | sed 's/.*-> //' \
        || echo 'NON agganciato')"
done
echo "--- ultimi messaggi kernel:"
dmesg | grep -iE 'int3472|pinctrl|gpio' | tail -15

echo
echo "ATTESO DOPO IL FIX:"
echo "  - compare un gpiochip"
echo "  - INTC1057:00 agganciato a pinctrl-alderlake"
echo "  - INT3472:01 e :02 agganciati a int3472-discrete"
echo
echo "Le fotocamere NON funzioneranno ancora: mancano i driver dei sensori."
echo "Questo sblocca solo l'alimentazione. Rilanciare poi collect-diag.sh"
echo "per fotografare il nuovo stato dei semafori."

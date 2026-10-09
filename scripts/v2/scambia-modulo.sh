#!/bin/bash
# scambia-modulo.sh — carica un altro gc5035.ko/gc8034.ko a stream fermo.
#
#   sudo scripts/v2/scambia-modulo.sh SENSORE FILE.ko
#
# Installa FILE.ko in /lib/modules/$(uname -r)/updates, stacca il sensore
# dal driver (unbind), scarica il modulo e lo ricarica. Non serve riavviare:
# il sensore torna nel grafo media al bind, gli stream vanno riconfigurati.
set -eu
S=$1 KO=$2
install -m 644 "$KO" /lib/modules/$(uname -r)/updates/$S.ko
depmod
dev=$(basename "$(ls -d /sys/bus/i2c/drivers/$S/i2c-GCTI* 2>/dev/null | head -1)")
[ -n "$dev" ] && echo "$dev" > /sys/bus/i2c/drivers/$S/unbind
rmmod $S
modprobe $S
for i in $(seq 20); do
    media-ctl -p 2>/dev/null | grep -q "entity.*: $S " && break
    sleep 0.5
done
media-ctl -p | grep -q "entity.*: $S " || { echo "$S non torna nel grafo"; exit 1; }
echo "$S: $(strings "$KO" | grep -E '^lab=' || echo v2) caricato"

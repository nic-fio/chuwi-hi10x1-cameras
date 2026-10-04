#!/bin/bash
# installa-kernel-prova.sh — mette un kernel di build-tablet-debug.sh dove
# Nic lo avvia: /mnt/vmlinuz-new<suff>, /mnt/initrd-new<suff> e i moduli in
# /lib/modules/<versione>. Non tocca vmlinuz, initrd.img ne' startup.nsh.
#
# Uso:  sudo ./scripts/installa-kernel-prova.sh ~/kernel-prova/base ""
#       sudo ./scripts/installa-kernel-prova.sh ~/kernel-prova/v3   -v3

set -eu

SRC="${1:?cartella con bzImage, modules.tar.zst, versione}"
SUFF="${2-}"
ESP=/mnt

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0 $*"; exit 1; }
[ "$(findmnt -no SOURCE,FSTYPE $ESP)" = "/dev/sda1 vfat" ] ||
    { echo "$ESP non e' la ESP (/dev/sda1 vfat) montata"; exit 1; }
for f in bzImage modules.tar.zst versione; do
    [ -r "$SRC/$f" ] || { echo "manca $SRC/$f"; exit 1; }
done
REL=$(head -1 "$SRC/versione")
case "$REL" in *intelcam-debug*) ;; *) echo "versione strana: $REL"; exit 1 ;; esac

# 1. moduli. /lib e' un link a usr/lib (merged-usr): scompattare su / con
#    tar rischia di sostituire il link con una cartella vera e rompere il
#    sistema. Si scompatta a parte e si copia solo la cartella della versione.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -I zstd -xf "$SRC/modules.tar.zst"
[ -d "$TMP/lib/modules/$REL" ] || { echo "archivio senza lib/modules/$REL"; exit 1; }
rm -rf "/lib/modules/$REL"
cp -a "$TMP/lib/modules/$REL" /lib/modules/
depmod -a "$REL"
echo "moduli: /lib/modules/$REL ($(du -sh "/lib/modules/$REL" | cut -f1))"

# 2. initrd, prima in /tmp per misurarlo: la ESP ha spazio limitato
mkinitramfs -o "$TMP/initrd" "$REL"
need=$(( $(stat -c %s "$TMP/initrd") + $(stat -c %s "$SRC/bzImage") ))
old=0
for f in "$ESP/vmlinuz-new$SUFF" "$ESP/initrd-new$SUFF"; do
    [ -e "$f" ] && old=$((old + $(stat -c %s "$f")))
done
free=$(( $(df -B1 --output=avail $ESP | tail -1) + old ))
[ "$need" -lt $((free - 50*1024*1024)) ] ||
    { echo "ESP: servono $((need>>20)) MB, liberi $((free>>20)) MB: non copio"; exit 1; }

# 3. copia sulla ESP, con nomi nuovi
cp "$SRC/bzImage" "$ESP/vmlinuz-new$SUFF"
cp "$TMP/initrd"  "$ESP/initrd-new$SUFF"
sync
cmp "$SRC/bzImage" "$ESP/vmlinuz-new$SUFF"
cmp "$TMP/initrd"  "$ESP/initrd-new$SUFF"
ls -l "$ESP/vmlinuz-new$SUFF" "$ESP/initrd-new$SUFF"
df -h $ESP | tail -1

cat <<EOF

Installato $REL. Riga per la UEFI Shell (ESC al conto alla rovescia):

  vmlinuz-new$SUFF initrd=initrd-new$SUFF root=UUID=bbf08cd1-b31b-4a2f-8f42-9659c613ae4a rw hostname=CHUWI

Senza "quiet": i messaggi di KASAN al boot vanno visti. Dopo l'avvio:
  sudo ./scripts/prova-serie-v3.sh
EOF

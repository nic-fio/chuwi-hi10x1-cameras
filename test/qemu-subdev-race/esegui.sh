#!/usr/bin/env bash
#
# Test della serie v3 (v4l2-subdev, NULL dereference su unbind) in QEMU.
# Gira sul server di compilazione. Due kernel dallo stesso albero:
#   base = media next 2dcdfb625 senza patch
#   v3   = ramo patch2-v3s (la serie)
# Compilazione a priorita' minima e -j12: il server e' condiviso.
#
#   ./esegui.sh            compila (se serve) e prova tutti e due
#
set -euo pipefail

SRC=/media/INTEL-CAMERA/sorgenti/media
OUT=/media/INTEL-CAMERA/build/qemu
QUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=2dcdfb625
SERIE=patch2-v3s
JOBS=12
N="nice -n 19"

mkdir -p "$OUT"
cd "$SRC"

if [[ -n "$(git status --porcelain)" ]]; then
	echo "ERRORE: l'albero ha modifiche non salvate" >&2
	exit 1
fi
TORNA=$(git rev-parse --abbrev-ref HEAD)

compila() {	# $1 = revisione, $2 = nome
	git checkout -q "$1"
	if [[ ! -f "$OUT/.config" ]]; then
		$N make -s O="$OUT" x86_64_defconfig
		$N ./scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
			kernel/configs/kvm_guest.config "$QUI/race.config" >/dev/null
		$N make -s O="$OUT" olddefconfig
		for o in KASAN VIDEO_VIMC VIDEO_V4L2_SUBDEV_API DEVTMPFS; do
			grep -q "^CONFIG_$o=y" "$OUT/.config" ||
				{ echo "ERRORE: CONFIG_$o non attivo" >&2; exit 1; }
		done
	fi
	$N make -s -j"$JOBS" O="$OUT" bzImage
	cp "$OUT/arch/x86/boot/bzImage" "$OUT/bzImage-$2"
	git rev-parse HEAD > "$OUT/bzImage-$2.rev"
}

initramfs() {
	local d="$OUT/initramfs"
	rm -rf "$d"; mkdir -p "$d"/{dev,proc,sys}
	gcc -O2 -Wall -static -pthread -o "$d/init" "$QUI/race.c"
	(cd "$d" && find . | cpio -o -H newc --quiet) > "$OUT/initramfs.cpio"
}

prova() {	# $1 = nome del kernel
	local log="$OUT/esito-$1.log"
	timeout 900 $N qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G \
		-kernel "$OUT/bzImage-$1" -initrd "$OUT/initramfs.cpio" \
		-append "console=ttyS0 panic=-1 loglevel=4 kasan_multi_shot" \
		-nographic -no-reboot > "$log" 2>&1 || true
	echo "== $1 ($(cat "$OUT/bzImage-$1.rev" | cut -c1-12))"
	grep -E "^RACE-" "$log" || echo "   (nessuna riga RACE: il test non e' arrivato in fondo)"
	echo "   oops/GPF/BUG: $(grep -cE 'Oops:|general protection fault|BUG: ' "$log")"
	echo "   KASAN:        $(grep -c 'KASAN:' "$log")"
	echo "   subdev_open:  $(grep -c 'subdev_open' "$log")"
	echo "   subdev_do_ioctl: $(grep -c 'subdev_do_ioctl' "$log")"
}

trap 'git -C "$SRC" checkout -q "$TORNA"' EXIT

compila "$BASE" base
compila "$SERIE" v3
initramfs
prova base
prova v3

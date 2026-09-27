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
[[ "$TORNA" == HEAD ]] && TORNA=$(git rev-parse HEAD)
rm -f "$OUT/.config"	# niente configurazioni vecchie di run precedenti

compila() {	# $1 = revisione, $2 = nome
	git checkout -q "$1"
	if [[ ! -f "$OUT/.config" ]]; then
		$N make -s O="$OUT" x86_64_defconfig
		$N ./scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
			kernel/configs/kvm_guest.config "$QUI/race.config" >/dev/null
		$N make -s O="$OUT" olddefconfig
		for o in KASAN VIDEO_VIMC VIDEO_V4L2_SUBDEV_API MEDIA_CONTROLLER DEVTMPFS SERIAL_8250_CONSOLE; do
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

# Crash per fase dal log del kernel: fase 0 = prima di RACE-START (avvio).
# Il primo "RIP: 0010:" dopo "Oops:" e' quello vero: oops_end() ristampa i
# registri del primo oops dopo ogni oops successivo.
oops_per_fase() {
	awk '/^RACE-START/{s=1} /^RACE-PHASE/{f++}
	     /Oops:/{o=1; next}
	     o && /RIP: 0010:/{r=$0; sub(/.*RIP: 0010:/,"",r); sub(/[+ ].*/,"",r);
	                       print (s ? f+1 : 0), r; o=0}' "$1"
}

prova() {	# $1 = nome del kernel; ritorna 1 se il run non e' valido
	local log="$OUT/esito-$1.log" valido=1 rc k
	timeout 900 $N qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G \
		-kernel "$OUT/bzImage-$1" -initrd "$OUT/initramfs.cpio" \
		-append "console=ttyS0 panic=-1 loglevel=8 kasan_multi_shot" \
		-nographic -no-reboot > "$log" 2>&1
	rc=$?
	echo "== $1 ($(cut -c1-12 "$OUT/bzImage-$1.rev")), uscita di qemu: $rc"
	grep -E "^RACE-" "$log" | sed 's/^/   /'

	# Un run che non ha esercitato davvero i due percorsi non conta.
	grep -q '^RACE-END' "$log" ||
		{ echo "   NON VALIDO: manca RACE-END (non avviato o appeso)"; valido=0; }
	[[ $(grep -c '^RACE-PHASE' "$log") == 4 ]] ||
		{ echo "   NON VALIDO: non ci sono 4 fasi"; valido=0; }
	grep -qE '^RACE-PHASE.*( cycles=0 | ok=0 | create_err=[1-9]| unbinder_dead=1| unbind_err=[1-9]| bind_err=[1-9])' "$log" &&
		{ echo "   NON VALIDO: fase senza cicli o operazioni riuscite, thread non creati, unbind morto o bind falliti"; valido=0; }

	echo "   Oops:                 $(grep -c 'Oops:' "$log")"
	echo "   KASAN null-ptr-deref: $(grep -c 'KASAN: null-ptr-deref' "$log")"
	echo "   BUG: KASAN (uaf/oob): $(grep -c 'BUG: KASAN' "$log")"
	echo "   WARNING:              $(grep -c 'WARNING:' "$log")"
	echo "   funzione nel RIP di ogni oops, per fase (0 avvio, 1-2 open, 3-4 ioctl):"
	oops_per_fase "$log" | sort | uniq -c | sed 's/^/      /'

	# Secondo controllo, indipendente: thread uccisi visti dal programma
	# contro oops visti dal kernel, fase per fase.
	for k in 1 2 3 4; do
		local ucc oo
		ucc=$(grep '^RACE-PHASE' "$log" | sed -n "${k}p" | sed -n 's/.* killed=\([0-9]*\) .*/\1/p')
		oo=$(oops_per_fase "$log" | awk -v k="$k" '$1==k' | wc -l)
		[[ "$ucc" == "$oo" ]] ||
			echo "   NB fase $k: thread uccisi ${ucc:-?}, oops nel log $oo (non coincidono)"
	done
	return $(( 1 - valido ))
}

trap 'git -C "$SRC" checkout -q "$TORNA"' EXIT

compila "$BASE" base
compila "$SERIE" v3
initramfs
esito=0
prova base || esito=1
oops_per_fase "$OUT/esito-base.log" | grep -qE '^[12] subdev_open' ||
	echo "NB: nessun oops in subdev_open sul kernel base: la 1/2 non e' dimostrata da questo run"
oops_per_fase "$OUT/esito-base.log" | grep -qE '^[34] subdev_do_ioctl' ||
	echo "NB: nessun oops in subdev_do_ioctl sul kernel base: la 2/2 non e' dimostrata da questo run"
prova v3 || esito=1
exit $esito

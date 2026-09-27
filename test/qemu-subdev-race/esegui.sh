#!/usr/bin/env bash
#
# Test della serie v3 (v4l2-subdev, NULL dereference su unbind) in QEMU.
# Gira sul server di compilazione. Tre kernel dallo stesso albero:
#   base = media next 2dcdfb625 senza patch
#   p1   = solo la 1/2 (subdev_open)
#   v3   = la serie intera (1/2 + 2/2, EXT_CTRLS)
#
# Ogni patch si prova da sola:
#   1/2: fasi "open"  su base (deve crashare) contro p1 e v3 (0 crash)
#   2/2: fasi "ioctl" su p1   (deve crashare) contro v3      (0 crash)
# Le fasi ioctl non si provano su base: anche li' l'apertura del nodo passa
# da subdev_open() e crasherebbe prima di arrivare all'ioctl.
#
# Un avvio QEMU per fase: i thread uccisi da un oops non rilasciano mai i
# nodi che tengono aperti, e dopo abbastanza morti vimc non si riattacca.
#
# Compilazione e QEMU a priorita' minima, -j12, 4 vCPU: il server e'
# condiviso con un altro progetto.
#
#   ./esegui.sh
#
set -uo pipefail

SRC=/media/INTEL-CAMERA/sorgenti/media
OUT=/media/INTEL-CAMERA/build/qemu
QUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=2dcdfb625
SERIE=patch2-v3s
JOBS=12
N="nice -n 19"

muori() { echo "ERRORE: $*" >&2; exit 2; }

mkdir -p "$OUT"
cd "$SRC" || muori "manca $SRC"
[[ -z "$(git status --porcelain)" ]] || muori "l'albero ha modifiche non salvate"
TORNA=$(git rev-parse --abbrev-ref HEAD)
[[ "$TORNA" == HEAD ]] && TORNA=$(git rev-parse HEAD)
trap 'git -C "$SRC" checkout -q "$TORNA"' EXIT

compila() {	# $1 = revisione, $2 = nome
	git checkout -q "$1" || muori "checkout di $1"
	if ! cmp -s "$QUI/race.config" "$OUT/.config.fatto"; then
		rm -f "$OUT/.config"
		$N make -s O="$OUT" x86_64_defconfig || muori "defconfig"
		$N ./scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
			kernel/configs/kvm_guest.config "$QUI/race.config" >/dev/null ||
			muori "merge_config"
		$N make -s O="$OUT" olddefconfig || muori "olddefconfig"
		for o in KASAN VIDEO_VIMC VIDEO_V4L2_SUBDEV_API MEDIA_CONTROLLER \
			 DEVTMPFS SERIAL_8250_CONSOLE; do
			grep -q "^CONFIG_$o=y" "$OUT/.config" || muori "CONFIG_$o non attivo"
		done
		cp "$QUI/race.config" "$OUT/.config.fatto"
	fi
	$N make -s -j"$JOBS" O="$OUT" bzImage || muori "compilazione di $2"
	cp "$OUT/arch/x86/boot/bzImage" "$OUT/bzImage-$2"
	git rev-parse HEAD > "$OUT/bzImage-$2.rev"
}

initramfs() {
	local d="$OUT/initramfs"
	rm -rf "$d"; mkdir -p "$d"/{dev,proc,sys}
	gcc -O2 -Wall -static -pthread -o "$d/init" "$QUI/race.c" || muori "race.c"
	(cd "$d" && find . | cpio -o -H newc --quiet) > "$OUT/initramfs.cpio"
}

# Oops per fase: 0 = prima di RACE-START (avvio). Il primo "RIP: 0010:"
# dopo "Oops:" e' quello vero: oops_end() ristampa i registri del primo
# oops dopo ogni oops successivo.
oops_rip() {
	awk '/^RACE-START/{s=1} /^RACE-PHASE/{f++}
	     /Oops:/{o=1; next}
	     o && /RIP: 0010:/{r=$0; sub(/.*RIP: 0010:/,"",r); sub(/[+ ].*/,"",r);
	                       print (s ? f+1 : 0), r; o=0}' "$1"
}

# Stampa l'esito di un avvio. Scrive in $CONTA gli oops nella funzione $3
# durante la fase (per il kernel senza la patch) e in $TOTALE ogni oops,
# report KASAN o WARNING dell'avvio (per il kernel con la patch: deve
# essere zero ovunque, non solo nella funzione corretta). Ritorna 1 se
# l'avvio non e' valido.
avvio() {	# $1 = kernel, $2 = fase (what:period), $3 = funzione attesa
	local log="$OUT/esito-$1-${2/:/-}.log" valido=1 rc riga ucc tutti nella tot
	timeout 600 $N qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G \
		-kernel "$OUT/bzImage-$1" -initrd "$OUT/initramfs.cpio" \
		-append "console=ttyS0 panic=-1 loglevel=8 kasan_multi_shot race.phases=$2" \
		-nographic -no-reboot > "$log" 2>&1
	rc=$?
	riga=$(grep '^RACE-PHASE' "$log" | tr -d '\r')	# la console seriale usa \r\n
	echo "== $1 $2 ($(cut -c1-12 "$OUT/bzImage-$1.rev")), uscita di qemu: $rc"
	grep '^RACE-ERROR' "$log" | sed 's/^/   /'
	echo "   ${riga:-(nessuna riga RACE-PHASE)}"

	grep -q "Linux version .*-g$(cut -c1-12 "$OUT/bzImage-$1.rev")" "$log" ||
		{ echo "   NON VALIDO: il kernel avviato non e' $1"; valido=0; }
	grep -q '^RACE-END' "$log" ||
		{ echo "   NON VALIDO: manca RACE-END (non avviato o appeso)"; valido=0; }
	[[ $(grep -c '^RACE-PHASE' "$log") == 1 ]] ||
		{ echo "   NON VALIDO: non c'e' esattamente una fase"; valido=0; }
	[[ "$riga" =~ ^RACE-PHASE\ what=(open|ioctl)\ period=[0-9]+ms\ .*\ bind_errno=[0-9]+$ ]] ||
		{ echo "   NON VALIDO: riga RACE-PHASE incompleta o spezzata"; valido=0; }
	if [[ "$riga" =~ \ cycles=0\ |\ ok=0\ |\ enodev=0\ |\ create_err=[1-9]|\ unbinder_dead=1|\ unbind_err=[1-9]|\ bind_err=[1-9] ]]; then
		echo "   NON VALIDO: senza cicli, operazioni riuscite o corse con l'unbind (enodev), thread non creati, unbind morto o bind falliti"
		valido=0
	fi

	tutti=$(oops_rip "$log")
	tot=$(grep -c -E 'Oops:|BUG: KASAN|WARNING:|kernel BUG at|BUG: unable' "$log")
	nella=$(awk -v f="$3" '$1 == 1 && $2 ~ "^" f' <<<"$tutti" | wc -l)
	ucc=$(sed -n 's/.* killed=\([0-9]*\) .*/\1/p' <<<"$riga")
	echo "   Oops $(grep -c 'Oops:' "$log"), KASAN null-ptr-deref $(grep -c 'KASAN: null-ptr-deref' "$log"), BUG: KASAN $(grep -c 'BUG: KASAN' "$log"), WARNING $(grep -c 'WARNING:' "$log"); in $3: $nella"
	[[ -n "$tutti" ]] && sort <<<"$tutti" | uniq -c | sed 's/^/      /'
	[[ "$ucc" == "$(grep -c . <<<"$(awk '$1 == 1' <<<"$tutti")")" ]] ||
		echo "   NB: thread uccisi ${ucc:-?} diversi dagli oops della fase"

	CONTA=$nella
	TOTALE=$tot
	return $(( 1 - valido ))
}

compila "$BASE" base
compila "$SERIE~1" p1
compila "$SERIE" v3
initramfs

esito=0
declare -A OOPS TOT
for caso in "base open:1 subdev_open" "base open:30 subdev_open" \
	    "p1 open:1 subdev_open" "p1 open:30 subdev_open" \
	    "v3 open:1 subdev_open" "v3 open:30 subdev_open" \
	    "p1 ioctl:1 subdev_do_ioctl" "p1 ioctl:30 subdev_do_ioctl" \
	    "v3 ioctl:1 subdev_do_ioctl" "v3 ioctl:30 subdev_do_ioctl"; do
	set -- $caso
	CONTA=0 TOTALE=0
	if avvio "$1" "$2" "$3"; then
		OOPS["$1 $2"]=$CONTA
		TOT["$1 $2"]=$TOTALE
	else
		OOPS["$1 $2"]=NV
		TOT["$1 $2"]=NV
		esito=1
	fi
done

echo
echo "== Riepilogo: oops nella funzione della patch / tutti gli oops, KASAN e WARNING (NV = avvio non valido)"
for k in "base open:1" "base open:30" "p1 open:1" "p1 open:30" "v3 open:1" \
	 "v3 open:30" "p1 ioctl:1" "p1 ioctl:30" "v3 ioctl:1" "v3 ioctl:30"; do
	printf '   %-14s %s / %s\n' "$k" "${OOPS[$k]}" "${TOT[$k]}"
done

# Verdetto per una patch: $1 kernel senza, $2 kernel con, $3 fase, $4 nome.
# Senza: servono avvii validi e almeno un oops nella funzione della patch.
# Con: servono avvii validi e zero oops, KASAN e WARNING di qualunque tipo.
verdetto() {
	local s1=${OOPS["$1 $3:1"]} s2=${OOPS["$1 $3:30"]}
	local c1=${TOT["$2 $3:1"]} c2=${TOT["$2 $3:30"]}
	if [[ $s1 == NV || $s2 == NV || $c1 == NV || $c2 == NV ]]; then
		echo "$4: NESSUNA CONCLUSIONE, ci sono avvii non validi"
	elif (( c1 + c2 > 0 )); then
		echo "$4: ATTENZIONE, il kernel con la patch ($2) ha oops, KASAN o WARNING nelle fasi $3"
	elif (( s1 + s2 == 0 )); then
		echo "$4: NESSUNA CONCLUSIONE, nemmeno il kernel senza ($1) crasha: il test non ha centrato la finestra"
	else
		echo "$4: DIMOSTRATA ($1 crasha $((s1 + s2)) volte nella funzione della patch, $2 nessun oops, KASAN o WARNING)"
	fi
}
verdetto base p1 open "1/2"
verdetto p1 v3 ioctl "2/2"
[[ ${TOT["v3 open:1"]} == 0 && ${TOT["v3 open:30"]} == 0 ]] ||
	echo "   attenzione: la serie intera non ha fasi open valide e pulite"
exit $esito

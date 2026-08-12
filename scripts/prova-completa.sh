#!/bin/bash
# prova-completa.sh — rifa' in un colpo solo tutte le verifiche su hardware.
#
# Progetto INTEL-CAMERA. Esiste per due motivi:
#
#   1. dopo ogni modifica ai driver bisogna poter dire "e' ancora tutto vero"
#      senza rifare a mano venti comandi e senza dimenticarne uno;
#   2. quando un revisore chiede "come l'hai provato", la risposta e' questo
#      file piu' il suo output, non un ricordo.
#
# Ogni verifica confronta un numero misurato con uno previsto e stampa OK o
# KO. Non "sembra funzionare": o il numero torna o non torna.
#
# Uso:  sudo ./scripts/prova-completa.sh [directory-di-uscita]
#
# Richiede: build-6.12/carica.sh gia' eseguito, oppure lo esegue lui.

set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$PROJECT_DIR/data/prova-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }

PASS=0
FAIL=0
ND=0

ok()   { printf '  [OK] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [KO] %s\n' "$1"; FAIL=$((FAIL+1)); }
# Terzo esito, e serve davvero: una misura che dipende dalla scena non e' un
# difetto quando la scena non c'e'. Un [KO] al buio sarebbe una bugia.
nd()   { printf '  [--] %s\n' "$1"; ND=$((ND+1)); }
head_() { printf '\n===== %s\n' "$1"; }

# Confronta due numeri con una tolleranza percentuale. Serve dappertutto qui:
# nessuna di queste misure e' esatta, ma tutte hanno un margine oltre il quale
# smettono di essere rumore e diventano un difetto.
close() { # atteso misurato tolleranza% etichetta
    python3 - "$@" <<'PY'
import sys
exp, got, tol, label = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
d = abs(got - exp) / exp * 100 if exp else 999
print(f"{'OK' if d <= tol else 'KO'}|{label}: atteso {exp:g}, misurato {got:g}, scarto {d:.2f}% (tolleranza {tol:g}%)")
PY
}

check_close() {
    local r; r=$(close "$@")
    case "$r" in OK\|*) ok "${r#OK|}" ;; *) ko "${r#KO|}" ;; esac
}

# --------------------------------------------------------------- ambiente
head_ "AMBIENTE"
uname -a | tee "$OUT/00-kernel.txt"
for t in v4l2-ctl media-ctl v4l2-compliance i2cget; do
    command -v "$t" >/dev/null && ok "$t presente" || { ko "$t assente"; }
done

# ------------------------------------------------------------------ carica
head_ "CARICAMENTO DEI MODULI"
if [ ! -L /sys/bus/i2c/devices/i2c-GCTI5035:00/driver ]; then
    "$PROJECT_DIR/build-6.12/carica.sh" >"$OUT/01-carica.txt" 2>&1
fi
for d in GCTI5035 GCTI8034; do
    if [ -L "/sys/bus/i2c/devices/i2c-$d:00/driver" ]; then
        ok "$d agganciato a $(basename "$(readlink -f "/sys/bus/i2c/devices/i2c-$d:00/driver")")"
    else
        ko "$d senza driver"
    fi
done
dmesg | grep -c "Connected 2 cameras" >/dev/null && ok "ipu-bridge ha collegato le camere"

# Da qui in poi il buffer del kernel copre TUTTA la prova. Azzerarlo piu'
# avanti — com'era prima del 2026-08-12 — cancellava cattura, guadagno e
# compliance prima di guardarli, e il controllo finale diceva "nessun
# BUG/WARNING" avendo visto solo i cicli di bind/unbind. E' cosi' che la
# WARNING di lockdep in ipu6_isys_video_set_streaming era passata inosservata.
dmesg -C

# ------------------------------------------------------------- chip ID I2C
# Il probe li ha gia' letti, ma leggerli da userspace prova che il bus e'
# davvero vivo e non che il driver si e' limitato a non lamentarsi.
head_ "CHIP ID SUL BUS"
modprobe i2c-dev 2>/dev/null
# Il numero di bus NON e' stabile: dipende da quanti controller il kernel
# enumera prima: sul kernel Debian i sensori stanno su i2c-3 e i2c-2, su
# quello di debug su i2c-2 e i2c-1. Va ricavato da sysfs, non cablato.
for spec in "GCTI5035:0x3f:0x50:0x35" "GCTI8034:0x37:0x80:0x44"; do
    IFS=: read -r name addr hi lo <<<"$spec"
    dev=$(readlink -f "/sys/bus/i2c/devices/i2c-$name:00" 2>/dev/null)
    bus=$(basename "$(dirname "$dev")" 2>/dev/null)
    bus=${bus#i2c-}
    if [ -z "$dev" ] || ! [ "$bus" -ge 0 ] 2>/dev/null; then
        ko "$name: nessun bus I2C in sysfs"
        continue
    fi
    echo on > "/sys/bus/i2c/devices/i2c-$name:00/power/control" 2>/dev/null
    sleep 1
    r1=$(i2cget -f -y "$bus" "$addr" 0xf0 2>/dev/null)
    r2=$(i2cget -f -y "$bus" "$addr" 0xf1 2>/dev/null)
    echo auto > "/sys/bus/i2c/devices/i2c-$name:00/power/control" 2>/dev/null
    if [ "$r1" = "$hi" ] && [ "$r2" = "$lo" ]; then
        ok "$name risponde $r1 $r2"
    else
        ko "$name: atteso $hi $lo, letto '$r1' '$r2'"
    fi
done

# ------------------------------------------------------------------ catture
# I numeri attesi vengono dai driver, non da qui: se qualcuno cambia una
# costante e si scorda di aggiornare la realta', questo se ne accorge.
head_ "CATTURA E TEMPI"
declare -A NODE SUBDEV
for s in gc5035 gc8034; do
    line=$("$PROJECT_DIR/scripts/cattura.sh" "$s" 1 /dev/null 2>&1 | head -1)
    NODE[$s]=$(echo "$line" | grep -oE "/dev/video[0-9]+")
    ent=$(echo "$line" | sed 's/ ->.*//')
    SUBDEV[$s]=$(media-ctl -p 2>/dev/null | awk -v e="$ent" '
        $0 ~ "entity [0-9]+: "e" " {f=1} f && /device node name/ {print $NF; exit}')
    [ -n "${NODE[$s]}" ] && ok "$s -> ${NODE[$s]} (${SUBDEV[$s]})" || ko "$s: pipeline non configurabile"
done

for spec in "gc5035:2920:2008:grbg:2592:1944" "gc8034:4272:2496:rggb:3264:2448"; do
    IFS=: read -r s hts vts pat w h <<<"$spec"
    [ -n "${NODE[$s]:-}" ] || continue
    pr=$(v4l2-ctl -d "${SUBDEV[$s]}" --list-ctrls 2>/dev/null |
         sed -n 's/.*pixel_rate.*value=\([0-9]*\).*/\1/p')
    lf=$(v4l2-ctl -d "${SUBDEV[$s]}" --list-ctrls 2>/dev/null |
         sed -n 's/.*link_frequency.*value=0 (\([0-9]*\).*/\1/p')
    fps_att=$(python3 -c "print($pr/($hts*$vts))")
    fps_mis=$(timeout 120 v4l2-ctl -d "${NODE[$s]}" --stream-mmap --stream-count=200 2>&1 |
              grep -oE "[0-9]+\.[0-9]+ fps" | tail -1 | cut -d' ' -f1)
    echo "$s: link_freq=$lf pixel_rate=$pr fps_atteso=$fps_att fps_misurato=$fps_mis" \
        >> "$OUT/02-tempi.txt"
    if [ -n "$fps_mis" ]; then
        check_close "$fps_att" "$fps_mis" 1 "$s: il frame rate previsto dal driver e' quello reale"
    else
        ko "$s: nessun frame catturato"
    fi

    "$PROJECT_DIR/scripts/cattura.sh" "$s" 3 "$OUT/$s.raw" >/dev/null 2>&1
    "$PROJECT_DIR/scripts/raw-to-png.py" "$OUT/$s.raw" "$w" "$h" "$pat" \
        "$OUT/$s.png" --frame 2 >/dev/null 2>&1 &&
        ok "$s: immagine scritta in $s.png" || ko "$s: conversione fallita"
done

# ------------------------------------------------------------------ guadagno
# Il segnale e' la media meno il pedestal di 64. Se la tabella di guadagno e'
# stata trascritta male, il rapporto non torna: e' il controllo che l'ha
# validata la prima volta.
head_ "GUADAGNO ANALOGICO"
# Restituisce due numeri: la media e la percentuale di pixel al fondo scala.
# La percentuale non e' un di piu': senza, questa misura mente. Vedi il
# controllo di saturazione piu' sotto.
misura_media() { # nodo file -> "media clip%"
    timeout 60 v4l2-ctl -d "$1" --stream-mmap --stream-count=2 --stream-to="$2" >/dev/null 2>&1
    python3 - "$2" <<'PY'
import array, sys
d = open(sys.argv[1], 'rb').read()
a = array.array('H'); a.frombytes(d[len(d)//2:len(d)//2*2])
sub = a[::17]
if not sub:
    print("0 0")
else:
    clip = sum(1 for v in sub if v >= 1020)     # 1023 e' il fondo scala a 10 bit
    print(f"{sum(sub)/len(sub)} {100*clip/len(sub)}")
PY
}
for spec in "gc5035:256:4096" "gc8034:64:490"; do
    IFS=: read -r s gmin gmax <<<"$spec"
    [ -n "${NODE[$s]:-}" ] || continue
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    read -r m1 c1 <<<"$(misura_media "${NODE[$s]}" "$OUT/.g1.raw")"
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmax 2>/dev/null
    read -r m2 c2 <<<"$(misura_media "${NODE[$s]}" "$OUT/.g2.raw")"
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    r=$(python3 -c "
s1=max($m1-64, 0.1); s2=max($m2-64, 0.1)
print(f'{s2/s1:.2f} {$gmax/$gmin:.2f}')")
    read -r got want <<<"$r"
    echo "$s: media ${m1} (clip ${c1}%) -> ${m2} (clip ${c2}%), rapporto $got, atteso $want" \
        >> "$OUT/03-guadagno.txt"
    # Al buio il segnale resta sul piedistallo di black level (64) e il
    # rapporto e' fra due rumori: 4 LSB al guadagno massimo vogliono dire
    # scena nera, non guadagno rotto. Serve una luce accesa davanti al
    # sensore, altrimenti questa misura non e' una misura.
    if [ "$(python3 -c "print(int($m2 - 64 < 4))")" = 1 ]; then
        # Niente printf sui decimali: la locale italiana vuole la virgola e
        # printf rifiuta "998.4" con "numero non valido". Si taglia e basta.
        nd "$s: scena troppo scura per misurare il guadagno (segnale ${m2%%.*} sul piedistallo 64) — rifare con una luce"
        continue
    fi
    # E il caso opposto, che il 2026-08-12 ha prodotto due falsi allarmi di
    # fila. Con troppa luce il fotogramma a guadagno massimo taglia sul fondo
    # scala (1023 a 10 bit): il segnale che manca in cima schiaccia la media e
    # il rapporto crolla, senza che i driver c'entrino niente.
    #
    # La soglia NON puo' essere sulla media, ed e' l'errore che avevo fatto la
    # prima volta. Una scena con zone luminose taglia il 15% dei pixel avendo
    # ancora una media di 421 su 1023: nessuna soglia sulla media la vede.
    # Misurato quel giorno sul gc5035, a 16x: media 421, massimo 1023,
    # 15.56% dei pixel al fondo scala, rapporto 10.7 invece di 16. A 1x lo
    # stesso fotogramma aveva massimo 366 e zero pixel tagliati.
    #
    # Si guarda quindi quanti pixel sono al fondo scala. Oltre il 2% il
    # rapporto non e' piu' una misura del guadagno, ed e' onesto dirlo invece
    # di stampare un [KO] che fa cercare un difetto che non c'e'.
    if [ "$(python3 -c "print(int($c2 > 2))")" = 1 ]; then
        nd "$s: scena troppo luminosa, a guadagno massimo ${c2%%.*}% dei pixel e' tagliato sul fondo scala — rifare con meno luce"
        continue
    fi
    # Tolleranza larga: la scena non e' controllata.
    check_close "$want" "$got" 25 "$s: il guadagno misurato segue quello chiesto"
done
rm -f "$OUT/.g1.raw" "$OUT/.g2.raw"

# -------------------------------------------------------------- compliance
head_ "V4L2-COMPLIANCE"
for s in gc5035 gc8034; do
    [ -n "${SUBDEV[$s]:-}" ] || continue
    n=$(timeout 300 v4l2-compliance -d "${SUBDEV[$s]}" 2>&1 | tee "$OUT/04-compliance-$s.txt" |
        sed -n 's/.*Succeeded: \([0-9]*\), Failed: \([0-9]*\).*/\1 \2/p')
    read -r good bad <<<"$n"
    # 1 fallimento e' quello degli eventi sui controlli, condiviso con tutti i
    # driver di sensore mainline recenti. Due sarebbero una regressione.
    if [ "${bad:-9}" -le 1 ]; then
        ok "$s: compliance $good ok, $bad fallito (atteso: al massimo 1)"
    else
        ko "$s: compliance $good ok, $bad falliti"
    fi
done

# ------------------------------------------------------------- bind/unbind
head_ "BIND E UNBIND, 10 CICLI"
for s in gc5035 gc8034; do
    dev=$(basename "$(ls -d /sys/bus/i2c/drivers/$s/i2c-GCTI* 2>/dev/null | head -1)" 2>/dev/null)
    [ -n "$dev" ] || { ko "$s: non agganciato, salto"; continue; }
    for _ in $(seq 1 10); do
        echo "$dev" > "/sys/bus/i2c/drivers/$s/unbind" 2>/dev/null
        echo "$dev" > "/sys/bus/i2c/drivers/$s/bind" 2>/dev/null
    done
    if [ -L "/sys/bus/i2c/devices/$dev/driver" ]; then
        ok "$s: 10 cicli, ancora agganciato"
    else
        ko "$s: non si riaggancia dopo i cicli"
    fi
done
# Il conteggio copre tutta la prova, non solo i cicli qui sopra. KASAN, UBSAN
# e lockdep stampano solo sul kernel di debug: sul kernel Debian queste righe
# non escono mai, e non uscire non vuol dire che il difetto non ci sia.
n=$(dmesg | grep -cE "BUG:|Oops|WARNING:|refcount_t|use-after-free|KASAN|UBSAN|lockdep|possible recursive|INFO: task")
[ "$n" -eq 0 ] && ok "nessun BUG/WARNING nel kernel" || ko "$n messaggi di BUG/WARNING, vedi 05-dmesg.txt"
dmesg > "$OUT/05-dmesg.txt"

# Lockdep si spegne DA SOLO al primo errore che trova, e resta spento fino al
# riavvio. Da quel momento "nessun BUG" non vuol dire piu' niente sul locking:
# nessuno lo sta piu' controllando. Senza questa riga il 2026-08-12 la prova
# avrebbe dichiarato tutto a posto con lockdep gia' morto da mezz'ora.
if [ -r /proc/lockdep_stats ]; then
    dl=$(awk '/debug_locks:/{print $2}' /proc/lockdep_stats)
    if [ "$dl" = "1" ]; then
        ok "lockdep e' ancora attivo: il verdetto sul locking vale"
    else
        ko "lockdep e' SPENTO (debug_locks=$dl): il verdetto sul locking non vale, riavviare"
    fi
fi

# NOTA: unbind DURANTE lo streaming non e' qui apposta, e dal 2026-08-12 si sa
# perche' deve restarne fuori. Con la patch A1 applicata non fa piu' oopsare il
# kernel — la macchina resta in piedi e nessun processo finisce in D — ma su un
# kernel con KASAN produce un use-after-free in __media_pipeline_stop(): la
# lista dei pad della pipeline referenzia ancora un media_pad del sub-device
# che l'unbind ha gia' liberato. E' C1 di docs/10, di mainline, e la patch A1
# non lo copre. Si prova a mano, non dentro il giro automatico.
#
# NOTA 2: i cicli qui sopra possono far oopsare il kernel lo stesso, senza che
# lo si chieda, per A2 — udev lancia v4l_id sul nodo che compare e sparisce e
# lo apre proprio dentro la finestra di subdev_open(). E' un difetto di
# mainline, non nostro, e non e' fatale: si vede come [KO] qui sotto finche'
# 'patches/wip/subdev-fix/' non e' applicata.

# ------------------------------------------------------------------ verdetto
head_ "VERDETTO"
printf '  %d verifiche superate, %d fallite' "$PASS" "$FAIL"
[ "$ND" -eq 0 ] && echo || printf ', %d non misurabili\n' "$ND"
echo "  output in $OUT"
[ "$FAIL" -eq 0 ] || exit 1

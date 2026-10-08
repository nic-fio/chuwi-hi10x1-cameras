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
    modprobe -a gc5035 gc8034 >"$OUT/01-carica.txt" 2>&1
fi
for d in GCTI5035 GCTI8034; do
    if [ -L "/sys/bus/i2c/devices/i2c-$d:00/driver" ]; then
        ok "$d agganciato a $(basename "$(readlink -f "/sys/bus/i2c/devices/i2c-$d:00/driver")")"
    else
        ko "$d senza driver"
    fi
done
# Dal grafo media e non dal «Connected 2 cameras» del boot: il dmesg -C qui
# sotto lo cancella, e dalla seconda corsa la verifica spariva senza KO.
for s in gc5035 gc8034; do
    csi=$(media-ctl -p 2>/dev/null | awk -v s="$s" '
        /^- entity/ { on = ($4 == s) }
        on && /-> "Intel IPU6 CSI2 [0-9]+":0 \[ENABLED/ { sub(/.*-> "/, ""); sub(/".*/, ""); print; exit }')
    [ -n "$csi" ] && ok "ipu-bridge ha collegato $s a $csi" || ko "$s non collegato a nessun CSI2 dell'IPU6"
done

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
    # Controlli ai default. v4l2-compliance li lascia sull'ultimo valore
    # provato, test pattern acceso compreso: lanciata a mano prima della prova
    # il 2026-10-08, il gc5035 ha dato lo stesso fotogramma a 1x e a 15,6x.
    # Dentro la prova non si vedeva perche' i cicli di bind la seguono.
    [ -n "${SUBDEV[$s]}" ] || continue
    def=$(v4l2-ctl -d "${SUBDEV[$s]}" --list-ctrls 2>/dev/null | awk '
        /flags=.*(read-only|inactive)/ { next }
        / default=/ { for (i = 1; i <= NF; i++) if ($i ~ /^default=/) { sub(/default=/, "", $i); printf "%s%s=%s", sep, $1, $i; sep = "," } }')
    [ -n "$def" ] && v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl="$def" 2>/dev/null
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

# Frame rate a VBLANK lontano dal default. Per il gc8034 controlla le 36 righe
# di offset del registro di blanking: con un errore di d righe il rapporto
# fra i due frame rate si sposta di circa d/2496 - d/4496 (0,07% per d = 4),
# poco sopra la precisione della misura. Si salva il d ricavato.
for spec in "gc5035:2920:1944:64" "gc8034:4272:2448:48"; do
    IFS=: read -r s hts h vbdef <<<"$spec"
    [ -n "${NODE[$s]:-}" ] || continue
    pr=$(v4l2-ctl -d "${SUBDEV[$s]}" --list-ctrls 2>/dev/null |
         sed -n 's/.*pixel_rate.*value=\([0-9]*\).*/\1/p')
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=vertical_blanking=2000 2>/dev/null
    f2=$(timeout 120 v4l2-ctl -d "${NODE[$s]}" --stream-mmap --stream-count=150 2>&1 |
         grep -oE "[0-9]+\.[0-9]+ fps" | tail -1 | cut -d' ' -f1)
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=vertical_blanking=$vbdef 2>/dev/null
    [ -n "$f2" ] || { ko "$s: nessun frame a VBLANK 2000"; continue; }
    att=$(python3 -c "print($pr/($hts*($h+2000)))")
    d=$(python3 -c "print(round($pr/($hts*$f2) - ($h+2000), 1))")
    echo "$s: VBLANK 2000 fps_atteso=$att fps_misurato=$f2 righe_in_piu=$d" >> "$OUT/02-tempi.txt"
    check_close "$att" "$f2" 0.2 "$s: il frame rate segue VBLANK (righe in piu' ricavate: $d)"
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
# Da driver-v1 ANALOGUE_GAIN e' l'indice del gradino analogico: il rapporto
# atteso e' quello fra l'ultimo e il primo gradino delle tabelle dei driver.
for spec in "gc5035:0:16:15.60" "gc8034:0:6:7.66"; do
    IFS=: read -r s gmin gmax gratio <<<"$spec"
    [ -n "${NODE[$s]:-}" ] || continue
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    read -r m1 c1 <<<"$(misura_media "${NODE[$s]}" "$OUT/.g1.raw")"
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmax 2>/dev/null
    read -r m2 c2 <<<"$(misura_media "${NODE[$s]}" "$OUT/.g2.raw")"
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=analogue_gain=$gmin 2>/dev/null
    # Il rapporto si fa solo sui pixel non saturi nel fotogramma a guadagno
    # massimo, gli stessi nei due fotogrammi. Il 2026-10-08 una luce
    # nell'inquadratura, gia' satura a 1x, portava col suo 0,5% di pixel il 37%
    # del segnale medio (9 LSB): a 16x tagliata a 1023, rapporto 9.76 invece
    # di 15.6, e il fotogramma a 1x con 15.6x ideale e taglio ne prevede 9.87.
    # La soglia sui pixel saturi (2%) non l'aveva vista: conta il segnale che
    # portano, non quanti sono. Con la maschera conta solo quanti ne restano.
    r=$(python3 - "$OUT/.g1.raw" "$OUT/.g2.raw" "$gratio" <<'PY'
import array, sys
def fot(f):
    d = open(f, 'rb').read()
    a = array.array('H'); a.frombytes(d[len(d)//2:len(d)//2*2])
    return a[::17]
a1, a2 = fot(sys.argv[1]), fot(sys.argv[2])
m = [(x, y) for x, y in zip(a1, a2) if y < 1020]
s1 = max(sum(x for x, _ in m)/len(m) - 64, 0.1)
s2 = max(sum(y for _, y in m)/len(m) - 64, 0.1)
print(f"{s2/s1:.2f} {float(sys.argv[3]):.2f} {100*len(m)/len(a2):.1f}")
PY
)
    read -r got want usati <<<"$r"
    echo "$s: media ${m1} (clip ${c1}%) -> ${m2} (clip ${c2}%), rapporto sui pixel non saturi ($usati%) $got, atteso $want" \
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
    # E il caso opposto. Con troppa luce il fotogramma a guadagno massimo
    # taglia sul fondo scala (1023 a 10 bit): quei pixel sono esclusi dal
    # rapporto, ma se ne restano pochi la misura vale per un angolo della
    # scena e non per il sensore. Il 2026-08-12, a 16x, il 15.56% era tagliato.
    if [ "$(python3 -c "print(int($usati < 50))")" = 1 ]; then
        nd "$s: scena troppo luminosa, a guadagno massimo resta non saturo solo il ${usati%%.*}% dei pixel — rifare con meno luce"
        continue
    fi
    # Tolleranza larga: la scena non e' controllata.
    check_close "$want" "$got" 25 "$s: il guadagno misurato segue quello chiesto"
done
rm -f "$OUT/.g1.raw" "$OUT/.g2.raw"

# ------------------------------------------------------- registri a 16 bit
# Esposizione e frame length si scrivono a 16 bit con autoincremento: in
# lettura e' provato (chip ID), in scrittura no. Si impostano i controlli
# durante uno stream e si rileggono i due byte via I2C.
#
# Durante, non col sensore solo acceso: i registri sono a doppio buffer. Il
# 2026-10-08, a sensore acceso senza stream, la rilettura dava 0 prima di
# qualsiasi stream e dopo uno stream il valore della scrittura PRECEDENTE
# (1112 -> 1111, 1109 -> 1112), mentre la traccia regmap mostrava il driver
# scrivere i due byte giusti. In streaming il valore e' esatto.
head_ "SCRITTURE A 16 BIT"
for spec in "gc5035:GCTI5035:0x3f:0x03:0x41:0:1944" "gc8034:GCTI8034:0x37:0x03:0x07:36:2448"; do
    IFS=: read -r s name addr rexp rvb vboff h <<<"$spec"
    [ -n "${SUBDEV[$s]:-}" ] || continue
    dev=$(readlink -f "/sys/bus/i2c/devices/i2c-$name:00"); bus=$(basename "$(dirname "$dev")"); bus=${bus#i2c-}
    # 250 fotogrammi: 9-10 s, abbastanza per finire le letture a stream vivo
    timeout 60 v4l2-ctl -d "${NODE[$s]}" --stream-mmap --stream-count=250 >/dev/null 2>&1 &
    sleep 3
    # prima VBLANK, che allarga il range dell'esposizione, poi l'esposizione
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=vertical_blanking=300 2>/dev/null
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=exposure=1110 2>/dev/null
    sleep 0.5    # qualche fotogramma, perche' i valori si aggancino
    e=$(( $(i2cget -f -y "$bus" "$addr" "$rexp") << 8 | $(i2cget -f -y "$bus" "$addr" $(printf 0x%02x $((rexp+1)))) ))
    b=$(( $(i2cget -f -y "$bus" "$addr" "$rvb") << 8 | $(i2cget -f -y "$bus" "$addr" $(printf 0x%02x $((rvb+1)))) ))
    if [ "$s" = gc5035 ]; then vb_att=$(( h + 300 )); else vb_att=$(( 300 - vboff )); fi  # gc5035: frame length; gc8034: VTS - altezza - 36
    echo "$s: esposizione letta $e (attesa 1110), frame/blanking letto $b (atteso $vb_att), altezza $h" >> "$OUT/06-registri.txt"
    [ "$e" -eq 1110 ] && ok "$s: esposizione a 16 bit riletta 1110" || ko "$s: esposizione riletta $e invece di 1110"
    [ "$b" -eq "$vb_att" ] && ok "$s: VBLANK a 16 bit riletto $b" || ko "$s: VBLANK riletto $b invece di $vb_att"
    wait
    v4l2-ctl -d "${SUBDEV[$s]}" --set-ctrl=vertical_blanking=$([ $s = gc5035 ] && echo 64 || echo 48) 2>/dev/null
done

# ------------------------------------------------------------- geometria
# Finestra letta e crop sono scritti dal driver con nomi e costanti (le stesse
# delle selezioni), a 16 bit anche in pagina 1. Si rileggono a stream vivo,
# come le scritture a 16 bit qui sopra: i registri sono a doppio buffer.
head_ "GEOMETRIA"
r16p() { # bus indirizzo pagina registro
    i2cset -f -y "$1" "$2" 0xfe "$3"
    echo $(( $(i2cget -f -y "$1" "$2" "$4") << 8 | $(i2cget -f -y "$1" "$2" $(printf 0x%02x $(($4+1)))) ))
}
# sensore:HID:indirizzo:attesi "pagina/registro=valore" separati da virgole
for spec in "gc5035:GCTI5035:0x3f:0/0x09=4,0/0x0b=3,0/0x0d=1960,0/0x0f=2608,1/0x91=8,1/0x93=8,1/0x95=1944,1/0x97=2592,0/0x05=730" \
            "gc8034:GCTI8034:0x37:0/0x0b=4,0/0x0d=2464,0/0x0f=3284,0/0x95=2448,0/0x97=3264,0/0x05=534"; do
    IFS=: read -r s name addr regs <<<"$spec"
    [ -n "${NODE[$s]:-}" ] || continue
    dev=$(readlink -f "/sys/bus/i2c/devices/i2c-$name:00"); bus=$(basename "$(dirname "$dev")"); bus=${bus#i2c-}
    timeout 60 v4l2-ctl -d "${NODE[$s]}" --stream-mmap --stream-count=150 >/dev/null 2>&1 &
    sleep 3
    bad=""
    for r in ${regs//,/ }; do
        pg=${r%%/*}; rest=${r#*/}; reg=${rest%%=*}; want=${rest#*=}
        got=$(r16p "$bus" "$addr" "$pg" "$reg")
        echo "$s: pagina $pg $reg letto $got atteso $want" >> "$OUT/08-geometria.txt"
        [ "$got" -eq "$want" ] || bad="$bad $pg/$reg=$got"
    done
    i2cset -f -y "$bus" "$addr" 0xfe 0
    wait
    [ -z "$bad" ] && ok "$s: finestra, crop e lunghezza di riga come le costanti del driver" ||
        ko "$s: registri di geometria diversi dall'atteso:$bad"
done

# ---------------------------------------------------------- test pattern
# Il gc5035 genera una mira a mosaico (barre, sfumature, griglie). La mira e'
# deterministica: due fotogrammi consecutivi sono uguali pixel per pixel,
# mentre una scena vera ha sempre rumore. Non dipende dalla luce.
head_ "TEST PATTERN (gc5035)"
if [ -n "${NODE[gc5035]:-}" ]; then
    v4l2-ctl -d "${SUBDEV[gc5035]}" --set-ctrl=test_pattern=1 2>/dev/null
    timeout 60 v4l2-ctl -d "${NODE[gc5035]}" --stream-mmap --stream-count=3 --stream-to="$OUT/.tp.raw" >/dev/null 2>&1
    v4l2-ctl -d "${SUBDEV[gc5035]}" --set-ctrl=test_pattern=0 2>/dev/null
    r=$(python3 - "$OUT/.tp.raw" <<'PY'
import array, sys
W, H = 2592, 1944
d = open(sys.argv[1], 'rb').read(); n = W * H * 2
f1 = array.array('H'); f1.frombytes(d[n:2*n])
f2 = array.array('H'); f2.frombytes(d[2*n:3*n])
s1, s2 = f1[::7], f2[::7]
same = sum(x == y for x, y in zip(s1, s2)) / len(s1)
print(f"{100*same:.1f} {min(s2)} {max(s2)}")
PY
)
    read -r same lo hi <<<"$r"
    echo "gc5035 test pattern: pixel uguali fra due fotogrammi $same%, livelli da $lo a $hi" >> "$OUT/09-test-pattern.txt"
    "$PROJECT_DIR/scripts/raw-to-png.py" "$OUT/.tp.raw" 2592 1944 grbg "$OUT/gc5035-test-pattern.png" --frame 2 >/dev/null 2>&1
    rm -f "$OUT/.tp.raw"
    if [ "$(python3 -c "print(int(${same:-0} > 99 and ${hi:-0} > 900))")" = 1 ]; then
        ok "gc5035: test pattern attivo ($same% dei pixel identici fra due fotogrammi), immagine in gc5035-test-pattern.png"
    else
        ko "gc5035: il test pattern non si vede ($same% dei pixel identici, livelli $lo-$hi)"
    fi
fi

# ------------------------------------------------- esposizione dispari gc5035
# Il driver vendor arrotonda l'esposizione al pari. A valori piccoli una riga
# pesa: fra 8 e 9 righe il segnale deve crescere del 12,5% se il sensore
# accetta i dispari, restare uguale se li arrotonda.
head_ "ESPOSIZIONE DISPARI (gc5035)"
if [ -n "${NODE[gc5035]:-}" ]; then
    sd=${SUBDEV[gc5035]}
    v4l2-ctl -d "$sd" --set-ctrl=analogue_gain=16 2>/dev/null
    v4l2-ctl -d "$sd" --set-ctrl=exposure=8 2>/dev/null
    read -r m8 c8 <<<"$(misura_media "${NODE[gc5035]}" "$OUT/.e8.raw")"
    v4l2-ctl -d "$sd" --set-ctrl=exposure=9 2>/dev/null
    read -r m9 c9 <<<"$(misura_media "${NODE[gc5035]}" "$OUT/.e9.raw")"
    v4l2-ctl -d "$sd" --set-ctrl=analogue_gain=0 --set-ctrl=exposure=984 2>/dev/null
    r=$(python3 -c "s8=max($m8-64,0.1); s9=max($m9-64,0.1); print(f'{s9/s8:.3f}')")
    echo "gc5035: esposizione 8 -> segnale $m8, 9 -> $m9, rapporto $r (1.125 se accetta i dispari, 1.000 se arrotonda)" >> "$OUT/07-esposizione-dispari.txt"
    if [ "$(python3 -c "print(int($m8 - 64 < 8))")" = 1 ]; then
        nd "gc5035: segnale troppo basso a 8 righe per decidere — serve piu' luce"
    elif [ "$(python3 -c "print(int(abs($r-1.125) < 0.05))")" = 1 ]; then
        ok "gc5035: accetta l'esposizione dispari (rapporto $r)"
    elif [ "$(python3 -c "print(int(abs($r-1.0) < 0.03))")" = 1 ]; then
        ko "gc5035: arrotonda l'esposizione al pari (rapporto $r): serve GC5035_EXP_STEP 2"
    else
        nd "gc5035: rapporto $r non decide, ripetere"
    fi
    rm -f "$OUT/.e8.raw" "$OUT/.e9.raw"
fi

# -------------------------------------------------------------- compliance
head_ "V4L2-COMPLIANCE"
# -z: il nodo del subdev sta sotto il dispositivo I2C, non sotto l'IPU6, e da
# solo v4l2-compliance non trova /dev/media0: senza, salta «Media Driver Info»
# e i test sul pad (formati, selezioni) e conta 46 test invece di 54.
mbus=$(media-ctl -d /dev/media0 -p 2>/dev/null | awk '/^bus info/ {print $3; exit}')
for s in gc5035 gc8034; do
    [ -n "${SUBDEV[$s]:-}" ] || continue
    # -u: il nodo e' un subdev. L'output completo va nella cover letter.
    # Fino al kernel 7.2 falliva il test degli eventi sui controlli; su next
    # il core imposta da solo V4L2_SUBDEV_FL_HAS_EVENTS, quindi zero e basta.
    # V4L2_COMPLIANCE= un v4l2-compliance compilato da git: Hans vuole la
    # versione con lo SHA in testa all'output, non quella del pacchetto.
    f="$OUT/04-compliance-$s.txt"
    timeout 300 "${V4L2_COMPLIANCE:-v4l2-compliance}" -z "$mbus" -u "${SUBDEV[$s]}" > "$f" 2>&1
    read -r good bad <<<"$(sed -n 's/.*Succeeded: \([0-9]*\), Failed: \([0-9]*\).*/\1 \2/p' "$f")"
    # Atteso: due avvisi sul CROP leggibile ma non scrivibile (Try e Active),
    # come imx219, imx258, gc05a2, gc08a3: un solo modo, crop fisso.
    altri=$(grep 'warn:' "$f" | grep -vc 'target 0 but not VIDIOC_SUBDEV_S_SELECTION')
    if ! grep -q 'Sub-Device ioctls (Source Pad 0)' "$f"; then
        ko "$s: compliance senza i test sul pad (dispositivo media non trovato)"
    elif [ "${bad:-9}" -eq 0 ] && [ "$altri" -eq 0 ]; then
        ok "$s: compliance $good ok, 0 falliti, solo gli avvisi attesi sul CROP"
    else
        ko "$s: compliance $good ok, ${bad:-?} falliti, $altri avvisi inattesi"
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

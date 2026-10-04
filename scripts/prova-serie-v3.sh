#!/bin/bash
# prova-serie-v3.sh — prova sul tablet della serie v3 (v4l2-subdev), da
# lanciare una volta sul kernel di debug "base" e una volta su quello "v3".
#
# Progetto INTEL-CAMERA. Kernel costruiti da scripts/build-tablet-debug.sh.
#
# Fasi, nell'ordine, con il dmesg salvato e classificato per ciascuna:
#
#   0 avvio      log del boot: cio' che KASAN/lockdep/UBSAN trovano PRIMA
#                di noi (wifi, i915, ...) non va attribuito alla prova
#   1 prima      uso normale: v4l2-compliance sui due sensori e sul media
#                device, cattura di 10 frame da ciascun sensore
#   2 open       per sensore: unbind/bind in ciclo mentre 4 processi aprono
#                e chiudono ogni /dev/v4l-subdev*  -> subdev_open(), 1/2
#   3 ioctl      per sensore: unbind/bind in ciclo mentre 4 processi tengono
#                aperto il nodo del sensore e ripetono VIDIOC_G_EXT_CTRLS
#                -> subdev_do_ioctl(), 2/2
#   4 dopo       di nuovo la fase 1: la macchina funziona ancora?
#
# Sul kernel base la fase 2 deve crashare (e' lo scopo). Al primo oops la
# prova si ferma: dopo, lo stato del kernel non e' piu' attendibile.
#
# ATTENZIONE, da sapere prima di leggere i risultati: gc5035/gc8034
# allocano la loro struttura con devm_kzalloc(), liberata all'unbind anche
# con il nodo ancora aperto. Un use-after-free segnalato da KASAN (tipico in
# subdev_close() o v4l2_fh_*) e' il limite sulla vita degli oggetti che la
# serie dichiara di NON risolvere, non un suo difetto. Il riepilogo separa
# i reperti per tipo e funzione apposta.
#
# Uso:  sudo ./scripts/prova-serie-v3.sh [cicli_per_fase]     (default 300)
# Esito: data/prova-v3-<kernel>-<data>/, riepilogo in RIEPILOGO.txt

set -u

CICLI="${1:-300}"
APRITORI=4
SENSORI="gc5035 gc8034"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$(uname -r)"
OUT="$PROJECT_DIR/data/prova-v3-$REL-$(date +%Y%m%d-%H%M%S)"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0 $*"; exit 1; }
case "$REL" in *intelcam-debug*) ;; *)
    echo "kernel $REL: non e' un kernel di debug intelcam"; exit 1 ;; esac
for t in python3 media-ctl v4l2-compliance v4l2-ctl; do
    command -v $t >/dev/null || { echo "manca $t"; exit 1; }
done

mkdir -p "$OUT"
R="$OUT/RIEPILOGO.txt"
log() { echo "$*" | tee -a "$R"; }

# ------------------------------------------------------------ classificatore
# Un reperto = una riga "tipo | funzione". La funzione viene dall'intestazione
# (KASAN, WARNING, UBSAN) o dalla prima riga RIP: che segue (oops, GPF).
classifica() {   # $1 = file dmesg
    python3 - "$1" <<'PY'
import re, sys, collections
righe = open(sys.argv[1], errors='replace').read().splitlines()
righe = [re.sub(r'^\[\s*[\d.]+\]\s*', '', r) for r in righe]
trovati = []
def rip(i):
    for r in righe[i:i+60]:
        m = re.search(r'RIP: \d+:([\w.]+)', r)
        if m: return m.group(1)
    return '?'
for i, r in enumerate(righe):
    if m := re.match(r'BUG: KASAN: ([\w-]+) in ([\w.]+)', r):
        trovati.append(('KASAN ' + m.group(1), m.group(2)))
    elif 'KASAN: null-ptr-deref' in r:
        trovati.append(('KASAN null-ptr-deref', rip(i)))
    elif r.startswith('BUG: kernel NULL pointer dereference'):
        trovati.append(('NULL deref', rip(i)))
    elif r.startswith('BUG: unable to handle page fault'):
        trovati.append(('page fault', rip(i)))
    elif r.startswith('BUG: sleeping function called'):
        trovati.append(('sleep in atomic', r.split(' at ')[-1]))
    elif m := re.match(r'WARNING: (possible .*|inconsistent .*|suspicious RCU.*)', r):
        trovati.append(('lockdep', m.group(1)[:60]))
    elif m := re.match(r'WARNING: CPU: \d+ PID: \d+ at \S+ ([\w.]+)', r):
        trovati.append(('WARNING', m.group(1)))
    elif m := re.match(r'WARNING: \S+:\d+ at ([\w.]+)', r):   # formato 7.x
        trovati.append(('WARNING', m.group(1)))
    elif m := re.match(r'UBSAN: ([\w-]+) in (\S+)', r):
        trovati.append(('UBSAN ' + m.group(1), m.group(2)))
    elif m := re.match(r'INFO: task (\S+) blocked', r):
        trovati.append(('hung task', m.group(1)))
    elif m := re.match(r'kmemleak: (\d+) new suspected', r):
        trovati.append(('kmemleak', m.group(1) + ' oggetti'))
c = collections.Counter((t, re.sub(r'\+0x.*', '', f)) for t, f in trovati)
if not c:
    print('    nessun reperto')
for (t, f), n in sorted(c.items()):
    print(f'    {n:5d}  {t:28s} {f}')
PY
}

fase_dmesg() {   # $1 = nome fase: salva, classifica, azzera
    dmesg > "$OUT/dmesg-$1.txt"
    log "  reperti nel dmesg ($1):"
    classifica "$OUT/dmesg-$1.txt" | tee -a "$R"
    dmesg -C
}

crash_nel_dmesg() {
    dmesg | grep -qE 'BUG: KASAN|KASAN: null-ptr-deref|BUG: kernel NULL|BUG: unable to handle|Oops'
}

# ------------------------------------------------------------ sensori
nodo_sensore() {   # $1 = gc5035 -> /dev/v4l-subdevN
    local ent
    ent=$(media-ctl -p 2>/dev/null | sed -n "s/^- entity [0-9]*: \($1 [0-9]*-[0-9a-f]*\) .*/\1/p")
    [ -n "$ent" ] && media-ctl -e "$ent" 2>/dev/null
}
dev_i2c() {        # $1 = gc5035 -> i2c-GCTI5035:00
    basename "$(ls -d /sys/bus/i2c/drivers/$1/i2c-GCTI* 2>/dev/null | head -1)" 2>/dev/null
}

uso_normale() {    # $1 = prima | dopo
    local s n
    log "== fase $1: uso normale"
    timeout 600 v4l2-compliance -M /dev/media0 > "$OUT/$1-compliance-media0.txt" 2>&1
    log "  media0: $(grep -E '^Total for' "$OUT/$1-compliance-media0.txt" | tail -1)"
    for s in $SENSORI; do
        n=$(nodo_sensore $s)
        if [ -z "$n" ]; then log "  $s: NON nel grafo"; continue; fi
        timeout 300 v4l2-compliance -d "$n" > "$OUT/$1-compliance-$s.txt" 2>&1
        log "  $s ($n): $(grep -E '^Total for' "$OUT/$1-compliance-$s.txt" | tail -1)"
        if "$PROJECT_DIR/scripts/cattura.sh" $s 10 "$OUT/$1-$s.raw" \
                > "$OUT/$1-cattura-$s.txt" 2>&1; then
            log "  $s: cattura ok, $(stat -c %s "$OUT/$1-$s.raw") byte"
        else
            log "  $s: cattura FALLITA (vedi $1-cattura-$s.txt)"
        fi
        rm -f "$OUT/$1-$s.raw"     # 10 frame raw sono ~100 MB: basta la misura
    done
    fase_dmesg "$1"
}

# ------------------------------------------------------------ lavoratori
# Ognuno scrive i suoi contatori in $OUT/w-<fase>-<n> ogni mezzo secondo:
# chi viene ucciso da un oops lascia l'ultimo valore, che basta.
lavoratore() {     # $1 = open | ioctl, $2 = file contatori, $3 = sensore
    exec python3 - "$1" "$2" "$3" <<'PY' >/dev/null 2>&1
import os, sys, glob, time, fcntl, struct, errno
modo, uscita, sensore = sys.argv[1:4]
def nodo_sensore():
    # Dopo ogni bind il nodo del sensore rinasce con un minor diverso:
    # va cercato per nome di entita' ("gc5035 3-003f") a ogni apertura.
    for d in glob.glob('/sys/class/video4linux/v4l-subdev*'):
        try:
            if open(d + '/name').read().startswith(sensore + ' '):
                return '/dev/' + os.path.basename(d)
        except OSError:
            pass
    return None
# VIDIOC_G_EXT_CTRLS = _IOWR('V', 71, struct v4l2_ext_controls), 32 byte;
# which = V4L2_CTRL_WHICH_CUR_VAL (0), count = 0, controls = NULL
G_EXT = 0xC0205647
arg = bytearray(struct.pack('<IIIiI4xQ', 0, 0, 0, 0, 0, 0))
ok = err = enodev = 0
t = time.time()
def scrivi():
    with open(uscita, 'w') as f: f.write(f'{ok} {err} {enodev}\n')
while True:
    if modo == 'open':
        for n in glob.glob('/dev/v4l-subdev*'):
            try:
                os.close(os.open(n, os.O_RDWR)); ok += 1
            except OSError as e:
                err += 1; enodev += e.errno == errno.ENODEV
    else:
        nodo = nodo_sensore()
        try:
            if nodo is None: raise OSError(errno.ENOENT, 'sensore assente')
            fd = os.open(nodo, os.O_RDWR)
        except OSError:
            err += 1; time.sleep(0.001); continue
        for _ in range(2000):        # tenuto aperto attraverso l'unbind
            try:
                fcntl.ioctl(fd, G_EXT, arg); ok += 1
            except OSError as e:
                err += 1
                if e.errno == errno.ENODEV: enodev += 1; break
        os.close(fd)
    if time.time() - t > 0.5:
        scrivi(); t = time.time()
PY
}

corsa() {          # $1 = open | ioctl, $2 = sensore -> 0 pulito, 1 crash
    local modo=$1 s=$2 dev nodo i PID=() esito=0 primo=""
    dev=$(dev_i2c $s); nodo=$(nodo_sensore $s)
    if [ -z "$dev" ] || [ -z "$nodo" ]; then
        log "== fase $modo/$s: sensore non agganciato, salto"; return 0
    fi
    log "== fase $modo/$s: $CICLI cicli unbind/bind di $dev, $APRITORI lavoratori"
    set +m
    for i in $(seq 1 $APRITORI); do
        lavoratore $modo "$OUT/w-$modo-$s-$i" $s & PID+=($!)
    done
    local t0=$SECONDS
    for i in $(seq 1 "$CICLI"); do
        echo "$dev" > "/sys/bus/i2c/drivers/$s/unbind" 2>/dev/null
        echo "$dev" > "/sys/bus/i2c/drivers/$s/bind"   2>/dev/null
        if [ -z "$primo" ] && crash_nel_dmesg; then
            primo=$i; esito=1; break
        fi
    done
    kill "${PID[@]}" 2>/dev/null; wait 2>/dev/null
    local vivi=0 tot_ok=0 tot_err=0 tot_nodev=0 f a b c
    for f in "$OUT"/w-$modo-$s-*; do
        read -r a b c < "$f" 2>/dev/null || continue
        tot_ok=$((tot_ok+a)); tot_err=$((tot_err+b)); tot_nodev=$((tot_nodev+c))
    done
    [ -n "$primo" ] && log "  CRASH al ciclo $primo" \
                    || log "  $CICLI cicli completati in $((SECONDS-t0)) s"
    log "  lavoratori: $tot_ok riusciti, $tot_err errori (di cui ENODEV $tot_nodev)"
    log "  sensore ancora agganciato: $([ -n "$(dev_i2c $s)" ] && echo si || echo NO)"
    fase_dmesg "$modo-$s"
    return $esito
}

# ------------------------------------------------------------ esecuzione
log "prova serie v3 — $(date -Is)"
log "kernel  : $REL"
log "versione: $(cat /proc/version)"
log "cmdline : $(cat /proc/cmdline)"
log "cicli   : $CICLI per fase"
lsmod > "$OUT/lsmod.txt"
media-ctl -p > "$OUT/media-ctl-prima.txt" 2>&1
log ""
log "== fase avvio"
fase_dmesg avvio

uso_normale prima

crash=0
for modo in open ioctl; do
    for s in $SENSORI; do
        corsa $modo $s || { crash=1; break 2; }
    done
done

if [ $crash -eq 0 ]; then
    uso_normale dopo
    media-ctl -p > "$OUT/media-ctl-dopo.txt" 2>&1
else
    log ""
    log "Prova fermata al primo crash: riavviare prima di altro."
fi

if [ -w /sys/kernel/debug/kmemleak ]; then
    echo scan > /sys/kernel/debug/kmemleak; sleep 5
    cat /sys/kernel/debug/kmemleak > "$OUT/kmemleak.txt"
    log "kmemleak: $(grep -c '^unreferenced object' "$OUT/kmemleak.txt") oggetti sospetti (tutto il boot)"
fi
cat /proc/sys/kernel/tainted > "$OUT/tainted.txt"
log "tainted: $(cat "$OUT/tainted.txt")"
chown -R "$(stat -c %U "$PROJECT_DIR")": "$OUT"
log ""
log "Risultati in $OUT"

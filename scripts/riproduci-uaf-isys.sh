#!/bin/bash
# riproduci-uaf-isys.sh — unbind di ipu6-isys con nodi ancora aperti.
#
# Progetto INTEL-CAMERA. Passo 1 del lavoro sulla vita degli oggetti in
# ipu6-isys (docs/12-recensione-serie-ipu6.md, 8 ottobre): prima di scrivere
# codice, il use-after-free va RIPRODOTTO, non dedotto.
#
# Cosa ci aspettiamo dalla lettura del codice (next 9cfc1aca0):
#   - struct ipu6_isys (con media_dev e v4l2_dev) e' allocata con
#     devm_kzalloc() sull'auxdev, i nodi video av[] stanno in isys->csi2,
#     allocato con devm_kcalloc(): tutto liberato all'unbind;
#   - isys_remove() fa mutex_destroy() su mutex che i file aperti usano.
# Quindi usare o chiudere un nodo rimasto aperto dopo l'unbind dovrebbe
# toccare memoria liberata (KASAN slab-use-after-free).
#
# Niente cicli: UN processo apre media0, un nodo video di isys e il nodo
# di un CSI2, poi esegue un passo alla volta e salva il dmesg dopo ognuno,
# cosi' si vede quale passo tocca memoria liberata:
#
#   unbind isys -> ioctl media -> ioctl video -> ioctl subdev
#               -> close subdev -> close video -> close media
#
# Nessuno streaming, isys non viene ricollegato. Dopo la prova il kernel
# non e' attendibile: RIAVVIARE prima di qualsiasi altra cosa.
#
# Uso:  sudo ./scripts/riproduci-uaf-isys.sh
# Esito: data/uaf-isys-<kernel>-<data>/, riepilogo in RIEPILOGO.txt

set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$(uname -r)"
OUT="$PROJECT_DIR/data/uaf-isys-$REL-$(date +%Y%m%d-%H%M%S)"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }
case "$REL" in *intelcam-debug*) ;; *)
    echo "kernel $REL: non e' un kernel di debug intelcam"; exit 1 ;; esac
command -v python3 >/dev/null || { echo "manca python3"; exit 1; }

DRV=$(ls -d /sys/bus/auxiliary/drivers/*isys* 2>/dev/null | head -1)
[ -n "$DRV" ] || { echo "driver isys non trovato in /sys/bus/auxiliary/drivers"; exit 1; }
DEV=$(basename "$(ls -d "$DRV"/*.isys.* 2>/dev/null | head -1)")
[ -n "$DEV" ] || { echo "nessun dispositivo agganciato a $DRV"; exit 1; }

mkdir -p "$OUT"
R="$OUT/RIEPILOGO.txt"
log() { echo "$*" | tee -a "$R"; }

log "riproduzione UAF ipu6-isys — $(date -Is)"
log "kernel  : $REL"
log "versione: $(cat /proc/version)"
log "cmdline : $(cat /proc/cmdline)"
log "driver  : $DRV"
log "device  : $DEV"
grep -q kasan_multi_shot /proc/cmdline || \
    log "NOTA: senza kasan_multi_shot KASAN stampa solo il PRIMO rapporto:" \
        "i passi dopo il primo UAF possono risultare puliti senza esserlo."
dmesg > "$OUT/dmesg-avvio.txt"
dmesg -C
log ""

python3 - "$DRV" "$DEV" "$OUT" <<'PY' 2>&1 | tee -a "$R"
import os, sys, glob, fcntl, subprocess, time, re

drv, dev, out = sys.argv[1:4]

def ioc(dir_, typ, nr, size):
    return (dir_ << 30) | (size << 16) | (ord(typ) << 8) | nr
R, RW = 2, 3
MEDIA_IOC_DEVICE_INFO  = ioc(RW, '|', 0x00, 256)   # struct media_device_info
VIDIOC_QUERYCAP        = ioc(R,  'V', 0,    104)   # struct v4l2_capability
VIDIOC_SUBDEV_QUERYCAP = ioc(R,  'V', 0,    64)    # struct v4l2_subdev_capability

def nodo(prefisso):
    for d in sorted(glob.glob('/sys/class/video4linux/*')):
        try:
            if open(d + '/name').read().startswith(prefisso):
                return '/dev/' + os.path.basename(d)
        except OSError:
            pass
    return None

def media_di_isys():
    for d in sorted(glob.glob('/sys/class/media/media*')):
        if os.path.realpath(d).find(dev) >= 0:
            return '/dev/' + os.path.basename(d)
    return '/dev/media0'

reperto = re.compile(r'BUG: KASAN|KASAN: null-ptr-deref|BUG: kernel NULL|'
                     r'BUG: unable to handle|Oops|WARNING:|UBSAN:|'
                     r'DEBUG_LOCKS_WARN_ON|general protection')

def passo(n, nome, azione):
    try:
        r = azione()
        esito = 'ok' + ('' if r is None else f' ({r})')
    except OSError as e:
        esito = f'errore {e.errno} ({os.strerror(e.errno)})'
    time.sleep(1)
    testo = subprocess.run(['dmesg'], capture_output=True, text=True).stdout
    subprocess.run(['dmesg', '-C'])
    f = f'{out}/dmesg-{n}-{nome}.txt'
    open(f, 'w').write(testo)
    righe = [re.sub(r'^\[\s*[\d.]+\]\s*', '', l) for l in testo.splitlines()]
    trovati = [l for l in righe if reperto.search(l)]
    print(f'{n} {nome:15s} {esito}')
    for l in trovati[:6]:
        print(f'      {l[:110]}')
    if len(trovati) > 6:
        print(f'      ... altre {len(trovati) - 6} righe, vedi {os.path.basename(f)}')
    sys.stdout.flush()

media = media_di_isys()
video = nodo('Intel IPU6 ISYS Capture')
subdev = nodo('Intel IPU6 CSI2')
print(f'nodi    : media {media}, video {video}, subdev {subdev}')
if not (video and subdev):
    print('nodi di isys non trovati: niente da provare'); sys.exit(1)

fd = {}
fd['media'] = os.open(media, os.O_RDWR)
fd['video'] = os.open(video, os.O_RDWR)
fd['subdev'] = os.open(subdev, os.O_RDWR)
buf = {k: bytearray(n) for k, n in (('media', 256), ('video', 104), ('subdev', 64))}
print('aperti tutti e tre; controllo che rispondano prima dell\'unbind:')
fcntl.ioctl(fd['media'], MEDIA_IOC_DEVICE_INFO, buf['media'])
fcntl.ioctl(fd['video'], VIDIOC_QUERYCAP, buf['video'])
fcntl.ioctl(fd['subdev'], VIDIOC_SUBDEV_QUERYCAP, buf['subdev'])
print('  ok\n')
sys.stdout.flush()

def unbind():
    with open(f'{drv}/unbind', 'w') as f:
        f.write(dev)

passo(1, 'unbind-isys',   unbind)
passo(2, 'ioctl-media',   lambda: fcntl.ioctl(fd['media'], MEDIA_IOC_DEVICE_INFO, buf['media']))
passo(3, 'ioctl-video',   lambda: fcntl.ioctl(fd['video'], VIDIOC_QUERYCAP, buf['video']))
passo(4, 'ioctl-subdev',  lambda: fcntl.ioctl(fd['subdev'], VIDIOC_SUBDEV_QUERYCAP, buf['subdev']))
passo(5, 'close-subdev',  lambda: os.close(fd['subdev']))
passo(6, 'close-video',   lambda: os.close(fd['video']))
passo(7, 'close-media',   lambda: os.close(fd['media']))
PY

log ""
log "isys ancora agganciato: $([ -e "$DRV/$DEV" ] && echo si || echo no)"
cat /proc/sys/kernel/tainted > "$OUT/tainted.txt"
log "tainted: $(cat "$OUT/tainted.txt")"
chown -R "$(stat -c %U "$PROJECT_DIR")": "$OUT"
log ""
log "Risultati in $OUT"
log "RIAVVIARE il tablet prima di qualsiasi altra prova."

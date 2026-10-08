#!/bin/bash
# riproduci-unbind-isys-streaming.sh — unbind di ipu6-isys con una cattura
# IN CORSO, un passo alla volta.
#
# Progetto INTEL-CAMERA. Prova per la patch 1/2 della serie sulla vita degli
# oggetti in ipu6-isys (docs/12-recensione-serie-ipu6.md, 8 ottobre).
#
# Cosa ci aspettiamo dalla lettura del codice (next 9cfc1aca0 e 8e26d4c20):
# isys_remove() chiama ida_destroy(&isys->streams) e free_fw_msg_bufs()
# PRIMA di isys_unregister_devices(). Con uno streaming acceso, e' solo
# vb2_video_unregister_device() dentro isys_unregister_devices() a fermarlo,
# e lo stop passa per ipu6_get_fw_msg_buf() (lista dei messaggi gia'
# liberati) e ida_free() (ida gia' distrutta).
#
# Passi, con il dmesg salvato dopo ognuno:
#   1 streaming acceso (v4l2-ctl --stream-mmap), controllo che sia partito
#   2 unbind di isys
#   3 fine del processo di cattura (da solo, o kill dopo la grazia)
#   4 (solo con ATTESA=<s>) dmesg dopo altri <s> secondi
#
# Isys non viene ricollegato. Dopo la prova il kernel non e' attendibile:
# RIAVVIARE prima di qualsiasi altra cosa.
#
# Uso:  sudo ./scripts/riproduci-unbind-isys-streaming.sh [gc5035|gc8034]
# Esito: data/unbind-isys-streaming-<kernel>-<data>/, riepilogo in RIEPILOGO.txt
#
# Il primo tentativo (8 ottobre, 10:02) ha bloccato il tablet e non ha lasciato
# niente: file locali a 0 byte, journal fermo prima della prova, nessun
# pstore ne' rilevatore di lockup in questo kernel. Per questo il dmesg scorre
# in diretta via SSH sul server (REMOTO, default 192.168.0.2) in
# ~/intelcam-log/<nome della cartella>.txt, e ogni riga del riepilogo va anche
# in /dev/kmsg, cosi' il file sul server dice a che passo eravamo.
#
# Il secondo tentativo (10:12) ha mostrato che non basta: il server riceve
# tutto fino a "1 streaming acceso" e poi niente, nemmeno la riga del passo 2.
# Il blocco avviene dentro l'echo di unbind e ferma anche ssh. Quello che
# il kernel stampa non arriva piu' in rete, ma puo' ancora arrivare sulla
# console. Per questo prima dell'unbind la console va al livello 8 e ogni
# riga del kernel viene rallentata di RITARDO ms (default 150), e lo schermo
# passa da solo alla console di testo VT (default 3, con l'ioctl VT_ACTIVATE:
# Ctrl+Alt+F3 sulla tastiera del tablet non funziona e chvt non c'e').
# Si lancia dal terminale grafico; dall'unbind in poi filmare lo schermo col
# telefono. Se la prova finisce senza bloccarsi, lo schermo torna da solo
# alla sessione grafica.
#
# Il passaggio di console avviene prima dello streaming, a printk normale:
# alle 11:28 e alle 11:41 (kernel -pm), fatto subito prima dell'unbind con
# printk_delay attivo, ha bloccato il tablet nei WARN intel_tc.c di i915.
#
# Il terzo tentativo (10:32) e' riuscito: oops in ipu6_put_fw_msg_buf() dentro
# l'ISR, rapporto completo sul server (ssh ha retto ~13 s dopo l'oops) e sullo
# schermo. Lettura in docs/12-recensione-serie-ipu6.md, 8 ottobre 10:40.

set -u

SENS="${1:-gc5035}"
GRAZIA="${GRAZIA:-5}"
RITARDO="${RITARDO:-150}"
VT="${VT:-3}"
REMOTO="${REMOTO:-192.168.0.2}"
UTENTE="${SUDO_USER:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$(uname -r)"
OUT="$PROJECT_DIR/data/unbind-isys-streaming-$REL-$(date +%Y%m%d-%H%M%S)"

[ "$(id -u)" -eq 0 ] || { echo "serve root: sudo $0"; exit 1; }
case "$REL" in *intelcam-debug*) ;; *)
    echo "kernel $REL: non e' un kernel di debug intelcam"; exit 1 ;; esac
command -v v4l2-ctl >/dev/null || { echo "manca v4l2-ctl"; exit 1; }
[ -n "$UTENTE" ] || { echo "lanciare con sudo da utente (serve la sua chiave SSH)"; exit 1; }
# vt N: porta lo schermo sulla console N; vt senza argomenti: dice quale e'.
vt() {
    python3 -I -c 'import fcntl, os, struct, sys
f = os.open("/dev/tty0", os.O_RDWR)
if len(sys.argv) > 1:
    n = int(sys.argv[1])
    fcntl.ioctl(f, 0x5606, n)    # VT_ACTIVATE
    fcntl.ioctl(f, 0x5607, n)    # VT_WAITACTIVE
else:
    print(struct.unpack("HHH", fcntl.ioctl(f, 0x5603, bytes(6)))[0])  # VT_GETSTATE' "$@"
}
vt_cambia() { timeout -s KILL 60 bash -c "$(declare -f vt); vt $1"; }
remoto() { sudo -u "$UTENTE" ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTO" "$@"; }
remoto true || { echo "server $REMOTO non raggiungibile via SSH"; exit 1; }

DRV=$(ls -d /sys/bus/auxiliary/drivers/*isys* 2>/dev/null | head -1)
[ -n "$DRV" ] || { echo "driver isys non trovato"; exit 1; }
DEV=$(basename "$(ls -d "$DRV"/*.isys.* 2>/dev/null | head -1)")
[ -n "$DEV" ] || { echo "nessun dispositivo agganciato a $DRV"; exit 1; }

mkdir -p "$OUT"
# Subito, non alla fine: se il kernel si blocca la fine non arriva.
chown "$(stat -c %U "$PROJECT_DIR")": "$OUT"
R="$OUT/RIEPILOGO.txt"
log() {
    echo "$*" | tee -a "$R"
    [ -n "$*" ] && echo "intelcam-prova: $*" > /dev/kmsg
    sync "$R"
}

# dmesg in diretta sul server; dmesg -C non tocca chi legge /dev/kmsg.
NOME="$(basename "$OUT")"
dmesg -w -x | remoto "mkdir -p intelcam-log && cat > intelcam-log/$NOME.txt" &
DPID=$!
sleep 2
remoto "test -s intelcam-log/$NOME.txt" || {
    echo "il dmesg non arriva sul server, prova annullata"; kill "$DPID"; exit 1; }

reperto='BUG: KASAN|KASAN: null-ptr-deref|BUG: kernel NULL|BUG: unable to handle|Oops|WARNING:|UBSAN:|DEBUG_LOCKS_WARN_ON|general protection|list_(add|del) corruption'

passo() {   # $1 numero, $2 nome
    local f="$OUT/dmesg-$1-$2.txt"
    sleep 1
    dmesg > "$f"; dmesg -C; sync "$f"
    sed -E 's/^\[ *[0-9.]+\] *//' "$f" | grep -E "$reperto" | head -8 | sed 's/^/      /' | tee -a "$R"
    local n; n=$(grep -cE "$reperto" "$f")
    [ "$n" -gt 8 ] && log "      ... in tutto $n righe, vedi $(basename "$f")"
}

log "unbind di ipu6-isys a streaming acceso — $(date -Is)"
log "kernel  : $REL"
log "versione: $(cat /proc/version)"
log "cmdline : $(cat /proc/cmdline)"
log "driver  : $DRV"
log "device  : $DEV"
log "sensore : $SENS"
grep -q kasan_multi_shot /proc/cmdline || \
    log "NOTA: senza kasan_multi_shot KASAN stampa solo il PRIMO rapporto."
dmesg > "$OUT/dmesg-avvio.txt"

# Pipeline: cattura.sh configura link e formati e cattura 1 fotogramma.
LINEA=$("$PROJECT_DIR/scripts/cattura.sh" "$SENS" 1 /dev/null 2>&1 | head -1)
VID=$(echo "$LINEA" | grep -oE "/dev/video[0-9]+")
[ -n "$VID" ] || { log "pipeline non configurata: $LINEA"; exit 1; }
log "pipeline: $LINEA"
# La chiusura di cattura.sh avvia una runtime suspend. Col kernel col ritardo
# (tablet-isys-pm) dura 5 s e blocca la resume dello streaming: va lasciata
# finire, altrimenti la suspend della finestra 1 non parte all'unbind.
PM="/sys/bus/auxiliary/devices/$DEV/power/runtime_status"
for _ in $(seq 1 30); do
    [ "$(cat "$PM")" = suspended ] && break
    sleep 0.5
done
log "runtime : isys $(cat "$PM") prima dello streaming"
# Il passaggio alla console di testo fa ripartire il rilevamento della porta
# Type-C di i915 (fb_set_var -> drm_fb_helper_hotplug_event), con i WARN di
# intel_tc.c. Col printk_delay attivo ogni WARN tiene la CPU ~13 s: alle
# 11:28 e alle 11:41 il tablet si e' fermato qui, prima dell'unbind. Quindi
# lo schermo passa adesso, a printk normale, e se non passa la prova si ferma.
VT_ORIG=$(vt)
if ! vt_cambia "$VT"; then
    log "schermo  : passaggio a tty$VT non riuscito in 60 s, prova annullata"
    exit 4
fi
log "schermo  : su tty$VT (era tty$VT_ORIG)"
dmesg -C
log ""

CAP="$OUT/v4l2-ctl.txt"
v4l2-ctl -d "$VID" --stream-mmap --stream-count=100000 > "$CAP" 2>&1 &
SPID=$!
sleep 3
if grep -q "VIDIOC_STREAMON returned -1" "$CAP" || ! kill -0 "$SPID" 2>/dev/null; then
    log "1 streaming       NON PARTITO: prova non valida"
    tail -3 "$CAP" | tee -a "$R"
    kill -9 "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    exit 3
fi
FRAMES=$(tr '\r' '\n' < "$CAP" | grep -c '<')
log "1 streaming       acceso su $VID ($FRAMES fotogrammi in 3 s)"
passo 1 streaming

# Da qui in poi l'unica traccia sicura e' lo schermo.
PRINTK_ORIG=$(cat /proc/sys/kernel/printk)
log "2 unbind-isys     sta per partire (console livello 8, ${RITARDO} ms per riga)"
dmesg -n 8
echo "$RITARDO" > /proc/sys/kernel/printk_delay
log "2 unbind-isys     unbind adesso"
echo "$DEV" > "$DRV/unbind"
log "2 unbind-isys     esito $? , isys agganciato: $([ -e "$DRV/$DEV" ] && echo si || echo no)"
passo 2 unbind-isys

for _ in $(seq 1 $((GRAZIA * 2))); do
    kill -0 "$SPID" 2>/dev/null || break
    sleep 0.5
done
if kill -0 "$SPID" 2>/dev/null; then
    kill -9 "$SPID" 2>/dev/null
    log "3 fine-cattura    appesa dopo ${GRAZIA}s, terminata con kill -9"
else
    log "3 fine-cattura    uscita da sola: $(tr '\r' '\n' < "$CAP" | grep -iE 'fail|error' | tail -1)"
fi
wait "$SPID" 2>/dev/null
passo 3 fine-cattura
# Con il kernel col ritardo nella runtime suspend (tablet-isys-pm) la suspend
# riparte 5 s dopo l'unbind: ATTESA=10 la fa rientrare nel dmesg della prova.
if [ "${ATTESA:-0}" -gt 0 ]; then
    sleep "$ATTESA"
    log "4 attesa          ${ATTESA}s dopo la fine della cattura"
    passo 4 attesa
fi
echo 0 > /proc/sys/kernel/printk_delay
echo "$PRINTK_ORIG" > /proc/sys/kernel/printk
vt_cambia "$VT_ORIG"

log ""
cat /proc/sys/kernel/tainted > "$OUT/tainted.txt"
log "tainted: $(cat "$OUT/tainted.txt")"
chown -R "$(stat -c %U "$PROJECT_DIR")": "$OUT"
log "Risultati in $OUT"
log "dmesg completo anche sul server: $REMOTO:intelcam-log/$NOME.txt"
log "RIAVVIARE il tablet prima di qualsiasi altra prova."
sleep 1; kill "$DPID" 2>/dev/null

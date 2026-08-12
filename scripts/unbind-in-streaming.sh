#!/bin/bash
# unbind mentre lo streaming e' in corso — reperti A1, C1 e C4.
# Uso: sudo unbind-in-streaming.sh <gc5035|gc8034> [cicli]
#
# Perche' esiste: e' lo scenario che fa emergere i difetti piu' brutti, quelli
# che si vedono solo quando qualcuno stacca l'hardware mentre lo si sta usando.
# Ha gia' trovato tre NULL pointer dereference / use-after-free di mainline
# (A1, A2, C1) e il blocco di DQBUF (C4).
#
# Due trappole, imparate sbagliando il 2026-08-12
# -----------------------------------------------
# 1. `wait` liscio sul processo di cattura significa attesa INFINITA finche'
#    C4 non e' corretto: senza la patch, DQBUF non torna mai. La prima
#    versione si e' impiantata al primo ciclo e c'e' voluto un quarto d'ora
#    per capire che non era lenta, era ferma. Qui c'e' una finestra di grazia.
#
# 2. Molto peggio: se la pipeline non e' configurata, STREAMON fallisce
#    subito con ENOLINK e il processo esce in un decimo di secondo. Una
#    versione precedente contava quell'uscita come "la cattura e' uscita da
#    sola", cioe' come la prova che C4 fosse corretto. Dava 5 successi su 5
#    senza che un solo fotogramma fosse mai stato catturato.
#
#    Da qui la regola: **un ciclo in cui lo streaming non e' partito non e'
#    un ciclo riuscito, e' un ciclo non valido**, e lo script si ferma.

set -u

SENS="${1:-gc5035}"; CICLI="${2:-5}"
GRAZIA="${GRAZIA:-5}"        # secondi concessi al processo per uscire da solo

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

DEV=$(basename "$(ls -d /sys/bus/i2c/drivers/$SENS/i2c-GCTI* 2>/dev/null | head -1)")
[ -n "$DEV" ] || { echo "$SENS non agganciato"; exit 1; }

# La pipeline va configurata, e va riconfigurata dopo ogni ricarica dei
# moduli: il grafo torna ai default e i link si spengono. cattura.sh fa
# esattamente questo, quindi si riusa invece di riscriverlo qui.
echo "configuro la pipeline di $SENS"
LINEA=$("$PROJECT_DIR/scripts/cattura.sh" "$SENS" 1 /dev/null 2>&1 | head -1) || {
    echo "non riesco a configurare la pipeline:"; echo "$LINEA"; exit 1; }
VID=$(echo "$LINEA" | grep -oE "/dev/video[0-9]+")
[ -n "$VID" ] || { echo "non trovo il nodo di cattura: $LINEA"; exit 1; }

BASE=$(dmesg | wc -l)   # da qui in avanti nel log; il buffer non si azzera

echo "sensore $SENS ($DEV) su $VID, $CICLI cicli, grazia ${GRAZIA}s"

APPESI=0
USCITI=0

for i in $(seq 1 "$CICLI"); do
    LOG="$TMP/ciclo$i.txt"
    v4l2-ctl -d "$VID" --stream-mmap --stream-count=1000 > "$LOG" 2>&1 &
    SPID=$!
    sleep 2                                   # lascia partire lo streaming

    # Il controllo che mancava: lo streaming e' partito davvero?
    if grep -q "VIDIOC_STREAMON returned -1" "$LOG" 2>/dev/null; then
        echo "  ciclo $i: STREAMON e' fallito, la cattura non e' mai partita"
        sed -n 's/^[[:space:]]*//p' "$LOG" | tail -2
        echo "  -> ciclo NON VALIDO: senza streaming non si sta provando niente"
        kill -9 "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
        exit 3
    fi
    if ! kill -0 "$SPID" 2>/dev/null; then
        echo "  ciclo $i: la cattura e' morta prima dell'unbind — NON VALIDO"
        tail -3 "$LOG"; exit 3
    fi

    echo "  ciclo $i: unbind a streaming acceso"
    echo "$DEV" > /sys/bus/i2c/drivers/$SENS/unbind 2>/dev/null

    # Si controlla ogni mezzo secondo invece di dormire GRAZIA secondi fissi,
    # cosi' un'uscita spontanea si vede subito.
    for _ in $(seq 1 $((GRAZIA * 2))); do
        kill -0 "$SPID" 2>/dev/null || break
        sleep 0.5
    done

    if kill -0 "$SPID" 2>/dev/null; then
        echo "  ciclo $i: DQBUF appeso dopo ${GRAZIA}s, termino il processo"
        kill -9 "$SPID" 2>/dev/null
        APPESI=$((APPESI+1))
    else
        ERR=$(grep -oE 'VIDIOC_DQBUF: failed: .*' "$LOG" | tail -1 | sed 's/.*failed: //')
        FPS=$(grep -oE '[0-9]+\.[0-9]+ fps' "$LOG" | tail -1)
        echo "  ciclo $i: la cattura e' uscita da sola — DQBUF: ${ERR:-nessun errore riportato} (girava a ${FPS:-?})"
        USCITI=$((USCITI+1))
    fi
    wait "$SPID" 2>/dev/null

    sleep 1
    echo "$DEV" > /sys/bus/i2c/drivers/$SENS/bind 2>/dev/null
    sleep 1
    if [ -L "/sys/bus/i2c/devices/$DEV/driver" ]; then
        echo "  ciclo $i: ri-agganciato"
    else
        echo "  ciclo $i: NON ri-agganciato"; exit 1
    fi

    # Dopo il bind la pipeline va rifatta: il sensore e' rientrato nel grafo
    # come entita' nuova e il link verso il nodo di cattura e' spento.
    "$PROJECT_DIR/scripts/cattura.sh" "$SENS" 1 /dev/null >/dev/null 2>&1 || true

    # Il vero criterio di fallimento non e' il blocco, e' la corruzione.
    if dmesg | tail -n "+$BASE" | grep -qiE "BUG: KASAN|use-after-free|BUG:"; then
        echo "  ciclo $i: REPERTO NEL KERNEL — mi fermo"
        dmesg | tail -n "+$BASE" | grep -iE "BUG: KASAN|use-after-free|BUG:" | head -5
        exit 2
    fi
done

echo
echo "fatto: $CICLI cicli veri, senza perdere il driver e senza reperti del kernel"
echo "  catture uscite da sole:  $USCITI"
echo "  catture appese su DQBUF: $APPESI"
if [ "$APPESI" -gt 0 ]; then
    echo "  -> C4 presente: manca la patch che chiama vb2_queue_error()"
else
    echo "  -> C4 corretto: la coda viene svegliata e DQBUF torna con un errore"
fi

if dmesg | tail -n "+$BASE" | grep -qi "lockdep is turned off"; then
    echo "  ATTENZIONE: lockdep si e' spento, il verdetto sul locking non vale"
fi

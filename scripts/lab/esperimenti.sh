#!/bin/bash
# esperimenti.sh — esperimenti E1-E9 di docs/14 col driver da laboratorio.
#
#   sudo scripts/lab/esperimenti.sh [gc5035|gc8034|tutti] [solo-E...]
#
# Scena: oggetti colorati (uno rosso e uno blu ben visibili) e con dettagli,
# luce costante, tablet fermo. Ogni esperimento cattura 6 fotogrammi in
# data/lab-DATA/ e scrive l'analisi in risultati.txt. Non tocca il driver.

set -u
QUI=$(cd "$(dirname "$0")" && pwd)
CATT=$QUI/lab-cattura.sh
AN="python3 -I $QUI/lab-analizza.py"
CHI=${1:-tutti}
SOLO=${2:-}
D=$(cd "$QUI/../.." && pwd)/data/lab-$(date +%Y%m%d-%H%M%S)
mkdir -p "$D"
R=$D/risultati.txt
exec > >(tee -a "$R") 2>&1

uname -r
dmesg -C

# es NOME SENSORE W H CODICE [RIF] -- righe di registri "pagina reg valore"
es() {
    local nome=$1 s=$2 w=$3 h=$4 c=$5 rif=$6
    shift 6
    [ -n "$SOLO" ] && [[ "$nome" != $SOLO* ]] && return 0
    printf '%s\n' "$@" > "$D/$nome.regs"
    echo; echo "=== $nome: $s ${w}x${h} $c ($*)"
    if ! "$CATT" "$s" "$w" "$h" "$c" 6 "$D/$nome" "$D/$nome.regs" > "$D/$nome.log" 2>&1; then
        echo "   CATTURA FALLITA:"; tail -5 "$D/$nome.log"
    fi
    tail -1 "$D/$nome.log"
    if [ -n "$rif" ] && [ -s "$D/$rif.raw" ]; then
        $AN "$D/$nome" --rif "$D/$rif"
    else
        $AN "$D/$nome"
    fi
    dmesg -c | grep -vE "lab: " | tail -5
}

if [ "$CHI" = gc5035 ] || [ "$CHI" = tutti ]; then
    S=gc5035
    # base: tabella del driver, 2592x1944 GRBG
    es g5-base $S 2592 1944 GRBG ""
    # E1 parita' Bayer: x di uscita 8->7, poi y 8->7
    es g5-E1-x7 $S 2592 1944 GRBG g5-base "1 0x94 7"
    es g5-E1-y7 $S 2592 1944 GRBG g5-base "1 0x92 7"
    # E2 col start 3 -> 2, 4, 5, 11 (spostamento e fase)
    for c in 2 4 5 11; do
        es g5-E2-col$c $S 2592 1944 GRBG g5-base "0 0x0c $c"
    done
    # E2b row start 4 -> 5, 6, 12
    for r in 5 6 12; do
        es g5-E2-row$r $S 2592 1944 GRBG g5-base "0 0x0a $r"
    done
    # E3 mirror/flip
    es g5-E3-h $S 2592 1944 GRBG g5-base "0 0x17 0x81"
    es g5-E3-v $S 2592 1944 GRBG g5-base "0 0x17 0x82"
    es g5-E3-v-comp $S 2592 1944 GRBG g5-base "0 0x17 0x82" "0 0x54 0x03" "2 0x22 0xfc"
    es g5-E3-hv-comp $S 2592 1944 GRBG g5-base "0 0x17 0x83" "0 0x54 0x03" "2 0x22 0xfc"
    # E5 finestra verticale ridotta: 1000 righe al centro (row 476, altezza 1016)
    es g5-E5-1000 $S 2592 1000 GRBG "" "0 0x09 0x01" "0 0x0a 0xdc" "0 0x0d 0x03" "0 0x0e 0xf8" \
        "1 0x95 0x03" "1 0x96 0xe8"
    # E5b crop orizzontale con la sola uscita: 1296 colonne al centro (x 656)
    es g5-E5-x1296 $S 1296 1944 GRBG "" "1 0x93 0x02" "1 0x94 0x90" "1 0x97 0x05" "1 0x98 0x10"
    # E5c finestra analogica orizzontale ridotta: larghezza 1312 da col 651
    es g5-E5-win1312 $S 1296 1944 GRBG "" "0 0x0b 0x02" "0 0x0c 0x8b" "0 0x0f 0x05" "0 0x10 0x20" \
        "1 0x97 0x05" "1 0x98 0x10"
    # E4 binning. A: modo 1296x972 del vendor (PLL dimezzata, 0xf8 resta a 19,2 MHz)
    BIN_ISP=("0 0x1f 0x19" "0 0x33 0x20" "1 0x44 0x02" "1 0x49 0x00" "1 0x4a 0x01"
             "1 0x4b 0xf8" "1 0x4e 0x06" "2 0x14 0x02" "2 0x15 0x00")
    BIN_OUT=("1 0x92 0x04" "1 0x94 0x03" "1 0x95 0x03" "1 0x96 0xcc" "1 0x97 0x05" "1 0x98 0x10")
    BIN_PLL=("0 0xf5 0xe4" "0 0xf7 0x11" "0 0xf9 0x12" "0 0xfa 0x01"
             "0 0x21 0x60" "0 0x29 0x30" "0 0x44 0x18" "0 0x4e 0x20" "0 0x8c 0x20"
             "0 0x91 0x15" "0 0x92 0x3a" "0 0x95 0x45" "0 0x96 0x35" "0 0x97 0x20"
             "0 0x9d 0x0c" "0 0xd0 0xb3" "0 0xd5 0xf0"
             "3 0x01 0x87" "3 0x02 0x58" "3 0x22 0x03" "3 0x26 0x06" "3 0x29 0x03" "3 0x2b 0x06")
    es g5-E4-A $S 1296 972 GRBG "" "${BIN_PLL[@]}" "${BIN_ISP[@]}" "${BIN_OUT[@]}"
    es g5-E4-A-RGGB $S 1296 972 RGGB "" "${BIN_PLL[@]}" "${BIN_ISP[@]}" "${BIN_OUT[@]}"
    # B: binning con la PLL piena
    es g5-E4-B $S 1296 972 GRBG "" "${BIN_ISP[@]}" "${BIN_OUT[@]}"
    # C: A senza 0x33 (atteso: un quarto del campo, niente media)
    es g5-E4-C $S 1296 972 GRBG "" "${BIN_PLL[@]}" "${BIN_ISP[@]}" "${BIN_OUT[@]}" "0 0x33 0x00"
    # D: solo 0x33 e uscita (cosa fa da solo)
    es g5-E4-D $S 1296 972 GRBG "" "0 0x33 0x20" "${BIN_OUT[@]}"
    # E9 estensione: righe da 0, uscita = finestra intera 2608x1960 da (0,0)
    es g5-E9-r0 $S 2608 1960 GRBG "" "0 0x0a 0x00" "1 0x92 0x00" "1 0x94 0x00" \
        "1 0x95 0x07" "1 0x96 0xa8" "1 0x97 0x0a" "1 0x98 0x30"
    # E9b finestra piu' alta: 2020 righe da 0
    es g5-E9-h2020 $S 2608 2020 GRBG "" "0 0x0a 0x00" "0 0x0d 0x07" "0 0x0e 0xe4" "1 0x92 0x00" "1 0x94 0x00" \
        "1 0x95 0x07" "1 0x96 0xe4" "1 0x97 0x0a" "1 0x98 0x30"
    # E9c colonne: col 0, larghezza 2616, uscita 2616
    es g5-E9-c0 $S 2616 1944 GRBG "" "0 0x0c 0x00" "0 0x0f 0x0a" "0 0x10 0x38" "1 0x94 0x00" \
        "1 0x97 0x0a" "1 0x98 0x38"
fi

if [ "$CHI" = gc8034 ] || [ "$CHI" = tutti ]; then
    S=gc8034
    es g8-base $S 3264 2448 RGGB ""
    es g8-E1-x8 $S 3264 2448 RGGB g8-base "0 0x94 8"
    es g8-E1-y9 $S 3264 2448 RGGB g8-base "0 0x92 9"
    # E7 mirror (scuola A: offset fissi)
    es g8-E7-h $S 3264 2448 RGGB g8-base "0 0x17 0xc1"
    es g8-E7-v $S 3264 2448 RGGB g8-base "0 0x17 0xc2"
    es g8-E7-hv $S 3264 2448 RGGB g8-base "0 0x17 0xc3"
    # E8 byte alto del crop: uscita 3264x2176, y 8 contro y 264
    LAB_CTRL=vertical_blanking=328 es g8-E8-y8 $S 3264 2176 RGGB "" "0 0x95 0x08" "0 0x96 0x80"
    LAB_CTRL=vertical_blanking=328 es g8-E8-y264 $S 3264 2176 RGGB g8-E8-y8 "0 0x91 0x01" "0 0x92 0x08" "0 0x95 0x08" "0 0x96 0x80"
    # E5 finestra analogica ridotta: 1200 righe al centro (row 58+624, altezza 1216)
    LAB_CTRL=vertical_blanking=1300 es g8-E5-1200 $S 3264 1200 RGGB "" "0 0x09 0x02" "0 0x0a 0xaa" "0 0x0d 0x04" "0 0x0e 0xc0" \
        "0 0x95 0x04" "0 0x96 0xb0"
    # E6 binning: solo ISP + crop + uscita + LWC (PLL e MIPI invariati)
    B8=("0 0x66 0x2c" "0 0x80 0x10" "0 0xad 0x30" "0 0xbc 0x49"
        "0 0x92 0x04" "0 0x94 0x05" "0 0x95 0x04" "0 0x96 0xc8" "0 0x97 0x06" "0 0x98 0x60"
        "3 0x12 0xf8" "3 0x13 0x07")
    LAB_CTRL=vertical_blanking=1280 es g8-E6-A $S 1632 1224 RGGB "" "${B8[@]}"
    LAB_CTRL=vertical_blanking=1280 es g8-E6-B $S 1632 1224 RGGB "" "${B8[@]}" "0 0xfc 0xee" "3 0x03 0x9a" "3 0x22 0x06"
    LAB_CTRL=vertical_blanking=1280 es g8-E6-C $S 1632 1224 RGGB "" "${B8[@]}" "0 0xad 0x00"
    # E9 righe da 0, uscita = finestra 3284x2464 da (0,0); poi 2522 righe
    es g8-E9-r0 $S 3280 2464 RGGB "" "0 0x0a 0x00" "0 0x92 0x00" "0 0x94 0x00" \
        "0 0x95 0x09" "0 0x96 0xa0" "0 0x97 0x0c" "0 0x98 0xd0" "3 0x12 0x04" "3 0x13 0x10"
    es g8-E9-h2522 $S 3280 2522 RGGB "" "0 0x0a 0x00" "0 0x0d 0x09" "0 0x0e 0xda" "0 0x92 0x00" "0 0x94 0x00" \
        "0 0x95 0x09" "0 0x96 0xda" "0 0x97 0x0c" "0 0x98 0xd0" "3 0x12 0x04" "3 0x13 0x10"
fi

echo; echo "Risultati in $D"

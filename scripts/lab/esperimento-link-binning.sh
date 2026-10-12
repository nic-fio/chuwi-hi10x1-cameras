#!/bin/bash
# esperimento-link-binning.sh — misura la frequenza del collegamento MIPI del
# GC5035 con il PLL della tabella binning del produttore (12/10/2026).
#
#   sudo scripts/lab/esperimento-link-binning.sh A|B [CARTELLA]
#
# Richiede il driver DA LABORATORIO caricato (patches/wip/lab/gc5035.ko).
#
# Idea: una riga di uscita deve uscire sul collegamento entro il periodo di
# riga. Il tempo per riga sul collegamento e' larghezza * 10 bit / (2 lane *
# 2 * f) piu' un tempo fisso t0 (pacchetti corti, LP <-> HS).
#  A: PLL normale (f = 422,4 MHz nota), uscita 2592 pixel, riga accorciata
#     col registro P0 0x05/06 finche' il flusso si rompe -> t0. Al primo
#     guasto si riprova con uscita 2000: se va, il limite era il collegamento
#     e non la lettura della matrice.
#  B: PLL e registri MIPI (pagina 3) della tabella binning, lettura piena
#     (niente 0x33, niente T0), riga normale (17,28 us), uscita allargata
#     finche' il flusso si rompe -> f = larghezza * 10 / (4 * (riga - t0)).
set -u
FASE=$1
D=${2:-$(dirname "$0")/../../data/link-binning-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$D"
L=$(dirname "$0")/lab-cattura.sh
H=480          # righe di uscita: bastano, il periodo di riga non cambia
N=30           # fotogrammi per prova

# uscita: pagina 1, 0x95/96 altezza, 0x97/98 larghezza (16 bit, alto prima)
uscita() { # larghezza altezza
    printf '1 0x95 %d\n1 0x96 %d\n1 0x97 %d\n1 0x98 %d\n' \
        $(($2 >> 8)) $(($2 & 255)) $(($1 >> 8)) $(($1 & 255))
}
riga() { # lunghezza di riga in unita' del registro (730 = 17,28 us)
    printf '0 0x05 %d\n0 0x06 %d\n' $(($1 >> 8)) $(($1 & 255))
}
pll_binning() {
    printf '0 0xf5 0xe4\n0 0xf8 0x49\n0 0xf9 0x12\n0 0xfa 0x01\n'
    printf '3 0x01 0x87\n3 0x02 0x58\n3 0x22 0x03\n3 0x26 0x06\n'
    printf '3 0x29 0x03\n3 0x2b 0x06\n3 0xf7 0x11\n'
}

prova() { # nome larghezza [scritture...] su stdin
    local nome=$1 w=$2 f=$D/$1
    cat > $f.regs
    "$L" gc5035 $w ${HH:-$H} ${CODICE:-GRBG} $N $f $f.regs > $f.log 2>&1
    local attesi=$(sed -n 's/.*(attesi \([0-9]*\)).*/\1/p' $f.log)
    local avuti=$(stat -c%s $f.raw 2>/dev/null || echo 0)
    local nts=$(grep -c . <(sed -n '/^timestamp:/,$p' $f.txt | sed 1d | grep -E '^[0-9.]+$') )
    local err=$(grep -ciE 'error|csi' $f.ts 2>/dev/null)
    echo "$nome larghezza=$w fotogrammi=$nts/$N byte=$avuti/$attesi errori=$err" | tee -a $D/riepilogo.txt
    rm -f $f.raw
}

case $FASE in
A)
    for r in 730 720 710 700 690 680 670 660 650 640 630 620 610 600; do
        { uscita 2592 $H; riga $r; } | prova A-riga$r 2592
        if ! tail -1 $D/riepilogo.txt | grep -q "fotogrammi=$N/$N"; then
            { uscita 2000 $H; riga $r; } | prova A-riga$r-2000 2000
            break
        fi
    done ;;
B)
    for w in 1000 1100 1200 1300 1400 1500 1600 1800 2000 2200 2400 2592; do
        { pll_binning; uscita $w $H; } | prova B-larg$w $w
    done ;;
C)
    # controprova: ogni prova al limite e' seguita da una che deve andare,
    # cosi' un guasto rimasto dalla prova prima si vede
    uscita 2592 $H | prova C-normale-inizio 2592
    for w in 1000 1020 1040 1060 1080 1100 1120; do
        { pll_binning; uscita $w $H; } | prova C-larg$w $w
        { pll_binning; uscita 1000 $H; } | prova C-dopo$w 1000
    done
    uscita 2592 $H | prova C-normale-fine 2592 ;;
E)
    # la fase C ha mostrato che dopo un guasto col PLL binning anche le prove
    # che andavano falliscono, finche' non si cattura col PLL normale: ogni
    # prova parte quindi da una cattura normale. Salita e poi discesa.
    for w in 960 980 1000 1020 1040 1060 1080 1100 1140 1200 1300 \
             1200 1140 1100 1080 1060 1040 1020 1000 980 960; do
        uscita 2592 $H | prova E-reset-$w-$RANDOM 2592
        { pll_binning; uscita $w $H; } | prova E-larg$w-$RANDOM $w
    done ;;
F|G)
    # Metodo della pendenza: la soglia di larghezza cresce con la riga di
    # 4 * f / 10 pixel per microsecondo, qualunque sia il tempo fisso t0.
    # F: PLL binning, soglia di larghezza per piu' lunghezze di riga.
    # G: verifica del metodo col PLL normale (f nota, 422,4 MHz): soglia di
    #    riga per piu' larghezze. Ogni prova parte da una cattura normale.
    # Ricerca per bisezione; il periodo misurato da' la riga vera.
    va() { tail -1 $D/riepilogo.txt | grep -q "fotogrammi=$N/$N byte=\([0-9]*\)/\1 "; }
    periodo() { sed -n '/^timestamp:/,$p' $D/$1.txt | sed 1d | grep -E '^[0-9.]+$' |
        python3 -I -c 'import sys,statistics; t=[float(x) for x in sys.stdin]; print("%.4f" % (statistics.median([b-a for a,b in zip(t,t[1:])])*1e3))'; }
    if [ $FASE = F ]; then
        for r in 730 910 1090 1270 1460; do
            lo=600 hi=2600     # lo va (da verificare), hi no
            while [ $((hi - lo)) -gt 8 ]; do
                w=$(( (lo + hi) / 4 * 2 ))
                uscita 2592 $H | prova F-reset-$r-$w 2592
                { pll_binning; riga $r; uscita $w $H; } | prova F-riga$r-larg$w $w
                if va; then lo=$w; ok=F-riga$r-larg$w; else hi=$w; fi
            done
            echo "SOGLIA F riga=$r larghezza_va=$lo non_va=$hi periodo_ms=$(periodo $ok)" | tee -a $D/riepilogo.txt
        done
    else
        for w in 2592 2400 2200 2000 1800; do
            lo=740 hi=400      # lo va (riga lunga), hi no (riga corta)
            while [ $((lo - hi)) -gt 2 ]; do
                r=$(( (lo + hi) / 2 ))
                uscita 2592 $H | prova G-reset-$w-$r 2592
                { riga $r; uscita $w $H; } | prova G-larg$w-riga$r $w
                if va; then lo=$r; ok=G-larg$w-riga$r; else hi=$r; fi
            done
            echo "SOGLIA G larghezza=$w riga_va=$lo non_va=$hi periodo_ms=$(periodo $ok)" | tee -a $D/riepilogo.txt
        done
    fi ;;
H)
    # Binning completo del produttore (binning-produttore.regs, 39 scritture
    # dalla tabella Intel), uscita 972 righe. Come G: per ogni larghezza la
    # riga piu' corta che regge, per bisezione.
    va() { tail -1 $D/riepilogo.txt | grep -q "fotogrammi=$N/$N byte=\([0-9]*\)/\1 "; }
    periodo() { sed -n '/^timestamp:/,$p' $D/$1.txt | sed 1d | grep -E '^[0-9.]+$' |
        python3 -I -c 'import sys,statistics; t=[float(x) for x in sys.stdin]; print("%.4f" % (statistics.median([b-a for a,b in zip(t,t[1:])])*1e3))'; }
    B=$(dirname "$0")/binning-produttore.regs
    for w in 1296 1100 900 700; do
        lo=730 hi=200
        while [ $((lo - hi)) -gt 2 ]; do
            r=$(( (lo + hi) / 2 ))
            uscita 2592 $H | prova H-reset-$w-$r 2592
            { grep -v '^#' $B; riga $r; printf '1 0x95 3\n1 0x96 0xcc\n'
              printf '1 0x97 %d\n1 0x98 %d\n' $((w >> 8)) $((w & 255)); } |
                HH=972 CODICE=RGGB prova H-larg$w-riga$r $w
            if va; then lo=$r; ok=H-larg$w-riga$r; else hi=$r; fi
        done
        echo "SOGLIA H larghezza=$w riga_va=$lo non_va=$hi periodo_ms=$(periodo $ok)" | tee -a $D/riepilogo.txt
    done ;;
D)
    # taratura fine fra 720 (va) e 710 (non va), con controllo dopo ogni prova
    for r in 718 716 714 712; do
        { uscita 2592 $H; riga $r; } | prova D-riga$r 2592
        uscita 2592 $H | prova D-dopo$r 2592
    done ;;
esac
echo "cartella: $D"

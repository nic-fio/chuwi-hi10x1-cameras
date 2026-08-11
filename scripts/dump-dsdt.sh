#!/bin/bash
# dump-dsdt.sh — estrae e decompila la DSDT, poi isola i nodi camera.
#
# Progetto INTEL-CAMERA — CHUWI Hi10 X1
#
# La DSDT e' la SPECIFICA da cui si scrivono i driver: contiene numero di lane
# MIPI, link frequency, sorgente di clock, indirizzi I2C e funzioni GPIO dei
# due sensori. Serve per:
#   - i valori delle voci ipu_supported_sensors[] in ipu-bridge.c  (Serie 3)
#   - capire se serve un quirk int3472                             (Serie 4)
#   - scrivere i due driver sensore                                (Serie 1 e 2)
#
# Uso:  sudo ./scripts/dump-dsdt.sh

set -eu

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$PROJECT_DIR/data/dsdt"
mkdir -p "$OUT"

if [ "$(id -u)" -ne 0 ]; then
    echo "Serve root: /sys/firmware/acpi/tables/DSDT e' leggibile solo da root."
    echo "Rilancia con: sudo $0"
    exit 1
fi

command -v iasl >/dev/null || { echo "iasl mancante: apt install acpica-tools"; exit 1; }

echo "[1/3] copia della tabella DSDT"
cp /sys/firmware/acpi/tables/DSDT "$OUT/dsdt.aml"

echo "[2/3] decompilazione"
iasl -d "$OUT/dsdt.aml" >/dev/null 2>&1 || true
[ -f "$OUT/dsdt.dsl" ] || { echo "iasl non ha prodotto dsdt.dsl"; exit 1; }

echo "[3/3] estrazione dei nodi camera"
# LNK0 = GCTI8034 (posteriore), LNK1 = GCTI5035 (frontale)
# DSC0/DSC1 = INT3472 discreti che alimentano i due sensori
{
    echo "############################################################"
    echo "# Nodi camera estratti dalla DSDT — CHUWI Hi10 X1"
    echo "#"
    echo "#   LNK0 -> GCTI8034 = GalaxyCore GC8034 (posteriore, 8 MP)"
    echo "#   LNK1 -> GCTI5035 = GalaxyCore GC5035 (frontale,  5 MP)"
    echo "#   DSC0/DSC1 -> INT3472 discreti (clock/GPIO/regolatori)"
    echo "#"
    echo "# Cosa cercare:"
    echo "#   SSDB    -> lane MIPI, link frequency, orientamento, porta CSI-2"
    echo "#   _DSD    -> proprieta' fwnode (clock-frequency, rotation, ...)"
    echo "#   _CRS    -> indirizzo I2C e bus, risorse GPIO"
    echo "#   _DSM    -> tipi di funzione GPIO usati da int3472"
    echo "############################################################"
    echo
    for node in LNK0 LNK1 LNK2 DSC0 DSC1 CAM0 CAM1 PMIC; do
        echo
        echo "===================== Device $node ====================="
        # Estrae il blocco Device(<n>) { ... } contando le graffe.
        # 'opened' e' necessario: la riga "Device (X)" precede la graffa
        # aperta, quindi senza di esso la condizione di chiusura scatterebbe
        # subito e verrebbe stampata solo l'intestazione.
        awk -v n="$node" '
            !d && $0 ~ ("Device \\(" n "\\)[[:space:]]*$") { d=1; depth=0; opened=0 }
            d {
                print
                depth += gsub(/\{/, "{")
                depth -= gsub(/\}/, "}")
                if (depth > 0) opened=1
                if (opened && depth <= 0) { d=0; found=1 }
            }
            END { exit(found ? 0 : 1) }
        ' "$OUT/dsdt.dsl" || echo "(nodo $node non presente in questa DSDT)"
    done
} > "$OUT/camera-nodes.dsl" 2>&1

# Estrazione mirata dei buffer SSDB, che contengono i parametri CSI-2
grep -n -A40 'SSDB' "$OUT/dsdt.dsl" > "$OUT/ssdb-raw.txt" 2>&1 || true

chown -R "${SUDO_USER:-root}:" "$OUT" 2>/dev/null || true

echo
echo "Fatto. Prodotti:"
echo "  $OUT/dsdt.aml          tabella grezza"
echo "  $OUT/dsdt.dsl          DSDT decompilata completa"
echo "  $OUT/camera-nodes.dsl  solo i nodi camera  <-- leggere questo"
echo "  $OUT/ssdb-raw.txt      buffer SSDB grezzi"

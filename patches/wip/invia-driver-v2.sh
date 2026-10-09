#!/usr/bin/env bash
#
# Spedisce la v2 dei driver GC5035/GC8034: lettera + 5 patch, in risposta
# alla lettera della v1 (stesso thread), agli stessi destinatari della v1.
#
#   ./invia-driver-v2.sh --prova    mostra cosa spedirebbe, NON spedisce
#   ./invia-driver-v2.sh            chiede conferma e spedisce
#
# Deciso con Nic il 9/10 sera: invio lunedi' 12/10 mattina. Prima di
# lanciarlo (lista in docs/14, «Lunedi' mattina»): commenti nuovi sul thread
# della v1 integrati, prova completa rifatta sui moduli finali, output di
# v4l2-compliance al posto del segnaposto nella lettera.
#
# La password per le app di Google NON e' salvata da nessuna parte: la
# chiede git send-email al momento dell'invio.

set -euo pipefail

CARTELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/upstream/driver-v2-invio"
PATCH=(
	"$CARTELLA/v2-0000-cover-letter.patch"
	"$CARTELLA/v2-0001-media-i2c-Add-GC5035-image-sensor-driver.patch"
	"$CARTELLA/v2-0002-media-i2c-Add-GC8034-image-sensor-driver.patch"
	"$CARTELLA/v2-0003-media-ipu-bridge-Add-GalaxyCore-GC5035-and-GC8034.patch"
	"$CARTELLA/v2-0004-media-i2c-gc5035-Add-crop-support.patch"
	"$CARTELLA/v2-0005-media-i2c-gc8034-Add-crop-support.patch"
)

# Lettera della v1 (patchwork, serie 31804)
V1="<20261009072733.39877-1-nicfio@gmail.com>"

PROVA=0
if [[ "${1:-}" == "--prova" || "${1:-}" == "--dry-run" ]]; then
	PROVA=1
fi

for f in "${PATCH[@]}"; do
	[[ -f "$f" ]] || { echo "ERRORE: manca $f" >&2; exit 1; }
done
if grep -n 'DA COMPLETARE\|TODO\|\*\*\* SUBJECT\|\*\*\* BLURB' "${PATCH[@]}"; then
	if [[ "$PROVA" == "1" ]]; then
		echo "(prova: segnaposto ancora presenti, l'invio vero si rifiuterebbe)"
	else
		echo "ERRORE: segnaposto ancora nel testo, non spedisco." >&2
		exit 1
	fi
fi

# --- Destinatari -------------------------------------------------------
# Gli stessi della v1 (docs/13, «Spedita»): To Laurent, che ha chiesto la
# v2, e Sakari (sensori); Cc Mauro, Hans Verkuil, Dan Scally (Reviewed-by
# sulla 3/5), Hans de Goede (IPU6, ipu-bridge), linux-media, linux-kernel.
A=(
	"Laurent Pinchart <laurent.pinchart@ideasonboard.com>"
	"Sakari Ailus <sakari.ailus@linux.intel.com>"
)
CC=(
	"Mauro Carvalho Chehab <mchehab@kernel.org>"
	"Hans Verkuil <hverkuil@kernel.org>"
	"Dan Scally <dan.scally@ideasonboard.com>"
	"Hans de Goede <hansg@kernel.org>"
	"linux-media@vger.kernel.org"
	"linux-kernel@vger.kernel.org"
)

ARGS=(--suppress-cc=all --thread --no-chain-reply-to --in-reply-to="$V1"
      --8bit-encoding=UTF-8 --transfer-encoding=8bit)
for a in "${A[@]}"; do ARGS+=(--to="$a"); done
for c in "${CC[@]}"; do ARGS+=(--cc="$c"); done

if [[ "$PROVA" == "1" ]]; then
	git send-email --dry-run --confirm=never "${ARGS[@]}" "${PATCH[@]}"
	echo
	echo "(prova: non ho spedito niente)"
	exit 0
fi

git send-email --dry-run --confirm=never "${ARGS[@]}" "${PATCH[@]}"
echo
read -r -p "Spedisco la v2 a questi destinatari? Scrivi SI per confermare: " RISPOSTA
if [[ "$RISPOSTA" != "SI" ]]; then
	echo "Annullato, non ho spedito niente."
	exit 1
fi

git send-email "${ARGS[@]}" "${PATCH[@]}"

echo
echo "Fatto. Ora: Message-ID della lettera nel diario, controllo su lore e patchwork."

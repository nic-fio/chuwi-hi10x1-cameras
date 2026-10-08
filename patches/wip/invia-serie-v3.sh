#!/usr/bin/env bash
#
# Spedisce la serie v3 (subdev_open/EXT_CTRLS): lettera + 2 patch, thread
# nuovo, le patch in risposta alla lettera.
#
#   ./invia-serie-v3.sh --prova    mostra cosa spedirebbe, NON spedisce
#   ./invia-serie-v3.sh            chiede conferma e spedisce
#
# Regola decisa con Nic il 04/10 (invio poi anticipato all'08/10): si spedisce solo se Sakari non ha dato
# segni di vita entro venerdi' 09/10. Prima di lanciarlo: Gmail, lore e
# patchwork senza risposte nuove (vedi docs/12-recensione-serie-ipu6.md).
#
# La password per le app di Google NON e' salvata da nessuna parte: la
# chiede git send-email al momento dell'invio.

set -euo pipefail

CARTELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERIE="$CARTELLA/subdev-fix-v3"
PATCH=(
	"$SERIE/v3-0000-cover-letter.patch"
	"$SERIE/v3-0001-media-v4l2-subdev-Fix-NULL-pointer-dereference-in.patch"
	"$SERIE/v3-0002-media-v4l2-subdev-Fix-NULL-pointer-dereference-in.patch"
)

PROVA=0
if [[ "${1:-}" == "--prova" || "${1:-}" == "--dry-run" ]]; then
	PROVA=1
fi

for f in "${PATCH[@]}"; do
	[[ -f "$f" ]] || { echo "ERRORE: manca $f" >&2; exit 1; }
done
if grep -n 'DA COMPLETARE\|TODO' "${PATCH[@]}"; then
	echo "ERRORE: segnaposto ancora nel testo, non spedisco." >&2
	exit 1
fi

# --- Destinatari -------------------------------------------------------
# To: Sakari, che ha recensito la v2 e ha annunciato la risposta sulla
#     patch del framework.
# Cc: Mauro (manutentore, get_maintainer.pl); Hans Verkuil (autore del
#     commit in Fixes della 2/2, era in Cc sulla v2); Laurent Pinchart
#     (autore del commit in Fixes della 1/2, e la sua obiezione alla patch
#     di Nguyen e' il motivo della v3); Nguyen Ngoc Thang (la sua patch e'
#     citata in [1]); linux-media, linux-kernel.
# Fuori: Antti Laakso (era in Cc per le patch ipu6, tolte dalla v3);
#     "Sergey Lebedev" (artefatto di get_maintainer.pl sul clone parziale);
#     stable@ e syzbot (i tag nei trailer bastano: --suppress-cc=all).
A="Sakari Ailus <sakari.ailus@linux.intel.com>"
CC=(
	"Mauro Carvalho Chehab <mchehab@kernel.org>"
	"Hans Verkuil <hverkuil@kernel.org>"
	"Laurent Pinchart <laurent.pinchart@ideasonboard.com>"
	"Nguyen Ngoc Thang <ngocthang2710.1999@gmail.com>"
	"linux-media@vger.kernel.org"
	"linux-kernel@vger.kernel.org"
)

ARGS=(--to="$A" --suppress-cc=all --thread --no-chain-reply-to
      --8bit-encoding=UTF-8 --transfer-encoding=8bit)
for c in "${CC[@]}"; do ARGS+=(--cc="$c"); done

if [[ "$PROVA" == "1" ]]; then
	git send-email --dry-run --confirm=never "${ARGS[@]}" "${PATCH[@]}"
	echo
	echo "(prova: non ho spedito niente)"
	exit 0
fi

git send-email --dry-run --confirm=never "${ARGS[@]}" "${PATCH[@]}"
echo
read -r -p "Spedisco la serie v3 a questi destinatari? Scrivi SI per confermare: " RISPOSTA
if [[ "$RISPOSTA" != "SI" ]]; then
	echo "Annullato, non ho spedito niente."
	exit 1
fi

# sendemail.confirm=always (config di git): chiede ancora conferma per
# ogni messaggio. La password la chiede send-email.
git send-email "${ARGS[@]}" "${PATCH[@]}"

echo
echo "Fatto. Ora: Message-ID della lettera nel diario, controllo su lore."

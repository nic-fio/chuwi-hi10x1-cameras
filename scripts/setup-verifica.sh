#!/bin/bash
# setup-verifica.sh — installa gli strumenti con cui si controllano le patch.
#
# Progetto INTEL-CAMERA.
#
# Sono i controlli che i revisori di linux-media eseguono prima di leggere il
# codice. Farli girare qui significa non farsi rimandare indietro la serie per
# motivi meccanici.
#
#   checkpatch      gia' nel kernel, non serve installare nulla
#   dt_binding_check dtschema + yamllint      valida i binding YAML
#   sparse          analisi statica            richiede una versione recente
#
# Idempotente: rilanciarlo non rompe niente.

set -euo pipefail

VENV="$HOME/.local/share/dtschema-venv"
SPARSE_SRC="$HOME/.local/src/sparse"
LINUX="${LINUX:-$HOME/linux}"

echo "== pacchetti di sistema =="
# yamllint: usato da dt_binding_check
# swig, python3-dev, libfdt-dev: servono a compilare pylibfdt, dipendenza di
#   dtschema, che altrimenti fallisce con "Failed building wheel for pylibfdt"
sudo apt-get install -y yamllint swig python3-dev libfdt-dev \
	device-tree-compiler build-essential git

echo
echo "== dtschema in un venv dedicato =="
# In venv e non di sistema: Debian 13 e' PEP 668 (externally-managed), e un
# pip install di sistema andrebbe forzato con --break-system-packages.
[ -d "$VENV" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q --upgrade dtschema
"$VENV/bin/dt-validate" --version

echo
echo "== sparse dal sorgente =="
# La sparse di Debian (0.6.4) non conosce __typeof_unqual__ e il kernel la
# rifiuta: scripts/checker-valid.sh ritorna 0 e il make ignora C=1 con un
# warning facile da non notare. Serve almeno la 0.6.5.
mkdir -p "$(dirname "$SPARSE_SRC")"
if [ -d "$SPARSE_SRC/.git" ]; then
	git -C "$SPARSE_SRC" pull -q --ff-only || true
else
	git clone -q --depth 1 \
		https://git.kernel.org/pub/scm/devel/sparse/sparse.git "$SPARSE_SRC"
fi
nice -n 19 make -C "$SPARSE_SRC" -j"$(nproc)" >/dev/null
"$SPARSE_SRC/sparse" --version

echo
echo "== verifica che il kernel accetti questa sparse =="
if [ -x "$LINUX/scripts/checker-valid.sh" ]; then
	res=$("$LINUX/scripts/checker-valid.sh" "$SPARSE_SRC/sparse" -m64)
	[ "$res" = "1" ] && echo "  ok" || { echo "  RIFIUTATA"; exit 1; }
else
	echo "  saltata: $LINUX non e' un albero kernel"
fi

cat <<EOF

== come usarli ==

  cd $LINUX

  # stile, sui file e sulle patch
  ./scripts/checkpatch.pl --strict --file --max-line-length=80 \\
      drivers/media/i2c/gc5035.c
  ./scripts/checkpatch.pl --strict --max-line-length=80 <patch>

  # binding YAML
  PATH="$VENV/bin:\$PATH" make dt_binding_check DT_SCHEMA_FILES=galaxycore

  # analisi statica
  make C=1 W=1 CHECK=$SPARSE_SRC/sparse drivers/media/i2c/gc5035.o

L'unico errore di checkpatch che deve restare e' "Missing Signed-off-by":
la firma DCO la mette chi invia, con nome e cognome veri.
EOF

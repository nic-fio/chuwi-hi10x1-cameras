#!/bin/bash
# build-tablet-debug.sh — sul server, i due kernel di debug per la prova
# della serie v3 (subdev_open/EXT_CTRLS) sul tablet.
#
#   base = media next + driver gc5035/gc8034 + int3472   (difetto presente)
#   v3   = base + le due patch della serie v3            (difetto corretto)
#
# Stessa config per entrambi: cambia solo v4l2-subdev.c, quindi il secondo
# e' una ricompilazione incrementale. LOCALVERSION_AUTO aggiunge -g<sha>,
# cosi' i due kernel hanno nomi (e /lib/modules) diversi sul tablet.
#
# Uso, sul server:  ./build-tablet-debug.sh
# Prodotti:         $OUT/{base,v3}/{bzImage,modules.tar.zst,config,versione}

set -eu

SRC=/media/INTEL-CAMERA/sorgenti/media-tablet
TOP=/media/INTEL-CAMERA/tablet
OUT=$TOP/out
export LSMOD_FILE=$TOP/patch/lsmod-tablet.txt

[ -r "$LSMOD_FILE" ] || { echo "manca $LSMOD_FILE"; exit 1; }
command -v gcc >/dev/null || { echo "gcc assente: installare prima gli strumenti"; exit 1; }

cd "$SRC"
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
    { echo "worktree sporco"; exit 1; }

raccogli() {    # $1 = base | v3
    local d=$OUT/$1 rel
    rel=$(make -s kernelrelease)
    rm -rf "$d" && mkdir -p "$d/mod"
    cp arch/x86/boot/bzImage "$d/bzImage"
    cp .config "$d/config"
    nice -n 15 make -s INSTALL_MOD_PATH="$d/mod" modules_install
    tar -C "$d/mod" -I zstd -cf "$d/modules.tar.zst" lib
    rm -rf "$d/mod"
    { echo "$rel"; git log --oneline -1; } > "$d/versione"
    echo "== $1: $rel, $(du -h "$d/bzImage" | cut -f1)"
}

git checkout -q tablet-base
"$TOP/scripts/build-kernel.sh" --debug "$SRC"
raccogli base

git checkout -q tablet-v3
nice -n 15 make -j"$(nproc)"
raccogli v3

git checkout -q tablet-base
echo "Fatto: $OUT"

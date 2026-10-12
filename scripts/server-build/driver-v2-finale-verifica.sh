#!/bin/bash
# Verifica meccanica della serie driver-v2 DEFINITIVA (quella in
# upstream/driver-v2-invio), commit per commit. Uso: ... TOP
# 12/10: la verifica del 9/10 alle 17:31 era su una versione intermedia.
# Gira dentro localhost/intelcam-build con /media/INTEL-CAMERA montato.
export LC_ALL=C
W=/media/INTEL-CAMERA/sorgenti/driver-v2
O=/media/INTEL-CAMERA/sorgenti/driver-v2-build
L=$O/log
cd $W || exit 1
git config --global --add safe.directory "*"
TOP=$(git rev-parse "${1:?serve il commit in cima}")
PRIMA=$(git rev-parse HEAD)
I=/media/INTEL-CAMERA/tablet/v2-invio
BASE=$(git merge-base $TOP next)
if [ ! -f $O/.config ]; then
    mkdir -p $O
    make -s O=$O allmodconfig || exit 1
fi
mkdir -p $L
grep -E "^CONFIG_(VIDEO_V4L2_SUBDEV_API|IPU_BRIDGE|VIDEO_GC5035|VIDEO_GC8034)=" $O/.config
nice make -j18 O=$O W=1 prepare modules_prepare > $L/prepare.log 2>&1 || { echo prepare fallito; tail $L/prepare.log; exit 1; }
OBJ="drivers/media/i2c/gc5035.o drivers/media/i2c/gc8034.o drivers/media/pci/intel/ipu-bridge.o"
for c in $(git rev-list --reverse $BASE..$TOP); do
    git checkout -q --detach $c
    s=$(git log -1 --format=%h $c)
    make -s O=$O olddefconfig
    $W/scripts/config --file $O/.config -m VIDEO_GC5035 -m VIDEO_GC8034
    make -s O=$O olddefconfig
    objs=""; for o in $OBJ; do [ -f ${o%.o}.c ] && objs="$objs $o"; done
    for o in $objs; do touch ${o%.o}.c; done
    make -j18 O=$O W=1 C=1 $objs > $L/$s-sparse.log 2>&1; r1=$?
    for o in $objs; do touch ${o%.o}.c; done
    make -j18 O=$O W=1 C=1 CHECK="smatch -p=kernel" $objs > $L/$s-smatch.log 2>&1; r2=$?
    echo "$s $(git log -1 --format=%s $c)"
    echo "   oggetti:$objs  (CC [M]: $(grep -c "CC \[M\]" $L/$s-sparse.log), CHECK: $(grep -c "CHECK " $L/$s-sparse.log))"
    echo "   W=1+sparse exit=$r1 warning=$(grep -c "warning:" $L/$s-sparse.log) error=$(grep -c "error:" $L/$s-sparse.log)"
    echo "   smatch     exit=$r2 warn=$(grep -cE "warn:|error:" $L/$s-smatch.log)"
done
git checkout -q --detach $TOP
echo "== patch generate = patch da spedire"
rm -rf $O/cmp && git format-patch -q -o $O/cmp $BASE..$TOP
for p in $O/cmp/*.patch; do
    q=$(ls $I/v2-$(basename $p | cut -c1-4)-*.patch)
    diff <(sed -e '1d' -e '/^-- $/,$d' -e '/^Subject:/s/\[PATCH[^]]*\]//' $p) <(sed -e '1d' -e '/^-- $/,$d' -e '/^Subject:/s/\[PATCH[^]]*\]//' $q) > /dev/null && echo "$(basename $p): identica" || echo "$(basename $p): DIVERSA da $(basename $q)"
done
echo "== get_maintainer"
./scripts/get_maintainer.pl --no-rolestats $I/v2-000[1-5]-*.patch
echo "== checkpatch"
rm -rf $O/out && git format-patch -q -o $O/out $BASE..$TOP
for p in $O/out/*.patch; do
    echo "$(basename $p): $(./scripts/checkpatch.pl --strict --codespell --max-line-length=80 -q $p | grep -E "^(ERROR|WARNING|CHECK)" | sort | uniq -c | tr "\n" " ")"
done
echo "== coccinelle"
printf "#include <linux/slab.h>\nvoid f(int *p){ if (p) kfree(p); }\n" > /tmp/t.c
spatch -D report --very-quiet --no-show-diff --sp-file scripts/coccinelle/free/ifnullfree.cocci /tmp/t.c 2>&1 | grep -q "NULL check" && echo "controprova: ok" || echo "controprova: FALLITA"
n=0; e=0
for c in $(find scripts/coccinelle -name "*.cocci"); do
    n=$((n+1))
    for f in drivers/media/i2c/gc5035.c drivers/media/i2c/gc8034.c drivers/media/pci/intel/ipu-bridge.c; do
        out=$(spatch -D report --very-quiet --no-show-diff -I include -I arch/x86/include -I include/uapi --sp-file $c $f 2>&1) || { e=$((e+1)); echo "non applicabile: $(basename $c) $f: $(echo "$out" | tail -1)"; continue; }
        [ -n "$out" ] && echo "$(basename $c) $f: $out"
    done
done
echo "script=$n errori=$e"
git checkout -q --detach $PRIMA
echo FINE

#!/bin/sh
# Verifica meccanica della serie driver-v1, commit per commit.
# Gira dentro localhost/intelcam-build con /media/INTEL-CAMERA montato.
export LC_ALL=C
W=/media/INTEL-CAMERA/sorgenti/driver-v1
O=/media/INTEL-CAMERA/sorgenti/driver-v1-build
L=$O/log
cd $W || exit 1
git config --global --add safe.directory "*"
TOP=$(git rev-parse HEAD)
BASE=$(git merge-base HEAD next)
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
echo "== dt_binding_check"
for y in galaxycore,gc5035 galaxycore,gc8034; do
    make -s O=$O dt_binding_check DT_SCHEMA_FILES=media/i2c/$y.yaml > $L/dt-$y.log 2>&1
    echo "$y exit=$? righe=$(grep -vc "^\s*$" $L/dt-$y.log)"
done
echo FINE

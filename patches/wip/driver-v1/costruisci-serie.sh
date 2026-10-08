#!/bin/sh
# Ricostruisce da zero la serie driver-v1 (3 patch) sul worktree del server.
# Uso, dal tablet:  ./patches/wip/driver-v1/costruisci-serie.sh
# I commit NON hanno Signed-off-by: lo aggiunge Nicola dopo averli riletti
# (Documentation/process/coding-assistants.rst, punto 6).
set -e
D=$(cd "$(dirname "$0")" && pwd)
R=192.168.0.2
W=/media/INTEL-CAMERA/sorgenti/driver-v1
BASE=8e26d4c20
AUTORE="Nicola Fiorillo <nicfio@gmail.com>"
scp -q "$D/gc5035.c" "$D/gc8034.c" "$D/msg/"*.txt "$D/inserisci.py" $R:$W/../driver-v1-patch/
ssh $R "cd $W && set -e
P=../driver-v1-patch
git checkout -q -f -B driver-v1 $BASE
cp \$P/gc5035.c drivers/media/i2c/ && python3 \$P/inserisci.py gc5035
git add -A drivers/media/i2c MAINTAINERS && git commit -q --author='$AUTORE' -F \$P/1-gc5035.txt
cp \$P/gc8034.c drivers/media/i2c/ && python3 \$P/inserisci.py gc8034
git add -A drivers/media/i2c MAINTAINERS && git commit -q --author='$AUTORE' -F \$P/2-gc8034.txt
python3 \$P/inserisci.py ipu-bridge
git add drivers/media/pci/intel/ipu-bridge.c && git commit -q --author='$AUTORE' -F \$P/3-ipu-bridge.txt
git log --oneline $BASE..HEAD" 2>&1 | grep -v tput

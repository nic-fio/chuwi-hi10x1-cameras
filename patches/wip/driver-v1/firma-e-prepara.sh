#!/bin/sh
# Lo lancia Nicola, non l'assistente: il Signed-off-by è una dichiarazione
# personale (Documentation/process/coding-assistants.rst, "AI agents MUST NOT
# add Signed-off-by tags").
# Sul server: aggiunge il Signed-off-by di Nicola alle 3 patch, crea la cover
# da cover.txt, passa checkpatch e get_maintainer. Copia le mail in
# patches/wip/driver-v1/invio/ sul tablet.
# Uso, dal tablet:  ./patches/wip/driver-v1/firma-e-prepara.sh
set -e
D=$(cd "$(dirname "$0")" && pwd)
R=192.168.0.2
W=/media/INTEL-CAMERA/sorgenti/driver-v1
BASE=8e26d4c20
SERIE=7b3ed03b4
OUT=/media/INTEL-CAMERA/sorgenti/driver-v1-invio
IMG=localhost/intelcam-build

scp -q "$D/cover.txt" $R:$OUT.cover.txt
ssh $R "cd $W && set -e
git checkout -q -f -B driver-v1-invio $SERIE
git -c user.name='Nicola Fiorillo' -c user.email=nicfio@gmail.com \
	rebase -q --signoff $BASE
git config branch.driver-v1-invio.description \"\$(sed '1s/^Subject: \[PATCH 0\/3\] //' $OUT.cover.txt)\"
rm -rf $OUT && mkdir -p $OUT
git format-patch -q --cover-letter --cover-from-description=subject \
	--base=$BASE -o $OUT $BASE..HEAD
podman run --rm --network=host -v /media/INTEL-CAMERA:/media/INTEL-CAMERA \
	-w $W $IMG sh -c './scripts/checkpatch.pl --strict $OUT/000[1-3]-*.patch; \
	./scripts/get_maintainer.pl --norolestats $OUT/000[1-3]-*.patch' \
	> $OUT/controlli.txt 2>&1 || true
git log --format='%h %s' $BASE..HEAD
grep -h -A3 '^Assisted-by' $OUT/000[1-3]-*.patch" 2>&1 | grep -v tput
rm -rf "$D/invio" && mkdir -p "$D/invio"
scp -q "$R:$OUT/*" "$D/invio/"
echo
cat "$D/invio/controlli.txt"
echo
echo "Mail pronte in $D/invio/"

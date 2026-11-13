# INTEL-CAMERA
Patch upstream (linux-media) per le fotocamere del CHUWI Hi10 X1: IPU6,
sensori GalaxyCore GC5035/GC8034, ipu-bridge, int3472.

## Struttura
- docs/NN-*.md: diario numerato; docs/12 = discussioni in lista, docs/13-14 = driver
- patches/wip/: serie in lavorazione, lettere, risposte (*.txt) e script d'invio (invia-*.sh)
- LETTERA-v2.txt: lettera della serie driver v2 (un solo file, niente copie)
- scripts/, test/: prove su tablet e QEMU; upstream/, reference/: sorgenti esterni

## Invio mail
- Ogni invia-*.sh ha `--prova` (anteprima, non spedisce). Lo script vero lo lancia solo Nic.
- Prima di qualsiasi invio: leggere in docs/12 lo stato del thread (anche serie ritirate).
- Dopo l'invio: Message-ID e link lore nel diario.

## Convenzioni
- Commit e diario in italiano; mail e patch in inglese, testo approvato da Nic.
- Prove su media `next`, mai su kernel di distribuzione nei messaggi di commit.

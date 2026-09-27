# Run 3 del test della corsa (27/09/2026, circa 13:56-14:08 ora italiana)

**Il run da citare.** Stesso schema del run 2 con le tre correzioni
(tetto di ricreazione 100, pausa prima della riga di fase, riga completa
obbligatoria). Tutti e 10 gli avvii validi, codice d'uscita 0.

Kernel da media next: base `2dcdfb625c3b`, p1 `683e31f9fc1c` (solo 1/2),
v3 `f07d7e2563c7` (1/2 + 2/2). x86_64_defconfig + kvm_guest.config +
KASAN (generic, inline) + vimc; QEMU/KVM, 4 vCPU, 4 GB. Un avvio per
fase, 60 s ciascuna, 16 thread di lavoro + 1 thread che fa unbind/bind di
vimc ogni 1 ms o 30 ms. La `.config` usata e' nell'archivio.

| kernel | fase | oops nella funzione | oops/KASAN/WARNING totali | cicli unbind |
|---|---|---|---|---|
| base | open 1 ms | 116 in subdev_open | 116 | 11803 |
| base | open 30 ms | 116 in subdev_open | 116 | 788 |
| p1 | open 1 ms | 0 | 0 | 423 |
| p1 | open 30 ms | 0 | 0 | 291 |
| v3 | open 1 ms | 0 | 0 | 418 |
| v3 | open 30 ms | 0 | 0 | 297 |
| p1 | ioctl 1 ms | 116 in subdev_do_ioctl | 116 | 9976 |
| p1 | ioctl 30 ms | 116 in subdev_do_ioctl | 116 | 718 |
| v3 | ioctl 1 ms | 0 | 0 | 644 |
| v3 | ioctl 30 ms | 0 | 0 | 391 |

Tutti gli oops sono `KASAN: null-ptr-deref`. 116 per avvio = tetto del
test (16 thread + 100 ricreati): e' "thread uccisi", non "volte in cui la
corsa si presenta". Il conteggio dei thread uccisi visto dal programma
coincide in ogni avvio con gli oops contati nel log del kernel.

Kernel con la patch, fasi open (p1+v3): ~7,96 milioni di open riuscite,
~1,14 milioni respinte con ENODEV mentre vimc veniva staccato.
Kernel con la serie, fasi ioctl (v3): ~880 milioni di VIDIOC_G_EXT_CTRLS
riusciti, ~23 mila respinti con ENODEV.

Nota: i cicli di unbind sono molti di piu' nei kernel che crashano
perche' li' i thread muoiono e il sistema e' meno carico; non e' un
confronto di prestazioni.

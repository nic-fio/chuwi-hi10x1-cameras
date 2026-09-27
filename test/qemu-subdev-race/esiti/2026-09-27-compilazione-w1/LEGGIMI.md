# Compilazione con W=1 della serie v3 (27/09/2026, 07:55-07:56 UTC)

Albero: media next `2dcdfb625c3b`, `.config` da `make allmodconfig`
(`/media/INTEL-CAMERA/build/next`, `VIDEO_V4L2_SUBDEV_API=y`).
Comando: `nice -n 19 make -j12 O=/media/INTEL-CAMERA/build/next W=1 drivers/media/v4l2-core/`.

| log | codice compilato | esito |
|---|---|---|
| `build-v3s.log` | serie intera, commit `f07d7e256` (sopra `683e31f9f`) | 0 avvisi, 0 errori |
| `build-1su2.log` | sola 1/2: `v4l2-subdev.c` di `683e31f9f` | 0 avvisi, 0 errori |

Sono gli stessi commit dei kernel del run 3. I commit della serie da
spedire (`06a38bc63`, `a41d57565`) differiscono da questi solo nei
messaggi: `git diff` vuoto su tutto l'albero, verificato il 27/09.

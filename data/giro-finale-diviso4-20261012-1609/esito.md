# Giro finale su driver-v2-diviso4 (12/10, 16:09-16:20)

Moduli: ricompilati da zero dalla cima di diviso4 (522de6a47); gc8034.ko e
ipu-bridge.ko identici byte per byte a quelli già installati, gc5035.ko
reinstallato (md5 in moduli.txt). Serie esportata in
patches/wip/driver-v2-diviso4/serie/.

- Richiesta di Uwe (12/10): applicata in tutti e 7 i commit, entrambi i
  driver; mod_devicetable.h assente anche da ipu-bridge.
- Statica (server, driver-v2-diviso4-verifica.log): W=1, sparse, smatch,
  checkpatch --strict puliti su tutti e 7.
- prova-binning: 20/20 (vedi cartelle.txt).
- prova-completa: 32 OK; KO solo per i 19 WARNING noti di
  ipu6-isys-queue.c:203; esposizione dispari non misurabile (poca luce).
- prova-crop: gc5035 0 KO, gc8034 0 KO (alcune posizioni non misurabili
  per la scena scura).
- libcamera (libcamera.txt): 60/60 fotogrammi, 0 ERROR, in 3 configurazioni
  per camera; gc5035 a 1280x960 e in ruolo raw a 24,05 fps (binning).
- Revisione avversaria a contesto pulito: nessun difetto bloccante.
  Rilievo «Assisted-by nel formato Claude:modello» respinto:
  coding-assistants.rst di questo albero chiede «LLM [TOOL1] [TOOL2]».
  Confermato e da decidere: i messaggi della 4 e della 5 dicono «changing
  the size resets the vertical blanking», ma il codice lo riporta al minimo
  a ogni set_fmt/set_selection ACTIVE (come imx219). Lettera da rifare per
  7 patch, anticipando: set_fmt che tocca il crop, la regola di 1296x972,
  unità in righe del sensore nel binning, doppione in enum_frame_size,
  PIXEL_RATE del GC8034 oltre il link, guadagno a indice.

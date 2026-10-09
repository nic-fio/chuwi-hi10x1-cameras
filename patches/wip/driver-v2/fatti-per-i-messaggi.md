# Fatti verificati per i messaggi della v2

Base per i messaggi di commit, la cover letter e la risposta a Laurent. Nic
scrive i testi in italiano con parole sue; Claude li traduce e la traduzione
si dichiara. Ogni fatto qui sotto è misurato sul tablet (Chuwi Hi10 X1,
IPU6, kernel 7.3-rc1 next) con due corse; la fonte è in `docs/14`. Niente di
quello che segue viene dal datasheet riservato.

## Che cosa cambia rispetto alla v1 (entrambi i driver)

- Niente più geometria fissa nella tabella: finestra di lettura e crop
  d'uscita si calcolano dal rettangolo di crop a ogni avvio dello stream.
- Crop analogico con VIDIOC_SUBDEV_S_SELECTION (target CROP): verticale con
  la finestra di lettura (fotogrammi più corti, fps più alti), orizzontale
  col crop d'uscita del sensore.
- set_fmt: niente binning né scaler, la dimensione del formato è quella del
  crop; una nuova larghezza o altezza ricentra il crop su quell'asse (come
  ov01a10, per chi non imposta il crop prima).
- I limiti di HBLANK, VBLANK ed esposizione seguono il crop; il default
  dell'esposizione non supera mai il massimo (bug latente della v1).
- Crop e formato vietati durante lo stream (EBUSY).
- Al crop di default l'immagine è identica alla v1 (confronto v1-v2-v1).
- Binning non incluso (motivo sotto).

## GC5035 (2 lane)

- NATIVE_SIZE = CROP_BOUNDS = 2608x1964: la più grande area misurata che dà
  immagine; intorno righe e colonne costanti (nero o fondo scala). Non è
  l'array fisico, che non è documentato.
- CROP_DEFAULT = (8, 8) 2592x1944, l'immagine della sequenza vendor.
- Passi: offset pari (ordine GRBG fisso), dimensioni multiple di 4, minimo
  64x64. Il sensore sposterebbe di una riga, ma gli offset dispari
  cambierebbero l'ordine Bayer.
- Col start: passi di 4 colonne, i valori pari danno immagini degradate;
  finestra orizzontale stretta = immagine nera. Per questo la finestra
  resta a tutta larghezza e l'orizzontale lo fa il crop d'uscita, che deve
  finire almeno 2 colonne prima della fine della finestra.
- Tempi: periodo = (altezza + vblank) x 2920 / 168,96 MHz, esatto da 64 a
  1964 righe (64 righe: 2,212 ms; 480: 9,401; 1944: 34,704).

## GC8034 (4 lane)

- NATIVE_SIZE = CROP_BOUNDS = 3282x2500 (righe 14-2513 del sensore: oltre
  la riga 2521 della finestra i tempi cambiano). CROP_DEFAULT = (8, 52)
  3264x2448, l'immagine vendor.
- Passi come il GC5035 (ordine RGGB fisso). Larghezza 512..3280: fino a 384
  colonne il ricevitore riceve fotogrammi rotti, da 448 va; un'uscita larga
  quanto la finestra dà errori CSI-2. Altezza 64..2448.
- Col start valido solo ad alcuni valori: finestra di tabella, orizzontale
  col crop d'uscita.
- Tempi: righe = finestra + 20 + registro di blanking; con finestra alta
  quanto l'uscita più 16, registro = vblank - 36 e periodo = (altezza +
  vblank) x 4272 / 256 MHz, esatto da 64 a 2448 righe.
- PIXEL_RATE corretto a 256 MHz (la v1 dichiarava 255,91 MHz, scelto per 24
  fps tondi; i periodi misurati tornano solo con 256 MHz).
- La tabella v1 scrive solo i byte bassi di alcuni registri di geometria; la
  v2 scrive tutto a 16 bit a ogni avvio (un byte alto lasciato da un crop
  precedente rompeva lo stream successivo).

## Binning (perché non c'è)

- GC5035: la tabella vendor 1296x972 funziona ed è una media di 4 campioni
  dello stesso colore (rumore temporale per pixel 2,71 -> 1,42 LSB, rapporto
  delle varianze 3,6-3,7), ma cambia PLL e timing MIPI: la frequenza del
  collegamento nel modo binned non è nota e LINK_FREQ non si può dichiarare
  con certezza. Il driver Intel dichiara la stessa frequenza e tempi che
  darebbero 57,6 fps; misurati 29.
- GC8034: il «binning» dei driver vendor esiste solo a 2 lane; a 4 lane con
  0xad = 0x30 il flusso CSI-2 si rompe in 7 combinazioni su 7, anche se la
  scrittura arriva (rilettura 0x30).
- Sakari su imx678 v3 (21/05/2026, <ag7oq5jO5G0rwvzb@kekkonen.localdomain>):
  binning e set_selection da rimandare al modello comune dei sensori raw.

## Prove della v2 (per la cover letter)

- v4l2-compliance da git 1616bf9e3c81 con -z PCI:0000:00:05.0: 54/54,
  0 falliti, 0 avvisi su entrambi (la v1 aveva 2 avvisi sul CROP).
- Batteria di crop (default, limiti, centro, angoli, minimo, richieste da
  arrotondare e fuori area): rettangolo applicato, periodo, fotogrammi
  completi, posizione al pixel: 0 KO in due corse per sensore.
- libcamera (simple + soft ISP): 60/60 fotogrammi, 0 errori, in tre
  configurazioni per camera.
- Limite osservato del ricevitore, non dei driver: oltre ~500 fps (GC8034 a
  64 righe) l'IPU6 restituisce timestamp nulli; GC5035 a 452 fps pulito.
- Controlli statici: W=1 + sparse, smatch, checkpatch --strict, coccinelle
  (esito della verifica in corso al momento della stesura: da aggiornare).

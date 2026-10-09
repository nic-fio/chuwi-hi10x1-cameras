# Patch libcamera gc5035/gc8034: fatti per il messaggio di commit

Il testo lo scrive Nic in italiano, Claude traduce. Qui solo i fatti.

Titolo: `libipa: camera_sensor_helper: Add GC5035 and GC8034`

1. Cosa aggiunge: helper per i sensori dei driver mandati a linux-media il
   9/10 (link lore da aggiungere). Black level 4096 (misurato 64 a 10 bit).
   Guadagno esponenziale: il controllo del driver è un indice. gc5035 17
   passi 1x-15,6x, ~1,5 dB; gc8034 7 passi 1x-7,66x, ~2,95 dB. Scarto
   massimo dalle curve misurate 1,6% e 1,7%.
2. Perché: senza helper libcamera usa AgcMSV invece di AgcMeanLuminance
   (commit 4412643bd) e prende l'indice per un guadagno. Finestra, 9/10:
   gc8034 con helper fermo a 1x 16,8 ms dal decimo fotogramma, senza non
   converge in 180 (17,4->29,9 ms); gc5035 con helper 1,68x, senza indice 9
   = 4,73x, 2,8 volte più luminoso. Luce artificiale 8/10: gc8034 senza
   helper oscilla per 90 fotogrammi.
3. Prova: Chuwi, IPU6, soft ISP, cam --metadata, 90 fotogrammi per corsa,
   due corse in ordine inverso (data/ae-finestra-20261009).

Quando: dopo il primo giro di commenti su linux-media. Se il controllo del
guadagno cambia (es. lineare invece dell'indice), l'helper va rifatto.

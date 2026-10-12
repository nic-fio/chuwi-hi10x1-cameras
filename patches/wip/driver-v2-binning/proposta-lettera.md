# Proposta per la lettera v2 col binning (12/10, da approvare da Nicola)

Proposta di Claude, scritta mentre Nicola era fuori. Cambia solo i punti
toccati dal binning. Il resto della lettera (cover-letter-v2.nic.it.txt)
resta com'è. Niente va nella .patch finché Nicola non approva.

## Oggetto

    [PATCH v2 0/7] media: Add GalaxyCore GC5035 and GC8034 sensor drivers

## Al posto di «Binning assente. …»

IT:

 - Binning 2x2 sul GC5035 (patch 6 e 7): con il crop di default, chiedendo
   metà formato (1296x972) si ottiene il binning, con lo stesso campo
   visivo. La sequenza vendor cambia la PLL, quindi ho misurato la
   frequenza del collegamento in quel modo: 176,3 ± 0,9 MHz, contro i
   175,2 MHz che danno i registri della PLL (con lo stesso metodo, a
   risoluzione piena, 420,7 ± 1,5 contro 422,4). La patch 6 aggiunge
   questa frequenza in ipu-bridge. Sul GC8034 il binning l'ho trovato solo
   in sequenze vendor a 2 lane; a 4 lane rompe il flusso CSI-2, quindi non
   c'è.

EN:

 - 2x2 binning on the GC5035 (patches 6 and 7): with the default crop,
   asking for half the size (1296x972) gives binning, with the same field
   of view. The vendor sequence changes the PLL, so I measured the link
   frequency in that mode: 176.3 +/- 0.9 MHz, against the 175.2 MHz given
   by the PLL registers (with the same method, at full resolution, 420.7
   +/- 1.5 against 422.4). Patch 6 adds this frequency to ipu-bridge. On
   the GC8034 I only found binning in 2-lane vendor sequences; with 4
   lanes it breaks the CSI-2 stream, so it isn't there.

## Al posto di «Ho messo il crop nelle patch 4 e 5, separate, …»

IT:

 - Ho messo il crop nelle patch 4 e 5 e il binning nelle 6 e 7, separate,
   dopo la discussione su IMX908 sul rimandarli al modello comune dei
   sensori raw (20261001133138.GM944070@killaraus.ideasonboard.com). Se
   volete fare lo stesso qui, le patch 1-3 stanno in piedi da sole, a
   risoluzione fissa come la v1.

EN:

 - I put the crop in patches 4 and 5 and the binning in 6 and 7,
   separately, after the IMX908 discussion about postponing them until the
   common raw sensor model
   (<20261001133138.GM944070@killaraus.ideasonboard.com>). If you want to
   do the same here, patches 1-3 stand on their own, at a fixed resolution
   like v1.

## Riga dei test

Da completare dopo le prove sul tablet (prova-completa-v2.sh,
prova-crop.py, prova-binning.sh, libcamera): aggiungere il binning
(tempi, posizione rispetto alla media 2x2 del modo pieno, compliance in
tutti e due i modi).

## «Rispetto alla versione v1»

IT, in fondo alla voce «patch 1 e 2»:

     tolto linux/mod_devicetable.h e tabella ACPI con inizializzatore con
     nome, come chiesto da Uwe.

e in coda:

   - patch 6 e 7: nuove.

EN:

     dropped linux/mod_devicetable.h and used a designated initializer in
     the ACPI table, as Uwe asked.

   - patches 6 and 7: new.

(Uwe Kleine-König ha risposto alla 1/3 il 12/10 alle 13:20; vale anche per
il GC8034, quindi la correzione è nelle patch 1 e 2.)

## Nota per Nicola

Le patch 4 e 5 della serie preparata il 9/10 (upstream/driver-v2-invio)
non avevano le correzioni delle 18:52 e delle 19:18 (set_fmt che centra
sul crop di default, VBLANK al default). I loro messaggi di commit le
descrivevano già. La serie nuova (ramo driver-v2-diviso2 sul server) ha il
codice provato.

# Messaggi di commit della v2 (italiano per Nic, inglese per i commit)

Preparati da Claude su delega di Nic (9/10 sera). Ogni numero viene da
docs/14 e fatti-per-i-messaggi.md. L'inglese è la traduzione dell'italiano.

---------------------------------------------------------------------------
## 1/5 media: i2c: Add GC5035 image sensor driver

IT:
Aggiunge un driver per il GalaxyCore GC5035, sensore raw Bayer da 5
Mpixel con interfaccia MIPI CSI-2 a due lane. Il driver supporta i
controlli di esposizione, guadagno analogico, blanking verticale e test
pattern, e produce 2592x1944 RAW10.

Il datasheet non è disponibile. La sequenza di inizializzazione viene dal
driver per Alder Lake-M di intel/ipu6-drivers, derivato da quello ChromeOS
del 2020. Finestra di lettura e crop d'uscita non fanno parte della
sequenza: si calcolano dal rettangolo di crop, nelle coordinate della più
grande area misurata che dà immagine (2608x1964), riportata come
dimensione nativa e limiti del crop. Il rettangolo di default dà la stessa
immagine della sequenza vendor. Il periodo del fotogramma, (altezza +
vblank) x 2920 / 168,96 MHz, coincide con le misure.

EN:
media: i2c: Add GC5035 image sensor driver

Add a driver for the GalaxyCore GC5035, a 5 Mpixel raw Bayer sensor with
a two lane MIPI CSI-2 interface. The driver supports the exposure,
analogue gain, vertical blanking and test pattern controls, and outputs
2592x1944 RAW10.

No datasheet is available. The initialisation sequence comes from the
Alder Lake-M driver in intel/ipu6-drivers, which derives from the ChromeOS
driver posted in 2020. The readout window and the output crop are not part
of the sequence: they are computed from the crop rectangle, in the
coordinates of the largest area measured to give image data (2608x1964),
which is reported as the native size and the crop bounds. The default crop
rectangle gives the same image as the vendor sequence. The frame period,
(height + vblank) * 2920 / 168.96 MHz, matches the measurements.

Assisted-by: claude-opus-5-5 coccinelle sparse smatch
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>

---------------------------------------------------------------------------
## 2/5 media: i2c: Add GC8034 image sensor driver

IT:
Aggiunge un driver per il GalaxyCore GC8034, sensore raw Bayer da 8
Mpixel con interfaccia MIPI CSI-2 a quattro lane. Il driver supporta i
controlli di esposizione, guadagno analogico e blanking verticale, e
produce 3264x2448 RAW10.

Il datasheet non è disponibile. La sequenza di inizializzazione viene dal
driver del BSP Rockchip. Finestra di lettura, crop d'uscita e lunghezza
delle righe CSI-2 si calcolano dal rettangolo di crop, nelle coordinate di
un'area di 3282x2500 misurata come utilizzabile, riportata come dimensione
nativa e limiti del crop; il rettangolo di default dà la stessa immagine
della sequenza vendor. Il fotogramma dura la finestra di lettura più 20
righe più il registro di blanking, che quindi vale vblank meno 36. Il
pixel rate, 256 MHz, è quello che dà i periodi misurati, da 1,869 ms per
112 righe a 41,653 ms per 2496.

EN:
media: i2c: Add GC8034 image sensor driver

Add a driver for the GalaxyCore GC8034, an 8 Mpixel raw Bayer sensor with
a four lane MIPI CSI-2 interface. The driver supports the exposure,
analogue gain and vertical blanking controls, and outputs 3264x2448
RAW10.

No datasheet is available. The initialisation sequence comes from the
Rockchip BSP driver. The readout window, the output crop and the CSI-2
line length are computed from the crop rectangle, in the coordinates of a
3282x2500 area measured to be usable, which is reported as the native size
and the crop bounds; the default crop rectangle gives the same image as
the vendor sequence. A frame lasts the readout window plus 20 lines plus
the blanking register, which therefore holds vblank minus 36. The pixel
rate, 256 MHz, is the one that gives the measured frame periods, from
1.869 ms for 112 lines to 41.653 ms for 2496 lines.

Assisted-by: claude-opus-5-5 coccinelle sparse smatch
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>

---------------------------------------------------------------------------
## 3/5 media: ipu-bridge: Add GalaxyCore GC5035 and GC8034

Invariato rispetto alla v1, più il Reviewed-by di Dan (9/10).

EN:
media: ipu-bridge: Add GalaxyCore GC5035 and GC8034

Add the GC5035 and GC8034 ACPI HIDs, with the link frequencies the two
sensors use with a 19.2 MHz external clock. Both are found on the CHUWI
Hi10 X1.

Reviewed-by: Daniel Scally <dan.scally@ideasonboard.com>
Assisted-by: claude-opus-5-5
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>

---------------------------------------------------------------------------
## 4/5 media: i2c: gc5035: Add analog crop support

IT:
Implementa la selezione CROP sul pad sorgente. Il crop verticale lo fa la
finestra di lettura, che accorcia il fotogramma: a 640x480 si arriva a 106
fps. Quello orizzontale lo fa il crop d'uscita del sensore, perché una
finestra più stretta dà immagini nere e il registro della colonna di
partenza si muove solo a passi di quattro colonne. Gli offset sono pari,
per tenere l'ordine GRBG, e le dimensioni multiple di 4, da 64x64 a
2608x1964.

Senza binning né scaler la dimensione del formato è quella del crop. Come
in ov01a10, set_fmt centra il crop su quello di default per chi non
imposta il crop prima, e come in imx219 una nuova dimensione riporta il
blanking verticale al default. Crop e formato non si cambiano durante lo
stream.

Provato con v4l2-compliance (54/54, nessun avviso) e con crop ai limiti,
negli angoli, alla dimensione minima e al centro: posizione verificata al
pixel, periodo come calcolato.

EN:
media: i2c: gc5035: Add analog crop support

Implement the crop selection on the source pad. The vertical crop is done
by the readout window, which shortens the frame: 640x480 runs at 106 fps.
The horizontal crop is done by the sensor output crop, as a narrower
readout window gives black images and the column start register only
moves in steps of four columns. Crop offsets are even, to keep the GRBG
order, and sizes are multiples of 4, from 64x64 to 2608x1964.

Without binning or scaling, the format size is the crop size. As in
ov01a10, set_fmt centres the crop rectangle on the default one for
userspace that does not set the crop first, and as in imx219 a new size
resets the vertical blanking. The crop and the format can't be changed
while streaming.

Tested with v4l2-compliance (54/54, no warning) and with crop rectangles
at the bounds, in the corners, at the minimum size and in the centre: the
position was checked to the pixel and the frame period is the computed
one.

Assisted-by: claude-opus-5-5 coccinelle sparse smatch
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>

---------------------------------------------------------------------------
## 5/5 media: i2c: gc8034: Add analog crop support

IT:
Implementa la selezione CROP sul pad sorgente, come per il GC5035: crop
verticale con la finestra di lettura, orizzontale con il crop d'uscita del
sensore, perché il registro della colonna di partenza dà immagini valide
solo ad alcuni valori. Gli offset sono pari, per tenere l'ordine RGGB, e
le dimensioni multiple di 4. La larghezza va da 512 a 3280: fino a 384
colonne il ricevitore CSI-2 riceve fotogrammi corrotti, e un'uscita larga
quanto la finestra di lettura dà errori CSI-2. L'altezza va da 64 a 2448:
con finestre più alte i fotogrammi si allungano oltre il calcolo.

Set_fmt e blanking verticale si comportano come nel GC5035.

Provato come il GC5035.

EN:
media: i2c: gc8034: Add analog crop support

Implement the crop selection on the source pad, as for the GC5035: the
vertical crop is done by the readout window, the horizontal crop by the
sensor output crop, as the column start register only gives valid images
at some values. Crop offsets are even, to keep the RGGB order, and sizes
are multiples of 4. The width ranges from 512 to 3280: up to 384 columns
the CSI-2 receiver gets corrupted frames, and an output as wide as the
readout window causes CSI-2 errors. The height ranges from 64 to 2448:
with taller readout windows the frames get longer than computed.

set_fmt and the vertical blanking behave as in the GC5035 driver.

Tested in the same way as the GC5035.

Assisted-by: claude-opus-5-5 coccinelle sparse smatch
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>

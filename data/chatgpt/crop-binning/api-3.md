Terza richiesta: revisione dei TESTI che andranno in lista (cover letter e
messaggi di commit della v2), dopo le correzioni al codice che conosci
(set_fmt ora centra sul crop di default, VBLANK al default a ogni cambio di
dimensione). La serie è divisa: 1-3 driver a crop fisso + ipu-bridge, 4-5
crop separabili, per il precedente IMX908 (Laurent e Sakari, 1/10/2026:
rimandare set_selection al modello comune dei sensori raw), mentre Laurent a
noi il 9/10 ha chiesto il crop analogico.

L'autore non è madrelingua inglese e scrive in italiano; il testo inglese è
una traduzione fedele e deve restare semplice e suo (Laurent diffida dei
testi scritti da LLM: non riscriverli in stile levigato).

Cerca solo:
1. affermazioni non sostenute dai fatti che ti ho dato o che un revisore
   potrebbe contestare;
2. errori o ambiguità di inglese che cambiano il significato (non lo stile);
3. punti che Laurent o Sakari attaccherebbero, e come prevenirli con il
   minimo cambiamento;
4. se la richiesta implicita nella cover (patch 4-5 da tenere o togliere) è
   chiara e rispettosa.
Rispondi in italiano, per punti, con la correzione minima proposta.

=== COVER LETTER ===
Subject: [PATCH v2 0/5] media: i2c: Add GalaxyCore GC5035 and GC8034 sensor drivers

Hi Laurent, after reading your message, this is what I did:

 - No more mode tables: the readout window and the output crop are
   computed from the crop rectangle every time streaming starts.
 - Crop through the CROP selection. Vertically it is an analog crop (the
   readout window gets smaller and the frame gets shorter: the GC5035 at
   640x480 runs at up to 106 fps). Horizontally it is the sensor output
   crop, because narrowing the readout window horizontally gives black
   images on the GC5035 and corrupted images on the GC8034.
 - No binning. On the GC5035 it works, but it changes the PLL and I don't
   know the link frequency in that mode, so I couldn't report a correct
   LINK_FREQ. On the GC8034 it only exists in the 2-lane vendor sequences;
   with 4 lanes it breaks the CSI-2 stream.
 - I put the crop in patches 4 and 5, separately, because for the IMX908
   you decided to postpone it until the common raw sensor model
   (<20261001133138.GM944070@killaraus.ideasonboard.com>). If you want to
   do the same here, patches 1-3 stand on their own, at a fixed resolution
   like v1.
 - I don't have the datasheet of the device, so I measured everything on
   the tablet: the area that gives image data (2608x1964 and 3282x2500,
   reported as NATIVE_SIZE and CROP_BOUNDS: it is not the physical array),
   the default crop (the same as v1: same image), the timing model (which
   corrected the GC8034 PIXEL_RATE to 256 MHz) and the size limits.
 - Testing: v4l2-compliance from git, 54/54 with no warnings on both, a
   set of crop tests in two test sessions (rectangle, timing, position to
   the pixel), libcamera 60/60 frames, and W=1, sparse, smatch, checkpatch
   and coccinelle clean on every patch.
 - Changes since v1:
   - patches 1 and 2: geometry removed from the register table and
     computed from the crop, all written as 16-bit values; NATIVE_SIZE and
     CROP_BOUNDS are the measured area instead of the vendor readout
     window; the default exposure no longer exceeds the maximum when
     VBLANK is reduced; GC8034: PIXEL_RATE set to 256 MHz and the blanking
     register computed from VBLANK.
   - patch 3: added Dan's Reviewed-by.
   - patches 4 and 5: new.
 - I used an LLM (Claude) for the code and the measurements, as stated in
   the tags; the English of this letter is translated from my Italian.

Nicola

[base-commit, diffstat e output di v4l2-compliance aggiunti da
git format-patch --cover-letter / dalla prova al momento dell'invio]

=== MESSAGGI DI COMMIT ===
--- 1/5
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
--- 2/5
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
--- 3/5
media: ipu-bridge: Add GalaxyCore GC5035 and GC8034

Add the GC5035 and GC8034 ACPI HIDs, with the link frequencies the two
sensors use with a 19.2 MHz external clock. Both are found on the CHUWI
Hi10 X1.

Reviewed-by: Daniel Scally <dan.scally@ideasonboard.com>
Assisted-by: claude-opus-5-5
Signed-off-by: Nicola Fiorillo <nicfio@gmail.com>
--- 4/5
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
--- 5/5
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

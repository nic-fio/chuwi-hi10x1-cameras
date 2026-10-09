<!-- gpt-5.5-2026-04-23 resp_056e057b0456839f006ac92fe28c3887d2a6dace84d59f39a5 uso 33261 token -->
Di seguito solo i punti che cambierei prima dell’invio.

---

## Punto generale: trailer `Assisted-by`

### Problema
Questi trailer sono rischiosi:

```text
Assisted-by: claude-opus-5-5 coccinelle sparse smatch
```

- `Assisted-by` non è un trailer kernel standard consolidato.
- `coccinelle sparse smatch` sono strumenti, non persone.
- Laurent/Sakari potrebbero chiedere di rimuoverli, indipendentemente dal merito tecnico.
- Inoltre “LLM for the code and the measurements” può far pensare che i fatti sperimentali vengano dall’LLM.

### Correzione minima
Rimuoverei tutti gli `Assisted-by:` dai commit.

Nella cover letter terrei una disclosure semplice:

```text
I used Claude as an assistant while writing/debugging the code and reviewing
the test plan/results. All register facts and measurements reported here come
from tests on the tablet. The English of this letter is translated from my
Italian.
```

Questo è molto più difendibile.

---

## Cover letter

### 1. “No more mode tables”

Originale:

```text
No more mode tables: the readout window and the output crop are
computed from the crop rectangle every time streaming starts.
```

### Problema
C’è ancora una tabella di inizializzazione registri. “No more mode tables” può essere contestato come troppo assoluto.

### Correzione minima

```text
The geometry registers are no longer fixed in the init register table: the
readout window and the output crop are computed from the crop rectangle every
time streaming starts.
```

---

### 2. “Vertically it is an analog crop”

Originale:

```text
Vertically it is an analog crop ...
```

### Problema
Senza datasheet, “analog crop” è una deduzione. Hai dimostrato che cambia la readout window e si accorcia il frame. Direi quello.

### Correzione minima

```text
Vertically the crop is implemented by changing the readout window, so the
frame gets shorter: the GC5035 at 640x480 runs at up to 106 fps.
```

---

### 3. GC8034 orizzontale: formulazione troppo forte

Originale:

```text
Horizontally it is the sensor output crop, because narrowing the readout
window horizontally gives black images on the GC5035 and corrupted images on
the GC8034.
```

### Problema
Per GC5035 sì: finestra orizzontale stretta = nero.  
Per GC8034 dai dati risulta soprattutto che il column start/readout window orizzontale non è affidabile; “narrowing the readout window horizontally gives corrupted images” è troppo specifico se non hai quella prova esatta.

### Correzione minima

```text
Horizontally it is the sensor output crop: a narrower horizontal readout
window gives black images on the GC5035, and on the GC8034 the column-start
settings I tried did not give a reliable programmable crop.
```

---

### 4. Binning GC5035: “changes the PLL” non basta

Originale:

```text
On the GC5035 it works, but it changes the PLL and I don't know the link
frequency in that mode, so I couldn't report a correct LINK_FREQ.
```

### Problema
Il punto non è solo PLL: la sequenza vendor cambia anche timing/MIPI. Meglio dire che non sai determinare la frequenza CSI-2.

### Correzione minima

```text
On the GC5035 it works, but the vendor binned sequence changes PLL/MIPI
timing and I have not determined the CSI-2 link frequency in that mode, so I
could not report a correct LINK_FREQ.
```

---

### 5. Binning GC8034: rendere verificabile

Originale:

```text
On the GC8034 it only exists in the 2-lane vendor sequences; with 4 lanes it
breaks the CSI-2 stream.
```

### Problema
“it only exists” è assoluto. Tu sai: nelle fonti pubbliche che hai trovato esiste solo a 2 lane; i tentativi 4-lane con i registri candidati rompono il CSI.

### Correzione minima

```text
On the GC8034 I only found binned modes in public 2-lane vendor sequences; in
the tested 4-lane configuration the candidate settings reproducibly broke the
CSI-2 stream.
```

---

### 6. Divisione patch 1-3 / 4-5

Originale:

```text
I put the crop in patches 4 and 5, separately, because for the IMX908 you
decided to postpone it until the common raw sensor model ...
```

### Problema
“You decided” può suonare personale/accusatorio. La richiesta implicita è chiara, ma la renderei più neutra.

### Correzione minima

```text
I kept crop support in patches 4 and 5 so that it can be reviewed or dropped
separately, following the IMX908 discussion about postponing set_selection
until the common raw sensor model
(<20261001133138.GM944070@killaraus.ideasonboard.com>). If you prefer the
same approach here, patches 1-3 stand on their own at the fixed v1
resolution.
```

Questa è chiara e rispettosa.

---

### 7. “datasheet of the device”

Originale:

```text
I don't have the datasheet of the device
```

### Problema
Sono due sensori. Inoltre “the datasheet” può sembrare che tu sappia che esista.

### Correzione minima

```text
I don't have datasheets for these sensors, so I measured everything on the
tablet:
```

---

### 8. `NATIVE_SIZE` / `CROP_BOUNDS`

Originale:

```text
the area that gives image data (2608x1964 and 3282x2500, reported as
NATIVE_SIZE and CROP_BOUNDS: it is not the physical array)
```

### Va quasi bene, ma meglio plurale e più preciso.

Correzione minima:

```text
the measured areas that give image data (2608x1964 and 3282x2500), reported
as NATIVE_SIZE and CROP_BOUNDS by the drivers; these are not claimed to be the
physical pixel arrays
```

Questo previene l’obiezione principale.

---

### 9. LLM nella cover

Originale:

```text
I used an LLM (Claude) for the code and the measurements, as stated in the
tags; the English of this letter is translated from my Italian.
```

### Problema
“for the measurements” è pericoloso: sembra che i dati vengano dall’LLM.  
“as stated in the tags” va tolto se rimuovi i trailer.

### Correzione minima

```text
I used Claude as an assistant while writing/debugging the code and reviewing
the test plan/results. All register facts and measurements reported here come
from tests on the tablet. The English of this letter is translated from my
Italian.
```

---

## Commit 1/5 — GC5035

### 1. “No datasheet is available”

Originale:

```text
No datasheet is available.
```

### Problema
Troppo assoluto.

### Correzione minima

```text
I do not have a datasheet for the sensor.
```

oppure:

```text
No public datasheet was available to me.
```

---

### 2. `native size` / `crop bounds`

Originale:

```text
in the coordinates of the largest area measured to give image data
(2608x1964), which is reported as the native size and the crop bounds.
```

### Va bene, ma prevenire l’obiezione “non è il physical array”.

Correzione minima:

```text
in the coordinates of the largest area measured to give image data
(2608x1964). The driver reports that measured area as the native size and the
crop bounds; it is not claimed to be the physical pixel array.
```

---

### 3. Trailer

Rimuovere:

```text
Assisted-by: claude-opus-5-5 coccinelle sparse smatch
```

---

## Commit 2/5 — GC8034

### 1. “No datasheet is available”

Come sopra.

Correzione minima:

```text
I do not have a datasheet for the sensor.
```

---

### 2. “3282x2500 area measured to be usable”

Originale:

```text
in the coordinates of a 3282x2500 area measured to be usable
```

### Problema
“usable” può essere contestato perché non tutto è selezionabile come singolo output massimo: width max 3280, height max 2448.

### Correzione minima

```text
in the coordinates of a 3282x2500 measured image-data area
```

oppure più esplicito:

```text
in the coordinates of a 3282x2500 area measured to contain image data
```

---

### 3. Frame periods: “112 lines” ambiguo

Originale:

```text
from 1.869 ms for 112 lines to 41.653 ms for 2496 lines.
```

### Problema
Meglio chiarire che sono frame lines, non output height.

### Correzione minima

```text
from 1.869 ms for 112 frame lines to 41.653 ms for 2496 frame lines.
```

---

### 4. Trailer

Rimuovere:

```text
Assisted-by: claude-opus-5-5 coccinelle sparse smatch
```

---

## Commit 3/5 — ipu-bridge

### 1. Link frequencies

Originale:

```text
with the link frequencies the two sensors use with a 19.2 MHz external clock.
```

### Problema minore
Se vuoi essere più prudente, specifica “on this platform / in these modes”.

### Correzione minima

```text
with the link frequencies used by the two sensors on this platform with a
19.2 MHz external clock.
```

---

### 2. Trailer

Rimuovere:

```text
Assisted-by: claude-opus-5-5
```

Il `Reviewed-by` e `Signed-off-by` vanno bene.

---

## Commit 4/5 — GC5035 crop

### 1. Subject: “analog crop support”

Originale:

```text
media: i2c: gc5035: Add analog crop support
```

### Problema
Il crop orizzontale non è analogico/readout-window crop: è output crop. Il subject è contestabile.

### Correzione minima

```text
media: i2c: gc5035: Add crop selection support
```

oppure:

```text
media: i2c: gc5035: Add configurable crop support
```

Io userei la prima.

---

### 2. “640x480 runs at 106 fps”

Va bene, se il valore è con `VBLANK` minimo/default. Per evitare obiezione:

```text
640x480 runs at up to 106 fps with the minimum vertical blanking.
```

---

### 3. “column start register only moves in steps of four columns”

Originale:

```text
... and the column start register only moves in steps of four columns.
```

### Problema
Manca il fatto importante: i valori pari corrompono l’immagine. Puoi aggiungerlo senza allungare molto.

Correzione minima:

```text
... and the column start register only moves in steps of four columns, with
even values producing corrupted images.
```

---

### 4. `set_fmt`

Originale:

```text
As in ov01a10, set_fmt centres the crop rectangle on the default one
```

### Problema
“The default one” è un po’ ambiguo. Meglio usare il nome V4L2.

Correzione minima:

```text
As in ov01a10, set_fmt centres the crop rectangle on CROP_DEFAULT
```

---

### 5. VBLANK

Originale:

```text
and as in imx219 a new size resets the vertical blanking.
```

Va bene se il codice fa davvero reset a default ogni cambio dimensione.  
Se vuoi essere più preciso:

```text
and, as in imx219, changing the size resets vertical blanking to its default.
```

---

### 6. Trailer

Rimuovere:

```text
Assisted-by: claude-opus-5-5 coccinelle sparse smatch
```

---

## Commit 5/5 — GC8034 crop

### 1. Subject: “analog crop support”

Originale:

```text
media: i2c: gc8034: Add analog crop support
```

### Problema
Stesso del GC5035: orizzontale via output crop, non analogico.

### Correzione minima

```text
media: i2c: gc8034: Add crop selection support
```

---

### 2. “as for the GC5035”

Originale:

```text
Implement the crop selection on the source pad, as for the GC5035:
```

### Problema
Accettabile, ma il GC8034 ha limiti propri. Va bene lasciarlo.

---

### 3. Width 512: manca perché non 448

Originale:

```text
The width ranges from 512 to 3280: up to 384 columns the CSI-2 receiver gets
corrupted frames, and an output as wide as the readout window causes CSI-2
errors.
```

### Problema
Dai dati: 448 funziona, ma scegli 512. Un revisore può chiedere perché il minimo non è 448.

### Correzione minima

```text
The width ranges from 512 to 3280: up to 384 columns the CSI-2 receiver
reported errors, 448 worked in the tests, and 512 is kept as a conservative
minimum. An output as wide as the readout window causes CSI-2 errors.
```

Meglio anche “reported errors” invece di “gets corrupted frames”, perché i tuoi fallimenti sono CSI errors/no usable frames.

---

### 4. Height > 2448

Originale:

```text
The height ranges from 64 to 2448: with taller readout windows the frames get
longer than computed.
```

### Problema
Troppo generale. Dai dati: il timing cambia quando la finestra raggiunge certe righe basse. Meglio dire quello.

### Correzione minima

```text
The height ranges from 64 to 2448: above that, the readout window can reach
the rows where the measured timing model changes.
```

Se vuoi essere ancora più concreto:

```text
The height ranges from 64 to 2448, keeping the readout window within the rows
where the measured frame-length model applies.
```

Questa è la versione più pulita.

---

### 5. “Tested in the same way”

Originale:

```text
Tested in the same way as the GC5035.
```

### Va bene, ma è un po’ debole. Minimo miglioramento:

```text
Tested in the same way as the GC5035: v4l2-compliance and crop rectangles at
the bounds, in the corners, at the minimum size and in the centre.
```

Non serve ripetere tutto.

---

### 6. Trailer

Rimuovere:

```text
Assisted-by: claude-opus-5-5 coccinelle sparse smatch
```

---

## Risposta alla domanda implicita: patch 4-5 da tenere o togliere

Sì, la richiesta è chiara, ma la renderei meno personale.

La formulazione migliore è:

```text
I kept crop support in patches 4 and 5 so that it can be reviewed or dropped
separately. If you prefer to postpone set_selection here as for the IMX908
discussion, patches 1-3 stand on their own at the fixed v1 resolution.
```

Questo dice chiaramente:

- patch 1-3 sono applicabili da sole;
- patch 4-5 sono offerte per revisione;
- non stai forzando la mano;
- non attribuisci a Laurent una decisione in modo polemico.

---

## Riassunto delle correzioni più importanti

Da fare prima dell’invio:

1. Cambiare i subject di 4/5 da `Add analog crop support` a `Add crop selection support`.
2. Togliere i trailer `Assisted-by:` con LLM/strumenti.
3. Correggere la frase sulla LLM: non “for the measurements”, ma “reviewing the test plan/results”; dati misurati da te.
4. Non dire “No more mode tables”; dire che la geometria non è più fissa nella init table.
5. Non dire “analog crop” come fatto generale; dire “readout-window crop” verticale.
6. Per GC8034, non dire che il binning “only exists” in assoluto; dire “I only found it in public 2-lane vendor sequences”.
7. Per GC8034 width, spiegare perché min 512 anche se 448 ha funzionato.
8. Per `NATIVE_SIZE`, mantenere sempre la precisazione: area misurata dal driver, non physical pixel array.

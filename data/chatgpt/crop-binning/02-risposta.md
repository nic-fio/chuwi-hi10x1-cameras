<!-- gpt-5.5-2026-04-23 resp_056e057b0456839f006ac918b4ce6487d29b650a6e99b527f1 uso 35555 token -->
Di seguito revisione severa, assumendo che il diff sia rappresentativo del codice reale.

---

## 1. Errori / rischi nel codice

### Bloccante: `set_fmt()` ricentra entrambi gli assi anche se cambia un solo asse

In entrambi i driver:

```c
if (width != crop->width || height != crop->height) {
        crop->left = ...
        crop->top = ...
        crop->width = width;
        crop->height = height;
}
```

Problema: se cambia solo la larghezza, sposti anche `top`; se cambia solo l’altezza, sposti anche `left`.

Esempio GC5035: crop default `2592x1944 @ (8,8)`. Se userspace chiede solo larghezza `2608x1944`, il codice ricentra anche verticalmente e porta `top` a 10. Quindi cambia immagine in Y senza motivo.

Correzione:

```c
if (width != crop->width) {
        crop->left = ALIGN_DOWN((AREA_WIDTH - width) / 2, 2);
        crop->width = width;
}

if (height != crop->height) {
        crop->top = ALIGN_DOWN((AREA_HEIGHT - height) / 2, 2);
        crop->height = height;
}
```

Oppure preserva il centro del crop corrente invece di ricentrare nell’area intera. Ma non ricentrare l’asse non modificato.

---

### Bloccante/minimo da verificare: modifica stato prima di aggiornare i controlli

In `set_selection()`:

```c
*v4l2_subdev_state_get_crop(state, 0) = rect;
...
gc5035_fill_format(format, &rect);

if (ACTIVE)
        return gc5035_update_ctrls(...);
```

Stesso in `set_fmt()`.

Problema: se `gc5035_update_ctrls()` / `gc8034_update_ctrls()` fallisce, lo stato ACTIVE è già stato modificato. Rimani con stato e controlli potenzialmente incoerenti.

Correzione consigliata:

1. calcola `rect` e `tmp_format`;
2. se ACTIVE, aggiorna i controlli;
3. solo se tutto va bene, committa crop e format nello stato.

Esempio:

```c
struct v4l2_mbus_framefmt new_fmt;

gc5035_fill_format(&new_fmt, &rect);

if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE) {
        ret = gc5035_update_ctrls(gc5035, &new_fmt);
        if (ret)
                return ret;
}

*v4l2_subdev_state_get_crop(state, 0) = rect;
*v4l2_subdev_state_get_format(state, 0) = new_fmt;
sel->r = rect;
```

---

### Da verificare: `__v4l2_ctrl_modify_range()` e valori correnti fuori range

Hai corretto il default dell’esposizione:

```c
min_t(s64, GC5035_EXP_DEF, exposure_max)
```

bene.

Ma devi testare anche questo caso:

1. userspace imposta esposizione alta;
2. userspace riduce drasticamente altezza / VBLANK massimo;
3. `exposure_max` scende sotto l’esposizione corrente.

Verifica se il core clampa il valore corrente come ti aspetti. Se no, devi clampare esplicitamente il controllo corrente, non solo il default.

Stesso discorso per `vblank`: se il valore corrente supera il nuovo massimo, devi sapere se viene clampato o se la modifica fallisce.

Test specifico da fare prima dell’invio:

```text
set exposure = max
set crop/format height = minimum
query exposure
stream on
```

e lo stesso con `vblank = max`.

---

### Locking: commento corretto solo se state lock == ctrl handler lock

Commento:

```c
/* Called with the state lock held, which is also the control handler lock. */
```

Questo è accettabile solo se nel probe fai davvero qualcosa del tipo:

```c
gc5035->sd.state_lock = gc5035->ctrls.lock;
```

o equivalente.

Se non è vero, l’uso di:

```c
__v4l2_ctrl_modify_range()
```

è sbagliato, perché la variante `__` richiede il lock del control handler già preso.

Correzione:

- o garantisci esplicitamente che state lock e ctrl lock siano lo stesso lock;
- o usa `v4l2_ctrl_modify_range()` non-`__`, prendendo attenzione all’ordine dei lock;
- o proteggi tutto con un mutex comune.

Questo è un punto che Sakari noterebbe facilmente.

---

### GC5035: commento incoerente con il codice sul column start

Commento:

```c
Its origin is read out with the row start register at 4 and
the column start register at 3.
```

Codice:

```c
#define GC5035_COL_START 1
...
GC5035_REG_WIN_LEFT, GC5035_COL_START
...
GC5035_REG_CROP_LEFT, crop->left + GC5035_OUT_LEFT_OFFSET
```

Questa frase è pericolosa. Il driver programma `col start = 1`, non 3.

Se vuoi spiegare l’equivalenza con la sequenza vendor, scrivilo esplicitamente:

```text
The vendor default used column start 3 and output crop left 8. The driver
uses column start 1 and output crop left 12 for the same default image, to keep
the horizontal readout window fixed at the measured-good column-start value.
```

Oppure più semplice:

```text
The coordinate origin corresponds to column start 1 and output crop left 4.
```

Non lasciare “column start 3” nel commento se il codice usa 1.

---

### GC5035 / GC8034: fixed Bayer code dipende dagli allineamenti

Tu tieni un solo `GC5035_MBUS_CODE` / `GC8034_MBUS_CODE`, quindi il crop deve preservare la fase Bayer.

Il codice allinea:

```c
left = ALIGN_DOWN(..., 2);
top  = ALIGN_DOWN(..., 2);
width/height = ALIGN_DOWN(..., 4);
```

Questo è coerente con “fixed Bayer order”, ma devi evitare di scrivere altrove che il crop verticale è libero a passo 1. Misurato sì; esposto dal driver no.

Due opzioni:

1. **Conservativa, attuale:** offset pari, Bayer code fisso. Va bene.
2. **Più completa:** permetti offset dispari e cambi `fmt->code` in base a `left/top` e mirror/flip. Più rischioso.

Per v2 io terrei la soluzione conservativa, ma scrivila chiaramente:

```text
The hardware can move vertically by one row, but the driver restricts crop
offsets to even coordinates to keep the advertised Bayer order stable.
```

---

### `set_selection()`: arrotondamento verso il basso può sorprendere, ma è accettabile

Esempio:

```c
rect.width = ALIGN_DOWN(clamp_t(...), 4);
```

Va bene, perché:

- RAW10 a larghezze multiple di 4 evita payload non interi;
- offset pari mantiene Bayer order;
- `enum_frame_size` non può esprimere step.

Però nel commit message devi dire che le dimensioni sono rounded down a multipli di 4.

---

### `enum_frame_size()`: ok, ma non implica che tutti i valori siano esatti

Restituisci solo min/max:

```c
fse->min_width = ...
fse->max_width = ...
```

Questo è normale per driver sensor con range continuo e rounding in `set_fmt()`. Nessun problema serio.

---

### Ordine scritture in `enable_streams()`: buono

Sequenza:

```c
write vendor table
write computed geometry
__v4l2_ctrl_handler_setup()
stream on
```

Questa è corretta.

In particolare è giusto che la geometria venga scritta prima dei controlli, perché `VBLANK`/esposizione dipendono dall’altezza corrente.

---

### GC8034: `LINE_BYTES` corretto, ma tieni il vincolo width % 4

Questo:

```c
cci_write(... GC8034_REG_LINE_BYTES, crop->width * 5 / 4, &ret);
```

è corretto solo perché imponi `width` multipla di 4. Va bene.

Io aggiungerei eventualmente un commento/assert difensivo:

```c
/* width is rounded to a multiple of 4 in set_fmt/set_selection. */
```

Non serve `BUILD_BUG_ON`, perché è runtime.

---

### GC8034: `GC8034_REG_BLANKING = vblank - 36`

Codice:

```c
ctrl->val - GC8034_BLANKING_OFFSET
```

Va bene dato:

```c
GC8034_VBLANK_MIN = 48
GC8034_BLANKING_OFFSET = 36
```

Quindi non vai negativo.

Però se in futuro qualcuno abbassa `VBLANK_MIN`, questo rompe. Il commento è sufficiente.

---

### Pad index

Nei nuovi `set_fmt()` / `set_selection()` non vedo controllo esplicito di `fmt->pad` / `sel->pad`.

Se il core nel tuo kernel valida già il pad prima di chiamare l’op, non è un problema pratico. Però molti driver fanno comunque:

```c
if (fmt->pad)
        return -EINVAL;
```

e:

```c
if (sel->pad)
        return -EINVAL;
```

Laurent potrebbe chiederlo per simmetria con gli altri pad ops.

---

## 2. `set_fmt()` che centra il crop

Sì, come modello è accettabile. È lo stesso schema usato da vari sensor driver: niente scaler, quindi la dimensione del format è la dimensione del crop; se userspace non imposta crop, `set_fmt()` produce un crop centrato.

Cosa direbbe Laurent probabilmente:

- “Va bene se documentato.”
- “Non cambiare più del necessario.”
- “Non spostare l’asse che non è cambiato.”
- “Se userspace vuole una posizione specifica, deve usare `set_selection()`.”

Quindi: **centrare sì, ma per asse**, non con l’`if (width != ... || height != ...)` attuale.

Inoltre, attenzione al default GC5035:

- area: `2608x1964`;
- default vendor: `2592x1944 @ (8,8)`;
- crop centrato geometricamente in area sarebbe `top = 10`, non `8`.

Quindi non dire:

> set_fmt 2592x1944 always gives the vendor image

Dire invece:

> the initial default state matches the vendor image; set_fmt without an explicit crop centres the requested size in the measured valid area.

---

## 3. `NATIVE_SIZE = CROP_BOUNDS = area misurata`

Accettabile, ma va formulato con molta cautela.

Non scrivere:

```text
native pixel array is 2608x1964 / 3282x2500
```

perché senza datasheet non lo sai.

Scrivi:

```text
The full physical pixel array is undocumented. The driver exposes as
NATIVE_SIZE the largest measured coordinate space that produced usable image
data. CROP_BOUNDS is identical to that coordinate space.
```

Per `CROP_DEFAULT` invece devi restituire il rettangolo vendor/default:

GC5035:

```text
CROP_DEFAULT = (8, 8) 2592x1944
```

GC8034:

```text
CROP_DEFAULT = (8, 52) 3264x2448
```

e `CROP` è quello corrente.

Se nel codice `get_selection()` non fa esattamente questo per:

- `V4L2_SEL_TGT_NATIVE_SIZE`
- `V4L2_SEL_TGT_CROP_BOUNDS`
- `V4L2_SEL_TGT_CROP_DEFAULT`
- `V4L2_SEL_TGT_CROP`

va corretto.

---

## 4. GC8034: min width 512, max 3280 dentro area 3282

Non è un problema serio.

È legittimo avere:

```text
CROP_BOUNDS width = 3282
max selectable/output width = 3280
```

se il motivo è hardware/CSI misurato.

Possibile obiezione del revisore:

> Why can’t userspace select the full CROP_BOUNDS width?

Risposta verificabile:

```text
The measured valid coordinate space is 3282 columns wide, but programming an
output width equal to the readout window causes CSI-2 errors on the tested
platform. Widths up to 384 also fail; 448 and above work. The driver therefore
limits the exposed output width to 512..3280.
```

Per libcamera non dovrebbe essere un problema se:

- `enum_frame_size()` riporta max `3280`;
- `set_fmt()` ritorna il formato arrotondato;
- `set_selection()` ritorna il crop effettivamente applicato.

Hai già testato 60/60, quindi bene.

Unica raccomandazione: nella cover letter spiega esplicitamente che `CROP_BOUNDS` è coordinate space, non promessa che il rettangolo intero sia selezionabile come singolo crop massimo.

---

## 5. Cosa manca per rendere la v2 accettabile

Prima dell’invio io sistemerei almeno questi punti:

1. **Fix `set_fmt()` per asse**, non ricentrare entrambi gli assi.
2. **Correggere il commento GC5035 su `col start 3` vs codice `col start 1`.**
3. **Verificare/clampare esposizione e vblank correnti** quando il formato/crop riduce i massimi.
4. **Assicurare locking corretto**: state lock e ctrl handler lock devono essere davvero lo stesso lock se usi le funzioni `__v4l2_ctrl_*`.
5. **Verificare `get_selection()` completo**:
   - `NATIVE_SIZE = area misurata`;
   - `CROP_BOUNDS = area misurata`;
   - `CROP_DEFAULT = rettangolo vendor`;
   - `CROP = stato corrente`.
6. **Aggiornare cover letter e commit message**:
   - GC5035 è 2 lane;
   - GC8034 è 4 lane;
   - niente binning in v2;
   - niente affermazioni su registri non documentati oltre agli effetti misurati;
   - spiegare che NATIVE_SIZE è “measured usable coordinate space”, non physical array.
7. **Aggiungere test specifici di regressione manuale**:
   - `set exposure=max`, poi crop minimo;
   - `set vblank=max`, poi crop massimo;
   - `set_fmt()` cambiando solo larghezza;
   - `set_fmt()` cambiando solo altezza;
   - `TRY` non modifica `ACTIVE`;
   - `ACTIVE` in streaming ritorna `-EBUSY`.

Nel complesso: l’impianto è buono e le scelte geometriche sono difendibili, ma il bug del ricentramento per assi e la formulazione ambigua del GC5035 sono da correggere prima della mailing list.

<!-- gpt-5.5-2026-04-23 resp_056e057b0456839f006acce7b01e4487d288d183b241a2c183 uso 36349 token -->
## 1. Regola nuova: difendibile?

Sì, **è difendibile**, ma va descritta come una scelta di precedenza tra due stati validi, non come workaround per libcamera.

Hai due modi che producono `1296x972`:

1. **binned 2x2**: crop nativo `2592x1944`, output `1296x972`;
2. **unbinned cropped**: crop nativo `1296x972`, output `1296x972`.

Quindi il formato da solo non disambigua. La regola nuova è ragionevole perché:

- `S_FMT(1296x972)` su uno stato “generico” sceglie il modo più utile/comune: **full-FoV binned**;
- `S_SELECTION(CROP=1296x972)` seguito da `S_FMT(1296x972)` resta **crop unbinned esplicito**;
- `S_FMT(G_FMT)` resta idempotente:
  - in binning: crop `2592x1944`, fmt `1296x972` → resta binning;
  - in crop unbinned: crop `1296x972`, fmt `1296x972` → resta unbinned;
- `TRY` e `ACTIVE` hanno la stessa logica;
- `set_selection()` continua a significare “voglio questo campo in coordinate native”, e quindi disabilita il preset binned.

### Punto attaccabile

Questa parte è troppo “libcamera-specific” nel commento:

```c
(libcamera sets the largest size, then the one it wants)
```

Laurent potrebbe dire che la semantica del driver non deve essere giustificata dal comportamento corrente di libcamera.

Correzione minima del commento:

```c
 * Half the size of the default crop rectangle selects 2x2 binning and sets
 * the default crop rectangle back, unless the crop rectangle already has
 * that size. This makes the requested output size select the full-FOV binned
 * mode by default, while keeping an explicitly configured crop of the same
 * size unbinned.
```

Poi, nella cover letter, puoi dire che questo è stato verificato anche con libcamera.

### Altro punto da controllare

Assicurati che il modo binned non sia derivato solo dalla richiesta fatta a `set_fmt()`, ma dallo **stato risultante**:

```text
binning attivo se format = 1296x972 e crop = CROP_DEFAULT 2592x1944
non binned se format = crop size
```

Questa distinzione deve essere usata anche in:

- `enable_streams()`;
- aggiornamento `LINK_FREQ`;
- aggiornamento `PIXEL_RATE`;
- `VBLANK/HBLANK/exposure`;
- eventuale `get_frame_desc()` se dipende dal modo.

Non deve esistere uno stato ambiguo “fmt 1296x972” senza sapere se è binned o crop unbinned.

---

## 2. Caso ambiguo: in binning l’utente imposta crop `1296x972`

È coerente.

Se l’utente fa:

```text
S_SELECTION(CROP = 1296x972)
```

sta chiedendo un campo nativo `1296x972`, non un crop nelle coordinate binned. Quindi è corretto che il driver passi a:

```text
crop = 1296x972
format = 1296x972
bin = 1
```

cioè crop unbinned.

Questo è anche coerente con la tua regola:

- `set_selection()` è esplicito e prevale;
- il binning è un preset del crop default;
- crop arbitrario + binning non è supportato/misurato.

Da documentare in commit message con una frase semplice:

```text
Setting CROP explicitly disables the binned preset; the output size becomes
the crop size again.
```

Oppure:

```text
The binned mode is only exposed for CROP_DEFAULT. Explicit crop rectangles,
including 1296x972, are unbinned.
```

---

## 3. Casi che possono sorprendere

### Caso A

Utente ha un crop qualsiasi, per esempio:

```text
crop = 640x480
S_FMT(1296x972)
```

Risultato nuovo:

```text
crop torna a CROP_DEFAULT
binning 2x2
```

Questo può sorprendere, ma è accettabile: senza scaler non puoi ottenere `1296x972` da un crop `640x480`, quindi `set_fmt()` deve comunque cambiare qualcosa. Scegliere il preset binned è difendibile.

### Caso B

Utente è in crop unbinned `1296x972` e vuole passare al binned chiamando solo:

```text
S_FMT(1296x972)
```

Non succede: resta unbinned, per idempotenza.

Per ottenere il binned deve fare ad esempio:

```text
S_SELECTION(CROP_DEFAULT)
S_FMT(1296x972)
```

Questo è il prezzo della disambiguazione. È accettabile, ma va documentato.

### Caso C

Utente fa solo `set_fmt(1296x972)` dopo che libcamera o altro ha portato il crop a `2608x1964`.

La nuova regola fa la cosa utile: torna al crop default e abilita il binning.

Questo è il motivo pratico del cambio, ma non lo metterei nel commento del codice.

---

## 4. Semantica subdev: violazioni?

Non vedo una violazione chiara, se mantieni queste condizioni:

- `S_FMT(G_FMT)` non cambia stato;
- `TRY` non modifica `ACTIVE`;
- `ACTIVE` durante streaming continua a dare `-EBUSY`;
- `G_SELECTION(CROP)` dopo `S_FMT(1296x972)` in binning restituisce davvero `CROP_DEFAULT`;
- `G_FMT` restituisce `1296x972`;
- `set_selection(CROP)` aggiorna il format a crop-size e disabilita binning;
- i controlli `LINK_FREQ`/`PIXEL_RATE` riflettono il modo attivo.

La semantica è history-dependent, ma non in modo illegale: `set_fmt()` nei subdev sensor può dipendere dalle selection correnti.

---

## 5. Alternative

### Alternativa 1: `1296x972` sempre binned

Difetto concreto: rompe il caso esplicito:

```text
S_SELECTION(CROP=1296x972)
S_FMT(1296x972)
```

e può violare l’idempotenza:

```text
G_FMT -> 1296x972
S_FMT(1296x972)
```

passerebbe da crop unbinned a binning, a meno di aggiungere comunque un’eccezione. Quindi finisci vicino alla tua regola attuale.

### Alternativa 2: `1296x972` binned solo se crop corrente è default

È la regola vecchia.

Difetto concreto già misurato: libcamera non raggiunge mai il binning perché durante configure passa da `2608x1964` e lascia il crop non default.

Quindi non va bene.

### Alternativa 3: controllo esplicito “binning on/off”

Sconsigliata.

Difetti:

- probabilmente sarebbe un controllo privato/non standard;
- duplica informazioni già rappresentabili con format + crop;
- libcamera non lo userà automaticamente;
- Laurent/Sakari potrebbero rifiutarlo come mode selection via control.

### Alternativa 4: usare `V4L2_SEL_TGT_COMPOSE`

Semanticamente sarebbe il modello più pulito:

```text
CROP = campo nativo
COMPOSE / format = dimensione dopo binning
```

Quindi:

```text
crop 2592x1944 + compose 1296x972 = binning
crop 1296x972 + compose 1296x972 = unbinned
```

Difetti concreti:

- più codice;
- più superficie di review;
- potrebbe incrociarsi con il “common raw sensor model” che Laurent/Sakari stanno ancora discutendo;
- `CameraSensorLegacy` potrebbe non usarlo nel modo desiderato;
- per un solo preset binned rischia di essere troppo.

Per v2 io non lo farei, salvo richiesta esplicita del maintainer.

---

## 6. Correzione minima consigliata

Terrei la regola nuova, ma cambierei commento/commit message così:

```c
/*
 * Half the size of the default crop rectangle selects 2x2 binning and sets
 * the default crop rectangle back, unless the crop rectangle already has
 * that size. This makes the requested output size select the full-FOV binned
 * mode by default, while keeping an explicitly configured crop of the same
 * size unbinned.
 *
 * Otherwise the output size is the size of the crop rectangle: a new width
 * or height centres the crop rectangle on the default crop rectangle along
 * that axis, within the measured area. The default size gives the default
 * rectangle back.
 */
```

E nel commit:

```text
The 1296x972 size can be produced in two ways: as the 2x2 binned output of
CROP_DEFAULT, or as an unbinned 1296x972 crop. Prefer the binned full-FOV mode
when set_fmt() requests 1296x972, but keep an explicitly configured 1296x972
crop unbinned. Setting CROP explicitly disables the binned preset.
```

Questa formulazione è difendibile e non sembra una pezza per libcamera.

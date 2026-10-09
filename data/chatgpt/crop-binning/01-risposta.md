<!-- gpt-5.5-2026-04-23 resp_056e057b0456839f006ac8f73ff9e887d2863b113b392e9fa1 uso 15211 token -->
## 1. Modello del `col start` GC5035

Sì, **il modello è sostenuto dai dati**, ma solo come modello empirico del registro `P0 0x0c`, non come spiegazione fisica.

Direi così:

- i valori **dispari** sono gli unici utilizzabili;
- il moto geometrico osservato è a passi di **4 colonne**;
- il valore pari `c` produce la stessa posizione geometrica del dispari precedente `c - 1`, ma con immagine degradata;
- la fase Bayer non cambia nei passi validi osservati.

Attenzione: nella descrizione c’è una piccola ambiguità. Gli esempi sono riferiti a `c = 3`, non a `c = 1`.

Formula coerente con gli esempi:

```text
dx(c) = 4 * (floor((c - 1) / 2) - 1)   rispetto a c = 3
```

Quindi:

```text
c=1/2  -> -4
c=3/4  ->  0
c=5/6  -> +4
c=7/8  -> +8
c=11   -> +16
```

Prima di metterlo in un commit message controllerei ancora:

- ripetizione su almeno un’altra scena o pattern stabile, non solo cucina;
- sweep di più valori dispari verso gli estremi utili, non solo `1,3,5,7,11`;
- verifica che il degrado dei valori pari non sia un artefatto dell’analisi Bayer: confronti per piano separato, come hai già iniziato a fare;
- verifica con output crop e larghezze realistiche del driver v2, non solo setup di laboratorio;
- controllo esplicito che `P0 0x0c` pari non cambi anche timing/MIPI in modo sottile;
- nessuna affermazione tipo “questo è il registro di analog crop orizzontale fine”: direi solo che **l’effetto misurato** è quello.

Nel commit message userei una formulazione prudente:

> The undocumented column-start register was swept experimentally. Odd values move the sampled image in 4-pixel steps. Even values produce the same geometric position as the previous odd value but degraded frames, so the driver only programs odd values.

Non direi di più.

---

## 2. Proposta GC5035 v2

### Parte buona

Mi sembra corretto:

- escludere dalle selection API le righe fisse a `1019/1023` e le colonne nere/costanti;
- esporre solo ciò che hai misurato come immagine valida;
- usare crop verticale libero a passo 1 riga;
- trattare il binning GC5035 come preset indivisibile;
- non dichiarare analogico/digitale il binning: “2x2 binning/averaging measured” va bene, “analog binning” no.

### Rischio grosso: `2608x1964` vs `1296x972`

C’è però un problema importante.

Se definisci:

```text
CROP_BOUNDS = 2608x1964
```

allora metà crop sarebbe:

```text
1304x982
```

ma il preset vendor binned è:

```text
1296x972
```

cioè esattamente metà di:

```text
2592x1944
```

Quindi non puoi dire contemporaneamente:

- crop pieno = `2608x1964`;
- binning = metà del crop pieno;
- output binned = `1296x972`.

Almeno una delle tre cose deve cambiare.

Soluzioni possibili:

1. **Bounds misurati 2608x1964, default crop 2592x1944**  
   È probabilmente la soluzione più difendibile, se riesci a giustificare l’offset del rettangolo `2592x1944` dentro l’area `2608x1964`.

   Esempio concettuale:

   ```text
   NATIVE_SIZE / CROP_BOUNDS = 2608x1964
   CROP_DEFAULT              = 2592x1944
   binned preset             = CROP_DEFAULT / 2 = 1296x972
   ```

   Però l’offset del default non va inventato: va preso da tabella vendor o misurato.

2. **Esporre solo 2592x1944 come area utile**  
   Più conservativo. Nasconde i margini misurati, ma evita di esporre pixel forse non appartenenti all’area immagine nominale.

3. **Esporre 2608x1964 ma binning solo per uno specifico crop 2592x1944**  
   Va bene, ma allora nel codice e nella cover letter devi dire chiaramente che il preset binned non è disponibile per l’intero `CROP_BOUNDS`.

Non lascerei il driver con “full crop 2608x1964” e “binned half crop 1296x972” senza spiegazione: un revisore lo noterà.

### Altro rischio: crop orizzontale a passo 4

Qui vedo una possibile incoerenza.

Tu hai misurato che:

- `P1 0x92/0x94` sposta l’uscita a passo 1 px;
- `P0 0x0c` ha passi effettivi da 4 px e valori pari degradati;
- la finestra analogica orizzontale stretta dà frame neri;
- conclusione precedente: crop orizzontale solo d’uscita.

Allora il crop orizzontale V4L2 non dovrebbe necessariamente essere limitato a passo 4.

Io farei:

- `P0 0x0c` fisso a un valore dispari noto buono, probabilmente quello vendor;
- crop orizzontale tramite output crop `P1`;
- `left` a passo 1 px se gestisci il cambio di Bayer code;
- oppure passo 2 px se vuoi mantenere la fase Bayer orizzontale costante;
- passo 4 solo se vuoi una restrizione conservativa, ma allora va motivata come policy del driver, non come limite hardware dimostrato.

Se lasci `left` a passo 4, Laurent potrebbe chiedere: perché, se hai misurato che l’output crop si muove a 1 px?

### Bayer code

Se permetti:

- `top` dispari;
- eventualmente `left` dispari;
- mirror/flip;

allora il media bus code deve cambiare coerentemente.

Non basta esporre `MEDIA_BUS_FMT_SRGGB10_1X10` fisso.

Devi calcolare il Bayer order da:

```text
crop left parity
crop top parity
hflip
vflip
GC5035 flip extra shift di 1 riga
```

Per GC5035, il flip verticale non è un flip puro: hai misurato anche `dy -1`. Questo deve entrare nel modello, oppure devi restringere/gestire il controllo in modo conservativo.

### Selection API

Un revisore media probabilmente si aspetterebbe:

- `NATIVE_SIZE`: coordinate native del pixel array esposto dal driver;
- `CROP_BOUNDS`: massimo rettangolo crop valido;
- `CROP_DEFAULT`: rettangolo normale/full-frame usato come default;
- `CROP`: rettangolo attualmente programmato, dopo rounding/allineamenti.

Non includerei nei bounds/default:

- righe fisse a `1019`;
- riga/bande a `1023`;
- colonne nere;
- colonne costanti.

Se scegli `2608x1964`, formulalo come:

> largest measured non-constant imaging area

non come “full physical pixel array”, perché senza datasheet non lo sai.

---

## 3. Registri a doppio buffer

Conseguenze principali:

### Readback

Non usare la rilettura immediata dopo `stream on` come verifica della scrittura.

Per quei registri la semantica osservata è:

```text
write accepted
readback initially old/shadow value
later readback programmed value
```

Quindi:

- la cache software del driver deve essere la fonte di verità;
- la diagnostica deve leggere dopo almeno un frame, o a stream fermo;
- non trattare il readback immediato come errore.

### Controlli durante streaming

Per esposizione e VBLANK:

- è normale che l’effetto arrivi dal frame successivo o da uno dei frame successivi;
- non promettere applicazione immediata;
- se exposure e frame length/VBLANK sono scritti separatamente, può esserci un frame transitorio con combinazione vecchia/nuova;
- se non conosci un group hold affidabile, non dichiarare aggiornamento atomico.

Da implementare bene:

- quando cambia VBLANK, aggiornare il range exposure;
- se il massimo scende sotto il valore corrente/default, clampare prima;
- correggere il bug che hai già trovato: il default passato a `__v4l2_ctrl_modify_range()` deve essere <= nuovo massimo.

### Cambio crop durante streaming

Io lo vieterei:

```c
if (streaming)
        return -EBUSY;
```

Motivi:

- crop cambia dimensioni e forse Bayer code;
- cambia il frame che il ricevitore CSI si aspetta;
- più registri devono essere coerenti fra loro;
- con double buffering non sai se tutti latchano nello stesso frame;
- un latch parziale può produrre esattamente gli errori CSI che hai visto.

Quindi: controlli tipo exposure/gain/VBLANK sì durante streaming; crop/format/binning no, salvo prova specifica e meccanismo atomico noto.

---

## 4. GC8034 binning

Sì, è ragionevole dichiarare il binning GC8034 non supportato nella v2.

La formulerei così, senza inventare il significato di `0xad`:

> GC8034 2x2 binned output is not exposed in this version. Public vendor sources only provide the 1632x1224 mode for a 2-lane configuration. On the tested 4-lane IPU6 platform, applying the candidate vendor binning setting involving `P0 0xad = 0x30` reproducibly breaks the CSI-2 stream: no frames are captured and the receiver reports payload CRC/header/long-packet/frame-sync errors. The same crop/LWC/output settings with `0xad = 0x00` stream correctly, and register readback confirms that `0xad = 0x30` was written. No known public 4-lane register sequence produces a working binned mode, so the driver exposes only full-resolution/cropped operation for GC8034.

Punti importanti:

- non dire “`0xad` è il registro del binning” se non lo sai;
- dire “candidate/vendor binned setting”;
- citare il controllo negativo `0xad = 0x00`;
- citare il readback `0x30`;
- citare che le fonti pubbliche hanno il modo solo a 2 lane;
- dire che verrà rivalutato se appare una fonte 4-lane funzionante.

---

## 5. Cose da correggere o indebolire

### Ambiguità nel modello `col start`

Come sopra: formula ed esempi sono riferiti a basi diverse. Sistemala prima di inserirla in mail/commit.

### `2608x1964` non è automaticamente “active array”

Hai dimostrato che è un’area non costante/immagine nel setup misurato. Non hai dimostrato che sia l’active array nominale del sensore.

Dato che il binning vendor è `1296x972`, c’è un forte indizio pratico che il rettangolo nominale sia `2592x1944`.

Quindi eviterei:

> native active area is 2608x1964

Meglio:

> largest measured valid non-constant readout area is 2608x1964

e poi decidere con attenzione `CROP_DEFAULT`.

### “Crop orizzontale solo d’uscita”

La conclusione è ragionevole per la v2, ma non direi che hai dimostrato che qualunque crop analogico orizzontale sia impossibile. Hai dimostrato che una finestra stretta specifica produce nero, e che l’output crop funziona.

Formulazione sicura:

> Horizontal analogue window reduction was not found to produce usable images in the tested configuration; the driver therefore implements horizontal crop through the output crop stage only.

### Binning GC5035

Il rapporto di varianze è un buon dato.

Formulazione sicura:

> consistent with averaging four same-colour samples

Non:

> proven analogue 2x2 binning

Hai già questa cautela, mantienila.

### `P0 0xf9`

Poiché scrivi `0x12` e rileggi sempre `0x10`, non attribuire al bit 1 nessuna funzione. Se rimane nella tabella perché viene dal vendor e il modo funziona, commentalo come valore vendor con bit non sticky/readback-masked, non come bit necessario.

### Double buffering

La tua conclusione è plausibile, ma “applicati a un confine di fotogramma” è ancora un’inferenza. Puoi dire:

> registers appear to be shadowed/double-buffered and become visible after streaming progresses

Per dire esattamente “frame boundary” servirebbe una prova durante streaming con marcatura frame-by-frame.

### GC8034 `P3 0x22 = 0x03`

Hai scritto “innocuo, dy -1, non confermato”. Non lo userei in commit/cover letter. È debole e non serve.

### Errori CSI

Ottimo che tu abbia distinto “zero frame + errori IPU6” da immagine degradata. Continua a tenerli separati: sono fenomeni diversi.

### Default exposure

Da correggere prima della v2. Un revisore non dovrebbe trovarsi un `set_vblank()` che fallisce per default fuori range.

# Recensione della serie IPU6 di Sakari (18 settembre 2026)

## Come ci siamo arrivati

Controllo di routine del 18/09. Sul **nostro** thread, niente: la v2
dell'invio 1 e' ferma a sei messaggi, l'ultimo e' la nostra replica del
12/09. Sakari non ha risposto, nessun altro e' intervenuto.

La novita' era altrove. Il 14/09 Sakari ha pubblicato una serie di 21
patch, *"IPU6 multi-stream and metadata support preparation"*, e il 17/09
ne ha gia' fatto la v2 (`20260917113923.59004-1-sakari.ailus@linux.intel.com`).
Riscrive da cima a fondo le due funzioni della nostra patch 1.

**Il nostro difetto e' ancora li'**, per la terza volta: `remote_pad =
media_pad_remote_pad_first(...)` dereferenziato senza controllo in
`ipu6_isys_csi2_enable_streams()` e `..._disable_streams()`. Prima ci era
passata sopra la v4 IPU7, adesso questa.

## La decisione

Invece di rispedire una patch nostra in coda, **commentare la patch sua**.
La serie e' aperta in revisione adesso; un commento su una patch del
manutentore viene letto, una patch nostra in coda no. La patch 2 (quella
del framework) resta da rispedire da sola, non e' toccata da questo.

## I quattro reperti, tutti in `ipu6_isys_csi2_streaming_change()`

Funzione nuova, aggiunta dalla patch **09/21**. Tutto letto sul testo
pubblicato su lore, **non** sul ramo git (che e' leggermente diverso e non
sarebbe stato citabile).

1. **Il tipo di ritorno non regge l'errore.** La funzione e' dichiarata
   `bool`, ma sulla via d'errore fa `return ret;` con `ret` intero. Un
   codice d'errore negativo diventa `true`, cioe' "procedi": chi chiama
   avvia il flusso del firmware e poi esegue `csi2->streaming_vc |= BIT(vc)`
   con `vc` **mai assegnata** — `*vc` si riempie solo in fondo alla
   funzione, oltre quel ritorno anticipato. In `..._disable_streams()` c'e'
   il gesto speculare con `&= ~BIT(vc)`. I due `return false` invece vanno
   bene: fanno saltare il cambio di stato.

2. **Il controllo c'e' ma controlla la cosa sbagliata.** Il codice fa
   `if (!av)` dopo `media_pad_remote_pad_unique()`, ma quella funzione
   `NULL` non lo restituisce mai. Verificato sul sorgente di mainline
   (`drivers/media/mc/mc-entity.c`): restituisce `ERR_PTR(-ENOLINK)` se non
   trova un collegamento attivo e `ERR_PTR(-ENOTUNIQ)` se ne trova piu' di
   uno. Quindi `!video_pad` non e' mai vero, il `dev_dbg()` sotto e'
   irraggiungibile, e il puntatore d'errore passa dentro
   `container_of_const()` fino a `av->streaming`, dove viene dereferenziato.

   **Il precedente che rende la cosa non opinabile**: nello stesso file,
   `ipu6_isys_csi2_get_link_freq()` la stessa chiamata la controlla con
   `IS_ERR()` e la stampa con `%pe`. E' codice suo. Citato nel messaggio.

3. **La ricerca sul pad d'ingresso, poche righe sopra, non ha nessun
   controllo**: `remote_pad->entity` viene letto subito.

4. **Un ciclo che non filtra.** La ricerca interna usa come chiave
   `this_entry->stream`, che non cambia a ogni giro: `entry` finisce sempre
   per essere `this_entry` stesso, il confronto sul canale virtuale e'
   quindi sempre vero e il `continue` non scatta mai. Ogni rotta attiva
   viene contata, qualunque sia il suo canale. Dal messaggio di commit la
   chiave doveva essere `route->sink_stream`. Scritto come "se non ho letto
   male": riguarda le sue intenzioni, non un fatto.

In coda al messaggio, **una riga sola** sul nostro vecchio difetto che
sopravvive a tutte e 21 le patch, dicendo esplicitamente che non riapro la
discussione sullo scenario. Solo: se entrano i controlli dei punti 2 e 3,
quel puntatore sta li' accanto.

## Come e' stato verificato

- `mc-entity.c` di mainline, scaricato da git.kernel.org: `curl` **passa**
  su git.kernel.org e su git.linuxtv.org. Anubis blocca solo lore, per cui
  li' serve il browser.
- Lo stato finale dopo tutte e 21 le patch, letto sul ramo di Sakari:
  `https://git.linuxtv.org/sailus/media_tree.git`, rami `ipu6`,
  `metadata-pre`, `metadata`. **Serve per non dire sciocchezze**: se una
  patch piu' avanti nella serie avesse aggiunto il controllo mancante,
  il commento sarebbe stato sbagliato. Non lo aggiunge nessuna.
- Il testo citato e' quello della **v2 su lore**, non quello del ramo: sul
  ramo alcune righe sono gia' diverse.
- Niente e' stato compilato ne' provato: il messaggio lo dice in chiaro,
  in apertura.

## Lo scambio

Spedito il 18/09 alle 09:36 CEST, Message-ID
`<178971697984.34231.15295000197727096742@gmail.com>`. **Recapito
verificato su lore**: indicizzato e agganciato sotto la patch 09/21, non
sotto la cover e non in un thread nuovo. Corpo in
`patches/wip/recensione-09-21.txt`, invio con
`patches/wip/invia-recensione-09-21.sh` (copia dello script gia'
collaudato: destinatari della patch 09/21, `In-Reply-To` sulla patch e non
sulla cover, password chiesta a ogni invio).

## La risposta (18/09, 22:56 CEST)

Sakari ha risposto in circa 13 ore, in copia alla lista, **accettando tutti
e quattro i reperti** e promettendo le correzioni nella v3:

1. tipo di ritorno: "Right", passa a `int` (il `bool` era stato scelto
   prima di capire che serviva gestire gli errori);
2. `NULL` mai restituito: "Indeed. This is where others have tripped,
   too. I'll fix this for v3." Passa a `media_pad_remote_pad_first()` e
   toglie il controllo, perche' `MEDIA_PAD_FL_MUST_CONNECT` garantisce il
   collegamento attivo;
3. stessa cosa sul pad d'ingresso;
4. confermato: lo stream veniva confrontato con quello sbagliato, deve
   venire dal routing. Aggiunge da se' un controllo mancante (entry non
   trovata).

Sulla nota in coda (il nostro puntatore della patch 1): non la liquida, la
riformula come due domande aperte, se quel puntatore possa essere `NULL` in
questo driver ("shouldn't be") e se gli analizzatori statici riescano a
capirlo. E chiude con **"I'll reply to the framework patch separately"**:
e' la nostra patch 2 (`v4l2-subdev.c`), quella che nella replica del 12/09
avevamo chiesto di considerare da sola. Al 19/09 mattina quella risposta
non e' ancora arrivata.

Non serve rispondere: e' un "grazie, lo sistemo nella v3" e un messaggio in
piu' sarebbe solo rumore.

## Prossimo passo

- Aspettare la sua risposta sulla patch 2: **non rispedirla** prima, visto
  che ha detto che ne scrivera'.
- Quando esce la v3 della serie, controllare che le quattro correzioni ci
  siano davvero; se ci sono, un `Reviewed-by` sulla 09/21 e' il modo
  normale di chiudere.

---

## Controllo del 20 settembre 2026

Sul **nostro** thread, niente: la v2 dell'invio 1 e' sempre a sei
messaggi, l'ultimo e' la nostra replica del 12/09. La risposta promessa
sulla patch 2 non e' arrivata. Non e' arrivata nemmeno la v3 della serie
IPU6: il messaggio del 18/09 alle 20:56 UTC — quello in cui accetta i
quattro reperti — e' **l'ultimo messaggio di Sakari su tutta la lista
linux-media**. Il 19 e il 20 non ha scritto a nessuno.

### Il difetto della patch 2 l'ha trovato anche qualcun altro

Il 19/09 alle 16:27 UTC, Nguyen Ngoc Thang ha spedito
`[PATCH] media: v4l2-subdev: fix NULL deref in subdev_open() racing with unbind`
(`20260919162709.314464-1-ngocthang2710.1999@gmail.com`). Stessa funzione,
stessa riga del nostro invio del 12 agosto.

Due cose contano.

**La conferma e' indipendente e automatica.** Nasce da una segnalazione di
**syzbot** (`syzbot+74de6401dbdd377b5746`), con `Cc: stable`. Il crash che
syzbot produce e' sul *secondo* dereference, `sd->entity.graph_obj.mdev`
— cioe' proprio quello che nel nostro messaggio avevamo dichiarato
«trovato leggendo il codice di teardown, non crashandoci sopra». Adesso
crasha da solo, su una macchina che non e' la nostra, sotto KASAN, con
`vimc` al posto dell'IPU6. Non e' piu' uno scenario nostro.

**L'ordine e' pubblico**: 12 agosto noi, 19 settembre lui. Archiviato su
lore, non serve rivendicarlo.

### L'obiezione di Laurent Pinchart, che riguarda anche noi

Laurent ha bocciato quella patch due volte in quindici minuti. La prima:
«this seems the kind of completely wrong fix that would be generated by an
LLM». Alla domanda su come preferirebbe che fosse risolto: «by actually
reasoning about it without the use of an LLM».

> **Correzione del 27/09 (riletto il thread su lore):** Laurent **non** ha
> scritto che la patch "restringe la finestra". Ha scritto solo le due frasi
> qui sopra, senza spiegazioni tecniche. "The patch only narrows the window"
> e' di **Nguyen**, nella sua risposta a Laurent. Quanto segue e' la nostra
> lettura, non la sua: non attribuirgliela mai in un messaggio.

Sotto il tono c'e' un'obiezione tecnica seria: mettere controlli sui
puntatori dentro `subdev_open()` **non chiude la corsa, la restringe**. Il
sub-device puo' sparire subito dopo il controllo, prima che venga chiamata
`internal_ops->open()`. La nostra patch 2 fa nella sostanza la stessa
cosa, quindi e' esposta alla stessa obiezione.

Quello che ci distingue e' gia' scritto nel messaggio della patch: il
paragrafo che spiega **perche'** non basta spostare
`video_unregister_device()` piu' su dentro
`v4l2_device_unregister_subdev()`, cioe' che `v4l2_open()` rilascia
`videodev_lock` prima di chiamare `fops->open()` e l'intera
unregister puo' scorrere li' in mezzo. E' una scelta argomentata, non un
controllo messo a caso. Resta una difesa, non una soluzione: il difetto
di fondo che Laurent indica c'e' anche da noi.

### Le tre strade

1. **Aspettare Sakari.** Decisione presa il 18/09, ancora valida.
2. **Intervenire nel thread di Laurent**: messaggio breve, il difetto e'
   gia' a lore dal 12 agosto, piu' l'analisi del perche' riordinare la
   unregister non basta. Utile — Laurent sta chiedendo esattamente un
   ragionamento — ma il tono del thread e' teso.
3. **Tenere syzbot come argomento** per quando Sakari rispondera': lo
   scenario non e' esotico, un fuzzer ci inciampa da solo.

**Deciso il 20/09: aspettare ancora qualche giorno.** Nessun messaggio
spedito.

### Da tenere d'occhio al prossimo controllo

- La risposta di Sakari sulla patch 2.
- La v3 della serie IPU6, per verificare le quattro correzioni.
- Il thread di Nguyen: se ne esce una v2 o se Laurent indica la strada
  giusta, quella strada vale anche per la nostra patch 2.
- Lo stesso autore ha spedito il 20/09 `[PATCH v1 0/2] Input: sur40 - fix
  UAF/hang on closing the video node after unplug`: difetto diverso,
  driver diverso, ma stessa famiglia della nostra patch 3.

---

## Controllo del 21 settembre 2026

Niente di nuovo. Sakari non ha scritto sulla lista dal 18/09 alle 20:56
UTC (terzo giorno di silenzio): niente risposta sulla patch 2, niente v3
della serie IPU6. Il thread di Nguyen su `subdev_open()` e' fermo ai
quattro messaggi del 19/09, nessuna v2 e nessuna indicazione nuova di
Laurent. Nella posta di Nic nessun messaggio dalla lista. Si continua ad
aspettare; nessun messaggio spedito.

---

## 22 settembre 2026: uscita la v3, e Nic e' in copia

Il 22/09 alle 12:05 UTC Sakari ha pubblicato `[PATCH v3 00/21] IPU6
multi-stream and metadata support preparation`. **Nic e' in Cc su tutti e
22 i messaggi**: nella v2 non c'era. E' il riconoscimento concreto della
recensione del 18/09, anche senza nome nel registro delle modifiche.

Il registro "since v2" elenca tre voci; due sono i nostri reperti:

- *"Rework return values for ipu6_isys_csi2_streaming_change() in patch 9"*
  -> reperto 1
- *"Fix inner loop stream check in ipu6_isys_csi2_streaming_change(), in
  the same patch"* -> reperto 4
- *"Fixed handling failed streamon"* -> patch 01, non nostra

### Verifica punto per punto (testo v3 su Gmail, patch 09 e 16)

1. **Corretto.** La funzione ora e' `int`: 1 = cambia stato, 0 = no,
   negativo = errore. Nella 09 i chiamanti fanno `if (ret <= 0)`; dopo la
   16 un errore negativo va su `goto err_av_del`, che pulisce anche
   `list_add` e `stream_ids`.
2. **Tolto, non corretto nel modo suggerito.** Nel ciclo ora c'e'
   `media_pad_remote_pad_first()` (che `NULL` lo puo' restituire) e
   `container_of_const()` senza nessun controllo: il `dev_dbg()` morto e'
   sparito insieme al controllo. Innocuo se quel collegamento esiste
   sempre, ma non verificato.
3. **Non toccato.** Il pad d'ingresso resta senza controllo; dopo la 16 la
   ricerca e' salita in `enable_streams()`/`disable_streams()`, accanto a
   `vdev_pad = media_pad_remote_pad_unique()` passato a
   `container_of_const()` senza `IS_ERR()`: il nostro vecchio difetto.
4. **Corretto.** La chiave del ciclo interno e' `route->sink_stream`, e la
   16 la conserva.

Il ramo `ipu6`/`metadata` su git.linuxtv.org alle 12:20 UTC **non era
ancora aggiornato alla v3** (conteneva ancora `this_entry->stream`): non
usarlo per confrontare finche' non cambia.

**Sulla patch 2 ancora niente**: Sakari non ha scritto altro dal 18/09.
Nessun messaggio spedito.

### Prossime mosse possibili (da decidere con Nic)

- Rispondere alla 09/21 v3 con un `Reviewed-by` limitato ai punti 1 e 4,
  oppure con una riga di ringraziamento piu' la domanda sul punto 2/3.
- Continuare ad aspettare la risposta annunciata sulla patch 2.

**Deciso il 22/09: aspettare un paio di giorni** (fino al 24-25/09) prima di rispondere alla v3, per lasciare spazio agli altri commenti. Poi si riprende la scelta fra Reviewed-by parziale e silenzio.

---

## Controllo del 23 settembre 2026: primo Reviewed-by sulla v3 (non nostro)

Il 23/09 alle 12:04 UTC **Antti Laakso** (Intel) ha risposto alla cover
letter della v3 con un `Reviewed-by` su tutta la serie, senza commenti.
Nic era in Cc, quindi il messaggio e' arrivato anche nella sua posta.

Controllo fatto su Gmail e su patchwork (il browser non era collegato,
lore non consultato): nessun altro commento sulle 21 patch della v3,
nessuna risposta di Sakari sulla nostra patch 2, nessuna nuova patch di
Sakari dopo la v3, il thread di Nguyen su `subdev_open()` senza novita'
su patchwork. Nessun messaggio spedito.

Per la decisione del 24-25/09: con il `Reviewed-by` di Antti la serie si
avvicina all'ingresso nell'albero. Se si vuole dire qualcosa sui punti 2 e
3 (controlli mancanti su `media_pad_remote_pad_first()` e
`media_pad_remote_pad_unique()`) conviene non aspettare troppo.

### Spedita la risposta alla 09/21 v3 (23/09, 14:54 UTC)

Approvata da Nic, testo in `patches/wip/recensione-09-21-v3.txt`, spedita
con `invia-recensione-09-21-v3.sh`. Recapito verificato su lore: il thread
ha 24 messaggi, il nostro e' agganciato sotto la patch 09 (non sotto la
cover). Una sola copia in Gmail.

Contenuto: grazie per i punti 1 e 4; **solo il punto 2**, riformulato dopo
una verifica nuova: i collegamenti fra i pad sorgente del CSI-2 e i nodi
video nascono con flag `0` (`isys_csi2_create_media_links()`, sia in
mainline sia nel ramo `metadata`), quindi spenti e non immutabili; con due
rotte attive sullo stesso VC e un solo collegamento acceso,
`media_pad_remote_pad_first()` restituisce `NULL` e `av->streaming` viene
letto da un puntatore derivato da `NULL`. Anche senza oops, quella rotta
blocca l'altra per sempre. Proposto `if (!video_pad) continue;`, come
domanda. Oggi i sensori a flusso singolo non ci arrivano (la voce del
frame descriptor manca prima e si esce con `-EINVAL`); ci arriva lo
scenario multi-stream che la serie prepara.

**Lasciato fuori apposta**: il punto 3 (e' lo scenario unbind gia'
respinto) e la patch 2. Nessun `Reviewed-by`: eventualmente dopo la
correzione.

Nota: lo script NON funziona col prefisso `!` di Claude Code (non si puo'
digitare SI); va lanciato da un terminale normale.

---

## 24 settembre 2026: Sakari accetta il punto 2

Il 24/09 alle 10:20 UTC Sakari ha risposto alla nostra mail sulla 09/21 v3
(indirizzata a Nic, linux-media e tutti gli altri in Cc, quindi pubblica):

> Right, indeed that's possible. I'll add the check.

Riconosce che lo scenario (collegamento spento -> `media_pad_remote_pad_first()`
restituisce `NULL`) e' possibile e aggiungera' il controllo `if (!video_pad)`,
presumibilmente nella v4. **Tutti e cinque i reperti mandati sulla 09/21 sono
ora accettati** (1-4 il 18/09, il 2 riformulato oggi).

Controllato su Gmail: nessun altro messaggio nuovo sulla serie, **ancora
niente sulla nostra patch 2** (framework, `v4l2-subdev.c`). Non serve
rispondere: un "grazie" in lista sarebbe solo rumore.

Nota: in Gmail la patch 09, la risposta di Antti e la nostra copia spedita
risultano nel Cestino (probabilmente pulizia a mano); la risposta di Sakari
e' in Posta in arrivo.

### Prossimo passo

Quando esce la v4: verificare che nella 09 (o dove finisce il ciclo dopo la
16) ci sia il controllo su `video_pad`, e se il resto e' invariato dare
`Reviewed-by` sulla 09/21. Il punto 3 resta fuori (e' lo scenario unbind).
Continuare ad aspettare la risposta annunciata sulla patch 2.

---

## Controllo del 27 settembre 2026: uscita la v4 della 09/21

Il 26/09 alle 18:25 UTC Sakari ha pubblicato `[PATCH v4 1/1] media: ipu6:
Start streaming once all streams have started, stop when not`: **solo la
patch 09**, ripubblicata da sola, con Nic in Cc. Registro "since v3":

> Check video_pad isn't NULL in ipu6_isys_csi2_streaming_change().

E' il nostro punto 2. Confrontata riga per riga con la v3 (entrambe da
Gmail): l'unica differenza nel codice sono le tre righe

    if (!video_pad)
            return -EINVAL;

dopo `media_pad_remote_pad_first()`, piu' il `Reviewed-by` di Antti
Laakso. Il resto e' identico.

Differenza rispetto alla nostra proposta: avevamo suggerito `continue`
(ignorare la rotta senza collegamento acceso), lui ha scelto `-EINVAL`
(rifiutare l'avvio). Con `-EINVAL` lo scenario "due rotte sullo stesso VC,
un solo collegamento acceso" non fa piu' oops e non resta appeso: fallisce
subito con un errore. E' una scelta difendibile (una rotta attiva senza
nodo video e' una configurazione sbagliata) e **non vale una replica**.

### Altro in lista, rilevante per noi

- 23-24/09, Felipe Calliari, `[PATCH 0/2] media: ipu6: Stop calling ISR
  hooks of unloaded drivers` (rmmod di isys/psys). Sakari al 24/09 gli ha
  risposto con la **stessa posizione data a noi** ("we currently can't
  safely remove the ISYS driver if the userspace isn't guaranteed to have
  no file handles open") e in piu' **"This patch looks very much
  LLM-generated. Are the tags in Documentation/process/coding-assistants.rst
  relevant for this?"**.
- 24/09, Antti Laakso, `media: ipu6: Fix bus device use-after-free` in
  `ipu6_pci_remove()`: Sakari ha solo aggiunto un `Closes:`.

**Il tag `Assisted-by`**: `coding-assistants.rst` chiede
`Assisted-by: LLM [strumenti]` sulle patch fatte con un assistente IA.
Nessuna delle nostre patch lo ha (21 `Signed-off-by`, zero
`Assisted-by`), nemmeno la patch 2 ancora in attesa. Da aggiungere a ogni
patch futura e a un'eventuale ripubblicazione della patch 2.

Sulla patch 2 ancora niente da Sakari. Nessun messaggio spedito.

### Spedito il Reviewed-by sulla v4 (27/09, 05:03 UTC)

Approvato da Nic, testo in `patches/wip/recensione-09-21-v4-tag.txt`,
spedito con `invia-recensione-09-21-v4.sh`. Recapito verificato su lore:
il thread ha 27 messaggi, il nostro e' agganciato sotto la v4 1/1 (che a
sua volta sta sotto la 09/21 v3). Una sola copia in Gmail.

Contenuto: il controllo su `video_pad` va bene anche con `-EINVAL`;
dichiarazione esplicita che le nostre revisioni sono state fatte con
l'aiuto di un LLM, con la precisazione che l'`Assisted-by` riguarda la
revisione e non la patch; poi `Assisted-by: LLM` e `Reviewed-by`.

Perche' il tag e' sicuro in una risposta: verificato sul sorgente di b4
(`find_trailers`, modo follow-up) che una riga `Xxx-by:` senza indirizzo
email viene scartata, quindi nel commit di Sakari entra solo il
`Reviewed-by`. Patchwork raccoglie solo Acked/Reviewed/Tested e simili.

---

## 27 settembre 2026: patch 2 verificata sul media tree `next`, di nuovo sul server

Il server `192.168.0.2` e' tornato disponibile (chiave SSH nuova). Dopo
il riavvio post-assistenza Nic ha reinstallato gli strumenti
(`apt-get install --no-upgrade`, simulato prima: 0 pacchetti aggiornati,
nessun servizio dell'altro progetto toccato). Server e tablet non si
riavviano fino alla sera del 28/09.

Base scelta: **`next` di `git.linuxtv.org/media.git`**, cima `2dcdfb625c3b`
("media: vivid: drop unused 'j' variable"). E' l'albero dove verrebbe
applicata ed e' la stessa base dichiarata dalla patch di Felipe Calliari
del 23/09. Clone con `--depth 50` in `/media/INTEL-CAMERA/sorgenti/media`.

Esito sulla patch 2 (`patches/wip/invio-1-v2/0002-...patch`, la v2 senza
modifiche):

- `subdev_open()` in `next` e' **identica** a quella che correggiamo: il
  difetto c'e' ancora, nessuna correzione (ne' quella di syzbot/Nguyen)
  e' entrata.
- `git am -3`: **si applica pulita**, senza fuzz.
- `allmodconfig` (`VIDEO_V4L2_SUBDEV_API=y`), `make W=1
  drivers/media/v4l2-core/`, `nice -n 19 -j12`: **zero avvisi, zero
  errori**, sia prima sia dopo la patch. Verificato che l'oggetto fosse
  ricompilato dal sorgente con la patch (`CC [M] ... v4l2-subdev.o` con
  `-Wextra`).
- `checkpatch.pl --strict --codespell`: 0 errori, 0 check, 2 avvisi, tutti
  e due "Unknown commit id" dovuti al clone parziale. I due commit citati
  esistono in mainline con il titolo giusto (verificati sul mirror
  GitHub di torvalds/linux): `61f5db549dde` ("[media] v4l: Make
  v4l2_subdev inherit from media_entity") e `218bf10e39ed` ("media:
  v4l2-subdev: handle module refcounting here").
- `get_maintainer.pl --nogit`: Mauro Carvalho Chehab, linux-media,
  linux-kernel. (Un "Sergey Lebedev" che compare con l'euristica su git e'
  un artefatto del clone parziale: il commit di confine contiene tutto
  l'albero.)

**Non fatto**: nessun avvio sul tablet (niente riavvii fino al 28/09 sera)
e nessuna prova della corsa sul kernel attuale; `sparse` non installato.
Se la patch va ripresentata: dichiararlo sotto il `---`, aggiungere
`Assisted-by: LLM`, aggiornare "unchanged in v7.3-rc2" alla base nuova, e
rispondere nel merito all'obiezione di Laurent Pinchart (il controllo
restringe la corsa, non la chiude). Continuare comunque ad aspettare la
risposta annunciata da Sakari.

### La risposta a Laurent: patch 2 riscritta (v3, non spedita)

L'obiezione di Laurent Pinchart sulla patch di Nguyen vale anche per la
nostra v2: controllare `sd->v4l2_dev` e `sd->entity.graph_obj.mdev` dentro
`subdev_open()` **restringe** la corsa, non la chiude.

Rilettura del 27/09 su `next`:

- Il crash non nasce da un oggetto liberato ma da **due puntatori azzerati
  apposta** da `v4l2_device_unregister_subdev()`: `sd->v4l2_dev = NULL` e,
  via `media_gobj_destroy()`, `sd->entity.graph_obj.mdev = NULL`. Sono
  stato di registrazione del sotto-dispositivo; gli oggetti a cui puntano
  sono ancora vivi.
- Il nodo in `/dev` ha **un suo puntatore** allo stesso `v4l2_device`,
  `vdev->v4l2_dev`: impostato in `__v4l2_device_register_subdev_nodes()`,
  mai azzerato, e coperto dal riferimento che `__video_register_device()`
  prende (`v4l2-dev.c:1105`, `v4l2_device_get()`) e che
  `v4l2_device_release()` rilascia.
- Quindi `subdev_open()` puo' usare `vdev->v4l2_dev->mdev` per tutti e due
  gli usi: non resta niente che lo smontaggio possa cambiare sotto di
  lei. Non e' una finestra piu' stretta, e' nessuna finestra.

La v3 (`patches/wip/subdev-fix-v3/`) cambia **3 righe** invece di 25,
nessun controllo aggiunto. `git am` pulito su `next`, `checkpatch --strict`
0 errori (1 avviso: il solito "Unknown commit id" del clone parziale). Il
messaggio dichiara esplicitamente cosa **non** risolve: la vita del
sotto-dispositivo e del media device quando i loro driver se ne vanno con
file aperti, cioe' proprio la "known limitation" di Sakari.

**Non ancora fatto**: compilazione (in attesa della fine dello stress test
sul server), prova sul tablet (niente riavvii fino al 28/09 sera),
sotto il `---` la nota su cosa e' stato provato, destinatari.

### Secondo punto con lo stesso difetto (trovato leggendo, non riprodotto)

In `subdev_do_ioctl()`, `VIDIOC_G_EXT_CTRLS`, `VIDIOC_S_EXT_CTRLS` e
`VIDIOC_TRY_EXT_CTRLS` passano `sd->v4l2_dev->mdev`. `subdev_do_ioctl_lock()`
controlla `video_is_registered(vdev)`, ma `v4l2_device_unregister_subdev()`
azzera `sd->v4l2_dev` **prima** di `video_unregister_device()`: una ioctl
sui controlli da un file gia' aperto, in quella finestra, dereferenzia
`NULL`. La correzione e' la stessa (`vdev->v4l2_dev->mdev`), ma va in una
patch a parte con il suo `Fixes:`, e il commit che ha introdotto quel
`sd->v4l2_dev->mdev` va trovato su una storia completa (il clone del
server ne ha solo 50 commit).


---

## 27 settembre 2026, pomeriggio: la serie v3 dopo la doppia verifica

Metodo (vedi la memoria "doppia verifica"): prima passata mia con i
controlli meccanici, seconda passata avversariale di **Fable 5.1**, piu'
un revisore del mio modello come confronto. Due giri: sulla patch singola
e poi sulla serie.

La patch 2 e' diventata una **serie v3 di due patch** con lettera
(`patches/wip/subdev-fix-v3/`). E' **v3** perche' su lore esistono solo v1
e v2; la "v3" interna del mattino non e' mai uscita.

- **1/2** `subdev_open()`: usa `vdev->v4l2_dev->mdev` (mai azzerato;
  `v4l2_release()` lo dereferenzia a ogni chiusura) e legge
  `mdev->dev->driver` una volta con `READ_ONCE()`, come
  `dev_driver_string()`, rispondendo `-ENODEV` se il driver del media
  device e' stato staccato. Il driver core lo scrive con `WRITE_ONCE()`
  (`device_set_driver()`, `drivers/base/base.h`).
- **2/2** le tre ioctl `EXT_CTRLS`: `sd->v4l2_dev->mdev` ->
  `vdev->v4l2_dev->mdev`. `Fixes: c41e9cff704a` (Hans Verkuil, 2018),
  trovato sulla storia GitHub e verificato sul diff. Dichiarato "trovato
  leggendo il codice".

Fatti nuovi, tutti verificati sul codice o sulle fonti:

- **vimc** (`vimc_remove()`) chiama `media_device_unregister()` prima di
  `v4l2_device_unregister()`: `graph_obj.mdev` si azzera mentre i nodi
  sono ancora registrati. Spiega perche' syzbot cade sulla *seconda*
  lettura (range 0x0-0x7) e noi sulla prima (0x8).
- **syzbot** ha segnalato il 7 agosto, **prima** del nostro invio del 12;
  il suo registro mostra la scrittura di `vimc.0` in
  `/sys/bus/platform/drivers/vimc/unbind`. La pagina **non ha un
  riproduttore pubblico**: `#syz test` non e' praticabile.
- **Nguyen** aveva un riproduttore (QEMU, KASAN, vimc, 16 thread che aprono
  i nodi contro bind/unbind): 32 crash prima, 0 dopo. E' la strada per
  provare la nostra serie sul server senza toccare il tablet (dopo lo
  stress test: serve un kernel intero e QEMU).
- Message-ID giusti per la lettera: risposta di Sakari alla v2
  `aqUoLr0JFGEBiJIf@kekkonen.localdomain`; nostro ritiro delle patch ipu6
  `178921203630.98144.13238972861597227362@gmail.com` (i vecchi appunti
  riportavano un altro ID: fa fede lore).

Verifiche meccaniche sulla versione finale: `git am` su `next`
`2dcdfb625`; `checkpatch --strict --codespell` 0 errori (solo "Unknown
commit id" da clone parziale); `make W=1 drivers/media/v4l2-core/` con
`allmodconfig` **pulita sia con la sola 1/2 sia con tutta la serie**.

**Manca prima di un eventuale invio**: la prova di funzionamento (tablet
dopo la sera del 28/09, oppure QEMU+vimc sul server), la dichiarazione
delle prove nella lettera (segnaposto `[DA COMPLETARE ...]`), l'ultima
passata di Fable sul testo finale, i destinatari. E resta la regola: non
prima della risposta di Sakari.

### Stato a fine giornata (27/09): serie v3 provata e rivista, non spedita

- **Prova di funzionamento fatta** in QEMU/KVM con KASAN e vimc sul server
  (`test/qemu-subdev-race/`, run 3 in `esiti/2026-09-27-run3/`): senza la
  1/2, 232 null-ptr-deref in `subdev_open()`; con, zero oops/KASAN/WARNING.
  Con la sola 1/2, 232 null-ptr-deref in `subdev_do_ioctl()`; con la serie
  intera, zero. Il difetto della 2/2, trovato leggendo, e' quindi reale.
  Il test e' passato da tre revisioni avversariali di Fable; i run 1 e 2
  avevano difetti del test, documentati nelle rispettive cartelle.
- **Messaggi e lettera aggiornati** con le prove e con cio' che non e'
  stato provato (hardware IPU6, syzbot senza riproduttore pubblico).
  Ultima revisione avversariale di Fable: ogni numero ricalcolato dai log,
  contenuto giudicato pronto, correzioni applicate.
- **Compilazione W=1** sugli stessi commit del test:
  `esiti/2026-09-27-compilazione-w1/`.
- **Manca**: i destinatari. E resta la regola: non spedire prima della
  risposta annunciata da Sakari sulla patch 2.
- Visto di passaggio: il percorso di errore di `vimc_probe()` ha un
  use-after-free quando i minori video finiscono (segnalato da Nguyen il
  19/09 come "unrelated finding"). Possibile patch futura, non ora.

---

## 1 ottobre 2026: sollecito a Sakari sulla patch 2

Controllo del 01/10: sul thread della v2 niente dal 12/09 (19 giorni);
patch v1 e v2 ancora `new` su patchwork linuxtv; thread di Nguyen fermo al
19/09; in Gmail niente dalla lista. Sakari invece e' attivissimo (una
dozzina di messaggi il 01/10, anche sulla serie IPU8): la patch 2 e'
rimasta indietro nella sua coda, non e' lui assente.

Deciso con Nic: **sollecito, non invio della v3**. La regola "non spedire
prima della risposta di Sakari" resta rispettata.

Spedito il 01/10 alle 17:27 UTC, in risposta alla nostra replica del 12/09
(`178921203630.98144.13238972861597227362@gmail.com`), stessi destinatari.
Corpo in `patches/wip/sollecito-patch2.txt`, invio con
`patches/wip/invia-sollecito-patch2.sh`. Contenuto: richiama il suo "I'll
reply to the framework patch separately" del 18/09, gli dice di non
perdere tempo sulla 2/3 v2 perche' c'e' una versione rifatta
(`vdev->v4l2_dev`, piu' la 2/2 sugli EXT_CTRLS), riassume la prova in QEMU
per configurazione (media next: oops in `subdev_open()`; sola 1/2: oops
in `subdev_do_ioctl()`; serie intera: zero), ricorda che il limite sulla
vita degli oggetti resta, e chiede se postare la v3 o se preferisce
commentare prima la v2. Niente syzbot/Nguyen/Laurent: stanno nella lettera
della v3.

### Prossimo passo

Aspettare la risposta. Se dice di postarla: v3 da
`patches/wip/subdev-fix-v3/` (manca ancora la scelta dei destinatari).

---

## Controllo del 4 ottobre 2026

Il dubbio di Nic: progetto arenato, oppure Sakari si e' preso la patch 2?
Verificato:

- **`subdev_open()` in `next`** (git.linuxtv.org, 04/10): ancora la riga
  `if (sd->v4l2_dev->mdev && sd->entity.graph_obj.mdev->dev)`, invariata.
  Nessuno ha corretto il difetto.
- **Patchwork linuxtv** (cercando `subdev`, `v4l2-subdev`, `subdev_open`
  dal 15/09): nessuna patch di Sakari su `v4l2-subdev.c`. Le sue patch dal
  28/09 riguardano IPU6/IPU8 Kconfig, ov05c10, revisori MAINTAINERS e una
  pull per la 7.4. Nella stessa zona solo patch di altri su problemi
  diversi: Heidelberg (`v4l2_subdev_release()`, 17/09) e Hauer
  (`v4l2_subdev_notify()` con SRCU, 24/09). Nguyen: `rejected`.
- **Le nostre 2/3 v1 e v2**: ancora `new`, **nessun delegato** assegnato.
- **Gmail** (Cestino compreso): nessuna risposta dopo il sollecito del
  01/10.
- **Lore** letto solo attraverso il feed salvato il 03/10 mattina (Anubis):
  niente di rilevante.

Conclusione: nessun segno di appropriazione. Il punto e' fermo, ma il
sollecito ha solo 3 giorni, e 2 sono di fine settimana. L'idea
`vdev->v4l2_dev` e' gia' pubblica e datata: sta nel sollecito su lore
del 01/10.

### 4 ottobre, sera: due kernel di debug per la prova sul tablet

Obiettivo: dati sull'hardware IPU6 per la lettera della v3 (prima/dopo,
non un fiume di log). Costruiti sul server, worktree
`/media/INTEL-CAMERA/sorgenti/media-tablet`, `next` a `9cfc1aca0`:

- `tablet-base` = next + `serie/` (gc5035, gc8034, ipu-bridge) + int3472
  + commit **SOLO PROVA** che adatta i due driver alla nuova firma di
  `set_fmt`/`get_selection` (argomento `const struct
  v4l2_subdev_client_info *`, arrivato in `next` dopo il 27/09).
  **La serie dei sensori non compila piu' su `next`: va ribasata prima
  di spedirla.**
- `tablet-v3` = base + le due patch della serie v3, che si applicano
  pulite sul `next` di oggi.

Kernel `7.3.0-rc1-intelcam-debug-g1b4a83d60ea1` (base) e `...-g22c29125bc70`
(v3), config identiche (KASAN, lockdep, UBSAN, KMEMLEAK; wifi, BT e
`uhid` per tastiera e mouse BLE). Copiati in `~/kernel-prova/{base,v3}`.

Script nuovi: `build-tablet-debug.sh` (server), `installa-kernel-prova.sh`
(ESP `/mnt/vmlinuz-new[-v3]` + `initrd-new[-v3]`, moduli in
`/lib/modules`), `prova-serie-v3.sh` (uso normale, corsa open, corsa
ioctl, uso normale, dmesg classificato per fase). Classificatore
verificato sui log del run 3 QEMU: stessi numeri della tabella.

Da sapere leggendo i risultati: gc5035/gc8034 usano `devm_kzalloc()`,
quindi un use-after-free KASAN su un nodo tenuto aperto attraverso
l'unbind e' il limite sulla vita degli oggetti, non un difetto della
serie.

### 4 ottobre, sera: esito della prova sul tablet

Stesso script (`prova-serie-v3.sh`, 300 cicli per fase, 4 lavoratori),
stessa macchina, i due kernel di debug:

| fase                  | base (`g1b4a83d60ea1`)          | v3 (`g22c29125bc70`)                 |
|-----------------------|---------------------------------|--------------------------------------|
| prima (compliance)    | 8/8, 46/46, 46/46, cattura ok   | 8/8, 46/46, 46/46, cattura ok        |
| open gc5035           | **KASAN null-ptr-deref in `subdev_open` al ciclo 4** | 300 cicli, 1,38 M open, 533 ENODEV, 1 WARNING (sotto) |
| open gc8034           | non eseguita (fermata al crash) | 300 cicli, 1,48 M open, 515 ENODEV, nessun reperto |
| ioctl gc5035          | non eseguita                    | 300 cicli, 44 M ioctl, nessun reperto |
| ioctl gc8034          | non eseguita                    | 300 cicli, 37 M ioctl, nessun reperto |
| dopo (compliance)     | non eseguita                    | 8/8, 46/46, 46/46, cattura ok        |

Fuori dalla serie e identici sui due kernel: i WARNING di i915 al boot
(`adlp_tc_phy_connect`, `get_pin_assignment`) e i due in
`ipu6_isys_buffer_list_get` durante la prima cattura.

L'unico reperto della v3: `DEBUG_LOCKS_WARN_ON(lock->magic != lock)` in
`__mutex_lock`, da `__v4l2_subdev_state_alloc()` <- `subdev_open()`.
gc5035 imposta `sd.state_lock = ctrls.lock` e all'unbind
`v4l2_ctrl_handler_free()` fa `mutex_destroy()` su quel mutex: una open
partita prima dell'unbind ha bloccato il lock di un sotto-dispositivo
gia' smontato, in memoria devm non ancora liberata (per questo KASAN
tace). E' il limite sulla vita degli oggetti dichiarato fuori dalla
serie, non un suo difetto. Un caso solo su 1,38 milioni di open.

Per la lettera della v3: il punto "Not tested on the IPU6 hardware" si
puo' sostituire con questi numeri (base: oops al 4o ciclo; v3: 1200
cicli senza oops, un warning da lifetime).

Lettera v3 aggiornata: il punto "Not tested on the IPU6 hardware" e'
sostituito dalla prova sul tablet (tabella base/v3, numeri sommati sui
due sensori, il WARNING spiegato come limite di lifetime). Detto
esplicitamente che sul tablet manca il prima/dopo della patch 2: sul
base la prova si ferma al crash della fase open. **Da fare prima di
spedire:** lo sha di `next` e' scritto abbreviato (`9cfc1aca0`, 9
caratteri): prendere i 12 caratteri dal worktree sul server.

### 4 ottobre, notte: v3 pronta da spedire, invio rimandato a venerdi'

Deciso con Nic: **non si spedisce niente adesso**. Se entro **venerdi'
9 ottobre** Sakari non da' segni di vita (risposta al sollecito del 01/10
o alla v2, commento su patchwork), si spedisce la v3. Se risponde, si
segue quello che dice.

Preparato e verificato sul server (`192.168.0.2`), worktree
`/media/INTEL-CAMERA/sorgenti/v3-invio` (staccato, `next` + serie):

- **`next` invariato** dal 01/10: `9cfc1aca0781` (fetch del 04/10 sera).
- **Le patch da spedire sono quelle provate**: `patch-id --stable`
  identico tra i file di `patches/wip/subdev-fix-v3/` e i commit di
  `tablet-v3` girati sul tablet.
- **`git am`** su `9cfc1aca0781`: pulito.
- **`checkpatch.pl --strict`**: 0 errori, 0 check; 1 avviso per patch,
  "Unknown commit id" sui `Fixes:` (clone parziale; `61f5db549dde`
  verificato su mainline il 27/09). Codespell non girato: dizionario
  assente sul server.
- **W=1** (`allmodconfig` + `VIDEO_V4L2_SUBDEV_API=y`,
  `drivers/media/v4l2-core/`): 0 avvisi, 0 errori su `next`, con la 1/2,
  con la serie; `v4l2-subdev.o` ricompilato ogni volta. Script
  `/media/INTEL-CAMERA/tablet/v3-invio/w1.sh`, log in
  `/media/INTEL-CAMERA/sorgenti/v3-invio-build/`.
- **Tra `2dcdfb625c3b` (base delle prove QEMU) e `9cfc1aca0781`** in
  `drivers/media/v4l2-core/` cambia solo `v4l2-isp.c`: le prove QEMU
  valgono sulla base nuova.

Lettera: compilazione e `base-commit` portati a `9cfc1aca0781`, prove
QEMU dichiarate sulla base vecchia con lo stesso `v4l2-subdev.c`, sha
del tablet a 12 caratteri (il "da fare" sopra e' chiuso).

**Destinatari** (proposta, in `patches/wip/invia-serie-v3.sh` con i
motivi): To Sakari; Cc Mauro, Hans Verkuil (Fixes della 2/2), Laurent
Pinchart (Fixes della 1/2 e obiezione che motiva la v3), Nguyen (patch
citata in [1]), linux-media, linux-kernel. Fuori Antti Laakso (era in Cc
solo per le patch ipu6), stable@ e syzbot (bastano i trailer). Thread
nuovo, `--suppress-cc=all`. Prova a vuoto (`--prova`) riuscita.

**Venerdi', prima dell'invio**: Gmail (Cestino compreso), lore,
patchwork; `git fetch` di `next` e, se si e' mosso, ripetere `git am`,
W=1 e aggiornare sha e `base-commit`. Poi `./patches/wip/invia-serie-v3.sh`.

### 8 ottobre, mattina: invio anticipato di un giorno

Deciso con Nic: si spedisce oggi invece di venerdi' (un giorno non cambia
niente). Controlli della lista "venerdi', prima dell'invio", fatti oggi:

- **Gmail** (Cestino compreso): nel thread della v2 l'ultimo messaggio e'
  il nostro sollecito del 01/10. Niente da Sakari, Laurent, Hans, Mauro.
- **lore**: il web e' dietro Anubis; letto via NNTP
  (`nntp.lore.kernel.org`, ultimi 3000 articoli di linux-media fino al
  08/10 04:16 UTC): nessun messaggio con i nostri Message-ID nei
  References oltre ai nostri.
- **patchwork**: v2 ancora `new`, zero commenti.
- **`next` si e' mosso**: `9cfc1aca0781` -> `8e26d4c20ed2` (133 commit;
  in `drivers/media/v4l2-core/` solo `8761a87af`, `v4l2-common.c`).
  `v4l2-subdev.c` e header coinvolti identici a `9cfc1aca0781` e
  `2dcdfb625c3b`: le prove QEMU e tablet valgono.
- **`git am`** su `8e26d4c20ed2`: pulito, `patch-id --stable` identico
  (`77a0cdda`, `13022d3e`) a quello delle patch provate.
- **W=1** (`w1.sh`): 0 avvisi, 0 errori su `next`, con la 1/2, con la
  serie; `v4l2-subdev.o` ricompilato ogni volta.

Lettera: sha della compilazione e `base-commit` portati a
`8e26d4c20ed2`. Prova a vuoto di `invia-serie-v3.sh --prova` riuscita.

### 8 ottobre, 06:26: v3 spedita

Spedita da Nic con `invia-serie-v3.sh` alle 04:25 UTC. Arrivata su
linux-media (verificato via NNTP), patch in risposta alla lettera:

- lettera: `<20261008042600.275884-1-nicfio@gmail.com>`
  https://lore.kernel.org/linux-media/20261008042600.275884-1-nicfio@gmail.com/
- 1/2: `<20261008042600.275884-2-nicfio@gmail.com>`
- 2/2: `<20261008042600.275884-3-nicfio@gmail.com>`

Prossimo passo: aspettare. Su patchwork la v2 andra' segnata come
superseded (lo fa il manutentore o, con un account, noi).

---

## 8 ottobre 2026: Laurent boccia la v3 1/2, la serie si ritira

Alle 05:48 UTC, 80 minuti dopo l'invio, Laurent Pinchart risponde alla
1/2 (`<20261008054842.GB683793@killaraus.ideasonboard.com>`, letto via
NNTP). Due frasi soltanto:

- sotto "Reproduced on ... 6.12.86": «We don't develop or test patches
  on 6.12.86.»
- sotto il controllo `READ_ONCE(mdev->dev->driver)`: «All of this is a
  hack that may reduce a race window but it doesn't fix the problem.»

Verificate tutte e due sui sorgenti `next` del server (`v3-invio`):

- **6.12.86: fondata.** La prova su `next` c'e' (tablet: oops al 4o
  unbind), ma e' scritta solo nella lettera. Il messaggio della patch
  cita il 6.12.86.
- **"Non risolve": fondata.** La nota del 27/09 ("3 righe, nessun
  controllo, nessuna finestra") valeva per la bozza. La versione spedita
  ha di nuovo un controllo seguito dall'uso:
  - `drv` e' controllato e poi usato. Il cdev del nodo trattiene solo
    videodev (`v4l2_subdev_fops.owner = THIS_MODULE`, `v4l2-dev.c:1061`):
    unbind e `rmmod` del driver tra il `READ_ONCE()` e
    `try_module_get()` fanno leggere `drv->owner` da memoria liberata.
    Ricavato leggendo il codice, non riprodotto.
  - `vdev->v4l2_dev` e' sicuro solo finche' il driver tiene vivi il
    `v4l2_device` e il `media_device`. vimc lo fa (release callback,
    `vimc-core.c:267`). ipu6-isys no: `media_dev` e `v4l2_dev` sono
    dentro `isys`, allocata con `devm_kzalloc()`
    (`ipu6-isys.c:990`), senza release.
  - La 2/2 si basa sullo stesso presupposto (`vdev->v4l2_dev`).

Deciso con Nic: **adeguarsi**. Risposta in
`patches/wip/risposta-a-laurent-v3.txt`, invio con
`patches/wip/invia-risposta-a-laurent-v3.sh` (prova a vuoto riuscita).
Il messaggio ammette tutti e due i punti, spiega i due buchi rimasti e
ritira tutta la serie v3: la soluzione vera e' la gestione della vita
di media device e sotto-dispositivi, non un altro controllo in `open()`.
**Non ancora spedita.**

### Dopo la bocciatura: com'e' fatto lo stato dell'arte (letto via NNTP)

Intestazioni di linux-media da ottobre 2023 a oggi, piu' i messaggi
chiave letti per intero:

- **Hans Verkuil, em28xx (pull per v7.3, 10/07/2026).** Sei patch, la
  centrale e' «use v4l2_device release callback»: la memoria del driver
  si libera nel `release()` del `v4l2_device`, quando l'ultimo nodo e
  l'ultimo file aperto se ne sono andati, non in `disconnect()`/`remove()`.
  Nella lettera della pull: «Hopefully once this is merged people will
  stop posting bad patches trying to fix the lifetime issues.» **E'
  questa la strada che i manutentori accettano: correggere la vita degli
  oggetti nel driver, non aggiungere controlli nel core.**
- La patch di Hans porta `Assisted-by: Claude:claude-opus-4-7`: il
  problema per loro non e' l'LLM, e' la correzione sbagliata.
- **Nessuna serie aperta sulla vita del media device** in questi tre
  anni (in `next` il `media_device` non ha refcount). Sakari ha in corso
  altre serie grandi (metadata/pad interni v12, IPU6 multi-stream,
  supporto ipu7 in ipu6 v4 da 45 patch): il driver IPU6 si muove molto.
- **ipu6-isys**: nessuna patch pubblicata che sposti `isys` (con dentro
  `media_dev` e `v4l2_dev`) dal `devm_kzalloc()` a un release callback.
  Ultima correzione vicina: Antti Laakso, «Fix bus device
  use-after-free» (24/09), su `ipu6_pci_remove()`, altra cosa.
- Thread di Nguyen (19/09): Laurent ha scritto solo le due frasi gia'
  note, nessuna indicazione tecnica.

### 8 ottobre, mattina: revisione della risposta a Laurent prima dell'invio

Regola: nella risposta solo affermazioni verificate su `next`
(`8e26d4c20`) o riprodotte. Esito del controllo sul codice:

- **Sbagliata la premessa del primo punto** («the cdev only holds
  videodev», e qui sopra «il cdev trattiene solo videodev»). Il nodo di
  un sotto-dispositivo e' registrato da
  `v4l2_device_register_subdev_nodes()` con
  `__video_register_device(..., sd->owner)` (`v4l2-device.c:224`), quindi
  il cdev trattiene il modulo **del sotto-dispositivo**:
  - CSI2 di isys: `asd->sd.owner = THIS_MODULE` (`ipu6-isys-subdev.c:348`)
    -> durante `subdev_open()` isys e' bloccato in memoria: niente
    `rmmod`, `drv` resta valido anche se l'unbind azzera `dev->driver`.
  - sensori (gc5035, gc8034): `sd->owner` = modulo del sensore
    (`v4l2-async.c:828`, `v4l2-i2c.c:52`) -> isys **non** e' trattenuto:
    unbind + `rmmod` di isys nella finestra restano possibili.
  La corsa su `drv->owner` vale quindi solo per i nodi dei sotto-
  dispositivi di un altro modulo. Ancora da riprodurre.
- Confermati sul codice: `vimc_v4l2_dev_release()` (`vimc-core.c:267`,
  assegnata a riga 382); `isys` con `media_dev` e `v4l2_dev` dentro
  (`ipu6-isys.h:111-112`) allocata con `devm_kzalloc()`
  (`ipu6-isys.c:990`); la 2/2 usa `vdev->v4l2_dev->mdev`.
- Il kernel di prova sul tablet e' su `9cfc1aca0`; tra questo e
  `8e26d4c20` `ipu6-isys.c` cambia di 21 righe (supporto ipu7), nessuna
  su allocazione, `isys_remove()` o `mutex_destroy()`.

### 8 ottobre, 08:51: unbind di isys con nodi aperti, riprodotto

`scripts/riproduci-uaf-isys.sh` sul kernel base (`g1b4a83d60ea1`,
next `9cfc1aca0`), un processo con `/dev/media0`, `/dev/video0`
(capture isys) e `/dev/v4l-subdev0` (CSI2 di isys) aperti. Esiti in
`data/uaf-isys-7.3.0-rc1-intelcam-debug-g1b4a83d60ea1-20261008-085146/`:

| passo          | esito            | KASAN |
|----------------|------------------|-------|
| unbind isys    | ok               | -     |
| ioctl media    | EIO              | -     |
| ioctl video    | ENODEV           | 3 use-after-free in `v4l2_ioctl` |
| ioctl subdev   | ENODEV           | -     |
| close subdev   | ok               | 9: `v4l2_release`, `subdev_close`, `v4l2_prio_close`, `v4l2_device_release` |
| close video    | ok               | 76: `__vb2_queue_free`, `vb2_core_queue_release`, ... |
| close media    | ok               | -     |

L'oggetto liberato nei rapporti slab (`kmalloc-2k`) e' allocato da
`isys_probe+0x9c` -> `devm_kmalloc` e liberato da
`unbind_store` -> `devres_release_all`. Disassemblato sul server:
`isys_probe` parte a `0x1220`, la chiamata a `devm_kmalloc` con
dimensione `0x7b0` (1968) e `GFP_KERNEL|__GFP_ZERO` ritorna a `0x12bc`
= `+0x9c`: e' `devm_kzalloc(sizeof(*isys))` (`ipu6-isys.c:990`).
`v4l2_device_release()` e `v4l2_prio_close()` leggono dentro quella
struttura: e' il `v4l2_dev` incorporato in `isys`.

**Il secondo punto della risposta a Laurent e' provato** per un file
aperto (non per una `open()` in corso, che non abbiamo riprodotto: va
tolta o provata). Il media device da solo regge: EIO e chiusura pulita.

### 8 ottobre: la finestra su `drv->owner`, vista su ipu6

Prima di costruire il kernel con `msleep()` nella finestra:

- In ipu6-isys `mdev->dev` **non** e' l'auxdev di isys:
  `isys_register_devices()` lo assegna e subito dopo
  `media_device_pci_init()` lo sovrascrive con `&pci_dev->dev`
  (`mc-device.c:869`). Quindi `drv` e' il driver PCI `intel_ipu6`, non
  isys. L'unbind di isys non azzera `mdev->dev->driver`: il controllo
  `!drv` della v3 su ipu6 scatta solo se si scollega il driver PCI.
- Nodi CSI2: il cdev trattiene isys, isys usa simboli di `intel_ipu6`
  (lsmod: `intel_ipu6 ... 1 intel_ipu6_isys`), quindi `drv` resta valido.
- Nodi dei sensori: il cdev trattiene solo gc5035/gc8034. Per liberare
  `drv` nella finestra servono `rmmod intel_ipu6_isys` **e**
  `rmmod intel_ipu6`. In piu' `CONFIG_KASAN_VMALLOC` non e' attivo nei
  kernel di prova: la lettura dalla memoria del modulo liberato non
  darebbe un rapporto KASAN, solo un page fault. Servirebbe una
  ricompilazione completa con KASAN_VMALLOC.

Conclusione: il primo punto della risposta e' vero in generale (il cdev
trattiene `sd->owner`, che puo' non essere il modulo di
`mdev->dev->driver`) ma non e' riprodotto e su ipu6 richiede uno
scenario artificiale. Il secondo punto, riprodotto, basta da solo a
dire che la v3 non risolve.

### 8 ottobre, 09:05: verifica finale della risposta, frase per frase

- 6.12.86 / prove su media next: lettera v3 (QEMU su `2dcdfb625c3b`,
  tablet su `9cfc1aca0781` + driver dei sensori).
- `vdev->v4l2_dev->mdev` nella 1/2 e nella 2/2: dalle patch.
- vimc: `struct vimc_device` contiene `mdev` e `v4l2_dev`
  (`vimc-common.h:136`), liberata in `vimc_v4l2_dev_release()`; ogni
  `video_device` registrato prende un riferimento al `v4l2_device`
  (`v4l2-dev.c:1105`).
- ipu6-isys, devm, liberazione all'unbind: codice `next` + prova KASAN
  (descrizione corretta: anche media aperto, una ioctl per nodo prima
  della close, UAF anche in `v4l2_ioctl`).
- em28xx: serie «fix lifecycle issues» di Hans (v2 16/06, v3 29/06,
  pull per v7.3 il 10/07, `<e94a6342-3731-470e-8c9b-370338daa7c1@kernel.org>`);
  la 2/6 «use v4l2_device release callback» e' in `next` `8e26d4c20`
  (3 righe caratteristiche su 3; il clone del server e' shallow, quindi
  verificato sul contenuto e non sul log).
- Intestazioni: To/Cc identici al messaggio di Laurent (+ noi),
  In-Reply-To e References giusti. Nessun messaggio nuovo nel thread.
Prova a vuoto riuscita.

### 8 ottobre, 09:06: risposta a Laurent spedita, serie v3 ritirata

Spedita da Nic alle 07:06 UTC (Gmail: nel thread della v3, Cc completi).
Prossimo lavoro: la vita degli oggetti in ipu6-isys sul modello della
serie em28xx di Hans (memoria del driver liberata nel release callback
del `v4l2_device`, non con devm), con prova KASAN prima/dopo con
`scripts/riproduci-uaf-isys.sh`. Il tablet va riavviato prima.

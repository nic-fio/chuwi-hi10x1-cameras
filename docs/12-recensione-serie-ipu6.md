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

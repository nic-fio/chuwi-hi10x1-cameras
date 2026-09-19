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

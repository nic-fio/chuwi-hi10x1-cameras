# 11 — Registro delle osservazioni dopo l'invio

Qui si annota **tutto quello che torna indietro** dalle mailing list sui nostri
invii: risposte dei manutentori, commenti di altri sviluppatori, rilievi dei
bot di review, esiti della CI. Una riga per osservazione, con la verifica fatta
sul sorgente e la decisione presa.

## Perche' un registro invece di correggere subito

Le osservazioni arrivano alla spicciolata nell'arco di giorni o settimane; una
v2 si manda **una volta sola**. Rispondere a ogni singolo rilievo con un nuovo
invio ha tre effetti, tutti cattivi: consuma l'attenzione dei revisori, riazzera
la coda di review a ogni giro, e fa sembrare la serie instabile. La forma
attesa e' l'opposto: si raccoglie, si risponde nel thread quando serve, e si
manda una v2 che chiude **tutti** i punti insieme, con sotto il changelog di
cosa e' cambiato dalla v1.

Quindi: qui si accumula, non si patcha. Le patch si scrivono quando scatta una
delle condizioni in fondo.

## Stato degli invii

| # | Cosa | Quando | Stato |
|---|---|---|---|
| 1 | `invio-1-difetti-mainline/` — 3 patch + cover | inviato 2026-08-12 12:53 | **in attesa**: nessuna risposta umana, 1 review automatica |
| 2 | `mc-pipeline-fix/` | non inviato | trattenuto in attesa della prima review vera |
| 3 | `ipu6-lock-fix/` — **2 patch dal 2026-08-22** | non inviato | trattenuto — **O7 fatto**, la modifica che mancava c'e' |
| 4 | `serie/` — i due driver, 5 patch | non inviato | trattenuto |
| 5 | `int3472-leak-fix/` + `int3472/` | non inviato | trattenuto |

L'invio 1 e' su lore:
<https://lore.kernel.org/linux-media/20260812105305.32447-1-nicfio@gmail.com/T/#u>

Le tre patch sono in patchwork di linux-media, tutte in stato **New** (raccolte,
nessuno le ha ancora prese in carico):

| Patch | Patchwork |
|---|---|
| 1/3 ipu6 remote pad | `patch/20260812105305.32447-2-nicfio@gmail.com/` |
| 2/3 v4l2-subdev open | `patch/20260812105305.32447-3-nicfio@gmail.com/` |
| 3/3 ipu6 unbind | `patch/20260812105305.32447-4-nicfio@gmail.com/` |

su `https://patchwork.linuxtv.org/project/linux-media/`.

## Come si controlla se c'e' qualcosa di nuovo

Tre posti, in quest'ordine:

1. **Il thread su lore** (link qui sopra) — le risposte umane compaiono li'
2. **Patchwork**, la riga "Checks" della singola patch — ci finiscono gli esiti
   della CI, con il link al messaggio esteso
3. **La ricerca globale** <https://lore.kernel.org/all/?q=nicfio> — prende anche
   le risposte finite su altre liste

**Serve il browser.** `curl` e `WebFetch` prendono la pagina di Anubis
("Controllo se sei un robot") sia su lore che su patchwork: la richiesta non
arriva mai al contenuto. Con Chrome la sfida si risolve da sola in qualche
secondo.

## Il registro

Legenda della colonna **Chi**: `bot` = review automatica, `umano` = persona,
`noi` = trovato da noi rileggendo dopo l'invio. La colonna **Nostro** dice se
il difetto e' in codice che abbiamo scritto noi: e' la distinzione che decide
se dobbiamo rispondere o no.

| ID | Data | Chi | Patch | Gravita' | Nostro | Cosa | Stato |
|---|---|---|---|---|---|---|---|
| O1 | 2026-08-12 | noi | cover | — | si' | nome di funzione sbagliato nella cover | da correggere in v2 |
| O2 | 2026-08-12 | bot | 3/3 | High | **si'** | manca il lock della coda in `isys_notifier_unbind()` | **verificato, da correggere in v2** |
| O3 | 2026-08-12 | bot | 2/3 | Critical | no, ma sulla riga che tocchiamo | `mdev->dev->driver` dereferenziato senza controllo | da decidere |
| O4 | 2026-08-12 | bot | 1/3 | High | no | `r_pad` NULL in `ipu6_isys_video_set_streaming()` | **verificato** — candidato a patch nuova |
| O5 | 2026-08-12 | bot | 1/3 | High | no | traversata dei link senza `graph_mutex`, TOCTOU e UAF | da valutare |
| O6 | 2026-08-12 | bot | 1/3 | Medium | no | `nlanes = 0` in disable: PHY DWC secondaria non spenta | **non riproducibile qui** |
| O7 | 2026-08-12 | bot | 1/3 | High | no | ritorni di `v4l2_subdev_state_get_*()` non controllati | **tocca l'invio 3**, vedi sotto |
| O8 | 2026-08-12 | bot | 3/3 | Critical | no | `video_device_release_empty` + devres: UAF alla chiusura | solo annotato |
| O9 | 2026-08-12 | bot | 3/3 | High | no | doppio ciclo sbagliato nel percorso d'errore di `isys_register_video_devices()` | **verificato** — candidato a patch nuova |

Da O2 a O9 sono tutte dello stesso messaggio: **Sashiko**, un bot di review AI
agganciato alla CI di `linux-media` (`sashiko-bot@kernel.org`), passato il
2026-08-12 alle 11:05 e alle 11:47. I suoi rilievi sono **osservazioni, non
richieste di modifica**: non sono un manutentore, e sono scritti quasi tutti
come domande. Vanno pesati come qualunque commento di uno sconosciuto, cioe'
verificandoli. Le verifiche fatte sono annotate voce per voce qui sotto.

Messaggi originali, per rileggerli interi:

| Patch | Messaggio |
|---|---|
| 1/3 | `.../media-ci@linuxtv.org/message/EGH4EN5QTUMMOP6XMUCVFELZJTMSSPUJ/` |
| 2/3 | `.../media-ci@linuxtv.org/message/BXHOUJNC5D4GDCHSVVYNQ7Y7L2Y3T36P/` |
| 3/3 | `.../media-ci@linuxtv.org/message/U7ZYOVWMTJCKLHZYQLYCZX6KFMA7SICC/` |

su `https://linuxtv.org/mailman3/hyperkitty/list/`.

---

### O1 — La cover letter dice un nome di funzione che non esiste

Nella copia pubblica della cover, il paragrafo su patch 1 dice che il NULL
dereference e' in `ipu6_isys_csi2_get_remote_desc()`. Quella funzione non
esiste: i punti sono `ipu6_isys_csi2_enable_streams()` e
`ipu6_isys_csi2_disable_streams()`. Corretto in locale con `54d6054`, **dopo**
l'invio, quindi l'archivio conserva la versione sbagliata.

Non merita un invio da solo — e' la cover, non il codice, e le patch dicono la
cosa giusta. Sparisce da se' con la v2.

### O2 — Il rilievo che riguarda codice nostro

**E' l'unico degli otto che il bot marca come "New issue"**, cioe' introdotto
dalla nostra patch, ed e' fondato.

La nostra `isys_notifier_unbind()` cicla sulle code del ricevitore CSI-2 e fa:

```c
if (!vb2_is_streaming(q))
        continue;
vb2_queue_error(q);
```

senza prendere il lock della coda. Un `STREAMOFF` concorrente che si infili fra
il controllo e la chiamata lascia una coda ferma marcata con errore, e quel
flag lo pulisce solo `__vb2_queue_cancel()`: la coda resta avvelenata fino allo
`STREAMOFF` successivo. Il caso simmetrico e' uno `STREAMON` che parta subito
dopo il controllo, e riporta l'appeso che la patch doveva togliere.

**Verificato sul sorgente**, non dedotto:

- il lock di quelle code e' `av->mutex` —
  `ipu6-isys-queue.c:841`, `aq->vbq.lock = &av->mutex`
- prenderlo dentro la `.unbind()` **non** rischia di incastrarsi contro il
  `DQBUF` che stiamo cercando di svegliare: `__vb2_wait_for_done_vb()` fa
  `mutex_unlock(q->lock)` prima di addormentarsi e lo riprende al risveglio
  (`videobuf2-core.c`, commento «Driver's lock is released to allow streamoff
  or qbuf to be called while waiting»)

Quindi la correzione e' fattibile ed e' di poche righe: prendere `q->lock`
attorno al controllo e alla marcatura, per ogni coda.

**Resta da verificare prima di scriverla**: che nessun percorso prenda il lock
del notificatore v4l2-async tenendo gia' `av->mutex`, altrimenti si crea un
ordine inverso.

**Con lockdep non si verifichera'** — decisione di Nic del 2026-08-22, dopo che
l'avvio del kernel di debug ha lasciato la macchina senza schermo esterno, dock
ne' touchscreen (`docs/10-kernel-di-debug.md`, sezione "ANDATA MALE"). Quel
kernel non e' utilizzabile su questo tablet e non si ricompila.

Resta una sola strada praticabile, piu' debole ma legittima: **leggere i
sorgenti** e verificare l'ordine dei lock sui percorsi di chiamata, come fa
qualunque revisore umano. Se il risultato e' pulito, O2 si scrive dichiarando
onestamente **come** e' stata verificata; se resta un dubbio, O2 non si invia.

### O3 — `driver` puo' essere NULL, e la riga e' nostra

La patch 2/3 riscrive il blocco che prende il modulo proprietario:

```c
if (mdev->dev) {
        struct module *owner = mdev->dev->driver->owner;
```

Il bot osserva che `__device_release_driver()` azzera `dev->driver` durante
l'unbind, e che noi non lo controlliamo — piu' un secondo caso, `mdev` liberato
via devres nella stessa finestra, che e' un use-after-free e non si chiude con
un controllo di NULL.

Il difetto e' **pre-esistente** — mainline dereferenzia la stessa catena senza
controlli — ma la riga la stiamo riscrivendo noi, e questo cambia le cose: e'
il posto dove un revisore chiede «gia' che ci sei». Il controllo su `driver` e'
una riga; il use-after-free su `mdev` e' un problema di ciclo di vita che non
va risolto di straforo dentro una patch che parla d'altro.

**Decisione rimandata** a quando risponde un umano: se nessuno lo solleva,
allargare la patch rischia di trasformare una correzione mirata in una
riscrittura, che e' il modo classico per farla respingere.

### O4 — Lo stesso oops, un piano piu' in su

`ipu6_isys_video_set_streaming()` fa, a `ipu6-isys-video.c:1022`:

```c
r_pad = media_pad_remote_pad_first(&av->pad);
r_stream = ipu6_isys_get_src_stream_by_src_pad(sd, r_pad->index);
```

**Verificato: e' vero, e non c'e' nessun controllo.** E' lo stesso difetto che
correggiamo nella patch 1/3, sullo stesso scenario — link rimossi mentre lo
streaming e' acceso — ma su un'altra funzione, che il bot raggiunge per una via
diversa: `unbind` di `intel_ipu6_isys` stesso invece che del sensore.

E' il candidato piu' promettente a **una patch nuova**, perche' e' della stessa
famiglia di quelle gia' inviate, e' piccolo, e sappiamo gia' riprodurre lo
scenario. Prima pero' va provocato davvero: questo progetto non manda patch per
difetti letti e mai visti.

### O5 — TOCTOU sulla traversata dei link

`media_pad_remote_pad_first()` scorre la lista dei link senza `graph_mutex`,
mentre `media_entity_remove_links()` la modifica tenendolo. Il bot ne deduce
possibile corruzione di lista, e comunque un use-after-free su `remote_sd` fra
il momento in cui lo si trova e quello in cui lo si usa.

Se ha ragione, il controllo di NULL che aggiungiamo nella patch 1/3 **riduce**
la finestra ma non la chiude. Nota importante: **non la peggiora**, quindi non
e' un motivo per rivedere quella patch.

Si sovrappone in parte a `mc-pipeline-fix/`, l'invio 2 non ancora partito, che
attacca lo stesso ciclo di vita da un altro lato (i pad che la pipeline tiene
per puntatore dopo che l'entity e' sparita). Da rileggere insieme quando si
prepara quell'invio.

### O6 — Non riproducibile su questa macchina

Il rilievo dice che sul percorso di disable si passa `nlanes = 0`, e che
`ipu6_isys_dwc_phy_set_power()` spegne entrambe le PHY solo dentro un
`if (nlanes == 4)`: in configurazione a 4 lane la secondaria resterebbe accesa.

**La PHY DWC su questa macchina non viene mai usata.** In `ipu6-isys.c:1146-1151`
la scelta e': `jsl` per IPU6SE, **`dwc` solo per `is_ipu6ep_mtl()`** — Meteor
Lake — e `mcd` per tutto il resto, che e' il nostro caso, Alder Lake-N. Il
GC8034 e' effettivamente a 4 lane (`GC8034_DATA_LANES 4`), quindi la
configurazione ci sarebbe, ma passa da un'altra PHY.

Conclusione: plausibile ma **non verificabile qui**, e questo progetto non manda
patch non provate. Annotato e chiuso.

### O7 — Tocca una patch che non abbiamo ancora inviato

Il bot segnala che `v4l2_subdev_state_get_format()` e
`v4l2_subdev_state_get_crop()` possono tornare NULL e che il ritorno viene
dereferenziato subito, in **due** funzioni: `ipu6_isys_fw_pin_cfg()` e
`ipu6_isys_configure_stream_watermark()`.

E' il rilievo piu' utile degli otto, perche' cade proprio su `ipu6-lock-fix/`,
l'invio 3 gia' scritto e non ancora partito. Verificato caso per caso:

| Funzione | Lock | Controllo NULL | Nostra patch |
|---|---|---|---|
| `ipu6_isys_fw_pin_cfg()` | mancava | mancava | **li aggiunge entrambi** |
| `ipu6_isys_configure_stream_watermark()` | **c'e' gia'** (`v4l2_subdev_lock_and_get_active_state`) | **manca** | **non la tocca** |

Quindi il bot ha ragione a meta' sulla seconda funzione — il lock c'e', il
controllo no — e quella meta' e' un buco vero della nostra patch: copre una
delle due funzioni con lo stesso difetto nello stesso file.

**FATTO — 2026-08-22.** `ipu6-lock-fix/` e' ora di due patch: la 0002 aggiunge
i controlli di NULL in `configure_stream_watermark()`. E' una patch separata e
non un'aggiunta alla 0001 perche' sono due difetti diversi — li' un lock
mancante, qui solo i controlli — ma portano lo stesso `Fixes:`.

Il tag e' **verificato sul diff vero**, scaricato da git.kernel.org, non
dedotto: prima di `58410f62e25d` la funzione chiamava
`ipu6_isys_get_stream_pad_fmt()`, che tornava `-EINVAL` quando l'accessore dava
NULL, e il calcolo del pixel rate stava sotto `if (!ret)`. Quel commit ha tolto
l'aiutante e con lui il controllo.

La correzione non inventa un comportamento nuovo: in caso di errore lascia
`pixel_rate` a zero, che e' esattamente cio' che succedeva prima, e il
controllo gia' presente poco sotto disabilita iwake e lo segnala. La funzione
torna `void` e il chiamante non ha percorso d'errore, quindi non c'e' altro da
fare.

Verifiche fatte: `checkpatch --strict` **0 errori 0 check**; compila pulita con
`W=1`. **Non provata a runtime** — richiederebbe il kernel di debug, che e'
stato abbandonato (`docs/10-kernel-di-debug.md`); il difetto e' comunque un
controllo di NULL mancante su un percorso che in condizioni normali non scatta.

**Resta da fare quando l'invio 3 parte**: assemblare le due patch come serie
`[PATCH 1/2]` e `[PATCH 2/2]`.

### O8 — Grosso, strutturale, non nostro

`av->vdev.release = video_device_release_empty` piu' allocazione devres: alla
rimozione del dispositivo la memoria di `isys` e delle code sparisce, ma un
descrittore ancora aperto in userspace fara' `v4l2_release()` su strutture gia'
liberate.

Se e' vero e' grave, ed e' anche il genere di cosa che non si corregge con una
patch di poche righe: vuol dire dare al `video_device` una distruzione a
riferimenti veri. Fuori portata per adesso, e comunque scorrelato dai nostri
invii. **Solo annotato**, per non perderlo.

### O9 — Un difetto piccolo e verificabile a occhio

Il percorso d'errore di `isys_register_video_devices()`:

```c
fail:
        while (i--) {
                while (j--)
                        ipu6_isys_video_cleanup(&isys->csi2[i].av[j]);
                j = NR_OF_CSI2_SRC_PADS;
        }
```

**Verificato leggendo il sorgente: il ciclo e' sbagliato.** Se
`ipu6_isys_video_init()` fallisce con `i == 0`, `while (i--)` e' subito falso e
non ripulisce **niente**, nemmeno gli `av` della porta 0 gia' inizializzati. Se
fallisce con `i == 1`, decrementa `i` a 0 prima del ciclo interno e ripulisce la
porta 0 invece della porta 1.

E' autocontenuto, si spiega in cinque righe di commit message, e non richiede
hardware particolare per essere argomentato — ma richiede di essere **provato**,
e provocare un fallimento di `ipu6_isys_video_init()` non e' immediato. Secondo
candidato a patch nuova, dopo O4.

---

## Quando si manda la v2

Non a numero di osservazioni, ma quando succede una di queste:

1. **Un manutentore risponde chiedendo modifiche.** E' il caso normale: si
   risponde nel thread punto per punto, e la v2 porta le sue richieste **piu'**
   tutto quello che nel frattempo e' maturato qui dentro (oggi: O1 e O2).
2. **Un manutentore dice "applicata".** Allora la v2 non esiste per quella
   patch, e cio' che resta aperto — O2 in testa — diventa una patch a se',
   sopra il codice appena entrato.
3. **Passano 10-14 giorni senza nessuna risposta.** Si manda un ping educato
   sul thread, non una v2. Se anche il ping non muove niente, si rimanda la
   serie con `RESEND` e le correzioni raccolte qui.

Quello che **non** fa scattare una v2 e' un rilievo di un bot, per quanto
corretto. O2 e' reale e va corretto, ma da solo non giustifica di rimandare
tutto: si porta con la prima v2 che parte per un motivo vero.

### Deciso il 2026-08-15

Si aspetta ancora, **non meno di una settimana**: prossimo controllo dal
**22 agosto** in poi. Se a quel punto nessun umano si e' fatto vivo, si smette
di aspettare e si lavora sui rilievi di Sashiko.

Cosa vuol dire in concreto, perche' non sono otto lavori ma due:

| | Cosa si fa | Dove va a finire |
|---|---|---|
| **O2** | prendere `q->lock` attorno al controllo e alla marcatura in `isys_notifier_unbind()` | v2 dell'invio 1, insieme a **O1** (il nome di funzione nella cover) |
| **O7** | aggiungere il controllo di NULL in `ipu6_isys_configure_stream_watermark()` | dentro `ipu6-lock-fix/`, prima che l'invio 3 parta |

Gli altri restano dove sono: **O3** in attesa di un umano, **O4** e **O9**
candidati a patch nuove ma solo dopo averli provocati davvero, **O5**, **O6**
e **O8** annotati e chiusi.

**Prerequisito di O2 — CHIUSO COME LIMITE NOTO, 2026-08-22.** Serviva
verificare con `PROVE_LOCKING` che nessun percorso prenda il lock del
notificatore v4l2-async tenendo gia' `av->mutex`. **Non si fara' con lockdep:**
il kernel di debug e' inservibile su questo tablet (config generata con
`localmodconfig`, mancano 108 dei 210 moduli in uso, touchscreen e USB-C
compresi) e si e' deciso di non ricompilarlo. La verifica, se si fa, si fa
leggendo i sorgenti, e va dichiarata per quello che e'.

## Storico dei controlli

| Data | Cosa e' emerso |
|---|---|
| 2026-08-13 | Primo controllo dopo l'invio. Nessuna risposta umana. Thread integro su lore, 3 patch in patchwork stato *New*. Trovata la review Sashiko del 12/08 — da li' O2..O9. La lista e' attiva (Ailus, Verkuil, Pinchart hanno scritto il 10 e l'11), quindi il silenzio non e' un problema di recapito |
| 2026-08-15 | Secondo controllo. **Niente di nuovo.** Thread lore fermo a 4 messaggi (`newest: 2026-08-12`), ricerca globale `?q=nicfio` 4 risultati su 4 tutti nostri. Le tre patch restano *New*, senza delegato; unica voce in Checks sempre `external-ci/sashiko` → `warning`, nessun check aggiunto. Lista molto attiva il 13 e il 14 (Ruoyu Wang, Pengpeng Hou, Brian Daniels, Thierry Reding, Ribalda), quindi e' coda di review, non lista ferma. Nessuna azione: 3 giorni dall'invio, la finestra del ping e' il 22-26 agosto |
| 2026-08-21 | Terzo controllo, un giorno prima della data fissata. **Nessuna risposta umana, di nuovo.** Thread lore fermo a 4 messaggi (`newest: 2026-08-12`); ricerca globale `?q=nicfio` 4 su 4 tutti nostri; le tre patch sempre *New*, senza delegato, unica voce in Checks `external-ci/sashiko` → `warning`. Lista attivissima (ultimo messaggio il 21 alle 06:40 UTC), quindi resta coda di review. Due cose viste di passaggio, nessuna delle due e' una risposta a noi: (a) `[syzbot] KASAN: slab-use-after-free Read in __vb2_queue_cancel (2)` del 20/08 — **non ci riguarda**, e' il percorso d'errore di `em28xx_v4l2_init()` su USB, non l'unbind di un sensore; (b) `[PATCH 0/2] Fix static analyser and compiler warnings in int3472` di **Sakari Ailus** del 20/08 — tocca `tps68470.c` e `discrete.c`, la nostra C3 tocca `clk_and_regulator.c`: **nessuna sovrapposizione di file, nessun conflitto**. Vale la pena saperlo lo stesso: Ailus e' fra i CC dell'invio 1 e in questi giorni sta lavorando su int3472 |

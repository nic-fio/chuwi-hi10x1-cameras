# Le tre correzioni nuove, provate sul silicio — 2026-08-12, ore 10:55-11:20

Prima di questa sessione C1, C2 e C3 erano **scritte ma mai eseguite**: il
kernel che girava stamattina non le conteneva. Questa e' la prima volta che
girano su hardware.

## Che sono davvero dentro, verificato non dedotto

Il kernel in esecuzione e' la build **#8 del 2026-08-12 ore 10:45**, cioe'
posteriore alla scrittura delle tre patch (10:31-10:37).

Non ci si e' fidati della cronologia. Per ognuna delle cinque correzioni si e'
provato a **disapplicarla** dall'albero compilato con `git apply --check
--reverse`: se torna indietro pulita, e' dentro.

```
DENTRO   ipu6-fix          (A1)
DENTRO   subdev-fix        (A2)
DENTRO   mc-pipeline-fix   (C1)
DENTRO   ipu6-lock-fix     (C2)
DENTRO   int3472-leak-fix  (C3)
```

## Esiti

| Reperto | Come si e' provato | Esito |
|---|---|---|
| **C1** use-after-free in `__media_pipeline_stop()` | 10 cicli di `unbind` a streaming acceso, 5 per sensore, ognuno con chiusura del file | **nessun reperto KASAN** |
| **C2** stato del sub-device letto senza lock | streaming, compliance, 10 cicli di bind/unbind, con lockdep acceso | **`debug_locks: 1`**, nessun reperto |
| **C3** perdita del ritorno di `_DSM` | KMEMLEAK, due passate, dopo avvio completo e ciclo di prove | **0 `unreferenced object`** |

`prova-completa.sh`: **23 verifiche su 23**, 0 fallite.

### Perche' la prova di C1 e' quella giusta e non una approssimazione

Il punto dove viveva l'use-after-free e' `mc-entity.c:946`, raggiunto da:

```
__fput -> v4l2_release -> vb2_core_queue_release -> __vb2_queue_cancel
       -> stop_streaming [intel_ipu6_isys] -> __media_pipeline_stop
```

Cioe' si attraversa **chiudendo il file**, non sganciando il sensore. Ogni
ciclo dello script termina il processo di cattura, quindi ogni ciclo percorre
quella strada per intero. Dieci passaggi, KASAN muto.

### Perche' `debug_locks: 1` e' la parte che conta di C2

Lockdep, quando trova un problema, lo segnala **una volta sola** e poi si
spegne: da quel momento `debug_locks` vale 0 e ogni verdetto successivo sul
locking e' privo di valore, senza che niente lo dica. E' la trappola gia'
annotata in `docs/10-kernel-di-debug.md`.

Dopo tutta l'attivita' di oggi `debug_locks` vale ancora **1**, e le classi di
lock sono salite da 1867 a 1917 con 22792 dipendenze dirette: lockdep ha
lavorato, non e' rimasto fermo. Il "nessun reperto" e' quindi un risultato,
non un silenzio.

## Un reperto nuovo: `DQBUF` non torna mai — candidato C4

Dopo l'`unbind` a streaming acceso, `v4l2-ctl` **non esce da solo**. Resta in
`vb2_core_dqbuf` ad aspettare un fotogramma che non arrivera' mai:

```
[<0>] vb2_core_dqbuf+0x362/0x1190 [videobuf2_common]
[<0>] vb2_dqbuf+0xb4/0x210 [videobuf2_v4l2]
[<0>] __video_do_ioctl+0x894/0xb30
[<0>] v4l2_ioctl+0x198/0x220
[<0>] do_syscall_64+0x101/0x690
```

**Riproducibilita': 10 su 10.** Zero catture uscite spontaneamente, su
entrambi i sensori.

Cosa e' e cosa non e':

- **non e' un blocco del kernel.** Lo stato del processo e' `S`, attesa
  interrompibile: si termina con un segnale e il sistema non ne risente. Per
  questo `DETECT_HUNG_TASK` non dice niente — sorveglia lo stato `D`
- **non e' corruzione.** KASAN tace su tutti e dieci i cicli
- **non e' nostro.** Il sensore sganciato non ha modo di dire alla coda vb2
  che se n'e' andato; il difetto sta nel percorso di mainline
- **e' un difetto visibile a chi usa la camera**: staccare l'hardware sotto un
  programma che cattura lo lascia appeso per sempre invece di dargli un errore

**Corretto in giornata**, vedi la sezione qui sotto.

## C4, dalla scoperta alla patch — ore 11:20-12:00

`isys_async_ops` in `ipu6-isys.c` dichiara `.bound()` e `.complete()` ma
**non `.unbind()`**: quando il sensore se ne va, nessuno lo dice ai nodi
video, e la coda vb2 non viene mai svegliata. L'attesa in
`__vb2_wait_for_done_vb()` finisce su un buffer nuovo, su `!q->streaming` o su
`q->error`, e smontare il sensore non produce nessuno dei tre.

La correzione aggiunge `.unbind()` e chiama `vb2_queue_error()` sulle code del
ricevitore CSI-2 a cui il sensore era attaccato. Solo su quelle **in
streaming**: `q->error` viene azzerato da `__vb2_queue_cancel()`, quindi
marcare una coda ferma la lascerebbe avvelenata fino al successivo
`STREAMOFF`.

Patch in `patches/wip/ipu6-unbind-fix/`. `Fixes: f50c4ca0a820`, cioe' il
commit che ha introdotto il file: verificato sul diff vero via API di GitHub,
che mostra `isys_async_ops` nascere con due sole callback.

### La prova A/B

Il confronto e' a **una sola variabile**: stesso script, stesso kernel, stessa
pipeline, cambia solo il modulo.

| | Cicli appesi | Cicli usciti | Errore restituito |
|---|---|---|---|
| **senza la patch** | 3 su 3 | 0 | — |
| **con la patch** | 0 | 10 su 10 | `-EIO` |

L'errore che arriva in userspace e' `VIDIOC_DQBUF: failed: Input/output
error`, preceduto dai fotogrammi che scorrevano davvero a 28,82 e 23,91 fps.

Sull'archivio di `linux-media`: **nessuno l'ha gia' inviata**, e su
`torvalds/master` di oggi `isys_async_ops` ha ancora due sole callback. La
finestra e' aperta dal 2024-01-31.

## Come una prova puo' mentire, e come ce ne siamo accorti

Vale la pena scriverlo perche' e' passato a un soffio dall'essere creduto.

Dopo aver ricaricato i moduli, il riproduttore ha dato **5 successi su 5**: le
catture "uscivano da sole", esattamente il risultato che la patch doveva
produrre. Era falso. Ricaricando i moduli il grafo media torna ai default e i
link si spengono, quindi `STREAMON` falliva subito con `ENOLINK` e `v4l2-ctl`
usciva in un decimo di secondo — **senza aver mai catturato un fotogramma**.
Lo script contava quell'uscita immediata come una vittoria.

Si e' visto solo perche' si e' andati a controllare quale errore tornasse a
userspace, e la risposta era `STREAMON`, non `DQBUF`.

Adesso lo script **configura la pipeline** riusando `cattura.sh` e **verifica
che lo streaming sia davvero partito** prima di sganciare. Un ciclo in cui la
cattura non e' mai partita non e' un successo: e' un ciclo non valido, e lo
script si ferma con un errore invece di contarlo.

## Difetto dello script, corretto oggi

`unbind-in-streaming.sh` faceva `wait` liscio sul processo di cattura. Con il
blocco qui sopra questo significa **attesa infinita**: la prima esecuzione si
e' impiantata al primo ciclo e ci e' rimasta 16 minuti prima che ce ne
accorgessimo. Lo script ora concede una finestra di grazia, poi termina il
processo, e **conta quanti cicli si sono appesi** invece di nasconderlo. Da
oltre 80 minuti stimati a 50 secondi reali per 5 cicli.

## Rumore di fondo, non nostro e gia' presente

Nel log d'avvio ci sono tre `WARNING` di `i915` sulle porte TypeC, due errori
ACPI del BIOS, SMBus occupato e la scheda audio che rinuncia. Nessuno tocca le
camere.

Attenzione a una lettura sbagliata: dentro i backtrace di quei `WARNING`
compaiono righe come `? __kasan_kmalloc` e `? kasan_quarantine_put`. **Non
sono segnalazioni di KASAN**, sono voci residue dello stack. Una segnalazione
vera comincia con `BUG: KASAN:`, e nel log non ce n'e' nessuna.

## La misura del guadagno mentiva con troppa luce — corretto in serata

Lo stesso principio della sezione precedente, applicato due volte nella stessa
ora. Il `gc5035` ha dato prima 2.83 e poi 10.7 invece di 16, e la prima volta
e' sembrata una regressione dei driver.

Non lo era: con troppa luce il fotogramma a guadagno massimo taglia sul fondo
scala a 1023, e il segnale che manca in cima schiaccia la media.

**La soglia sulla media non basta**, ed e' l'errore del primo tentativo di
correzione. Misurato:

| Guadagno | Media | Massimo | Pixel al fondo scala |
|---|---|---|---|
| 1x | 97,5 | 366 | 0,00% |
| 16x | 421,6 | 1023 | **15,56%** |

Un sesto dell'immagine tagliato, e la media ancora a 421 su 1023: nessuna
soglia sulla media se ne accorge. Il rilevatore giusto e' la **percentuale di
pixel al fondo scala**, soglia 2%, e adesso finisce anche in
`03-guadagno.txt`.

Le due camere guardano da parti opposte, quindi si misura **una alla volta**:
non esiste una posizione della luce buona per entrambe. I due valori validi di
oggi sul kernel #8 sono **15,89x su 16** (scarto 0,69%) e **7,51x su 7,66**
(scarto 1,96%).

## Materiale

| File | Cos'e' |
|---|---|
| `00-kernel.txt` | versione e data di build del kernel provato |
| `05-dmesg-completo.txt` | log d'avvio da journald, `root=UUID=` omesso |
| `06-lockdep.txt` | `/proc/lockdep_stats` a fine prove |
| `07-kmemleak.txt` | esito KMEMLEAK — **vuoto, ed e' il risultato** |
| `08-le-cinque-correzioni.diff` | il diff esatto compilato nella build #8 |

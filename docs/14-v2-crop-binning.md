# 14 — v2 dei driver: crop analogico e binning

Richiesta di Laurent sulla 1/3 (9/10/2026): «Please make the driver freely
configurable, with support for analog crop (and binning if supported by the
device).» Stato dell'arte e piano della serie in `docs/13` (sezione v2).

## Regola sulle fonti (decisione di Nic, 9/10)

Nel driver e nelle mail ogni fatto viene dalle misure sul tablet o da
driver vendor pubblici. In parallelo si chiede il datasheet a GalaxyCore.

## Registri (ricerca del 9/10; [V] = driver vendor pubblici concordi,
## [I] = ipotesi; tutto da misurare)

GC5035 (8 bit, pagine con 0xfe):
- P0 0x09/0a row start, 0x0b/0c col start, 0x0d/0e altezza finestra,
  0x0f/10 larghezza finestra [V]. I vendor non toccano mai larghezza e
  col start (sempre 2608 da 3); riducono l'altezza nei modi veloci.
- P1 0x91/92 y, 0x93/94 x, 0x95/96 altezza, 0x97/98 larghezza di uscita
  [V]. Nelle tabelle vendor l'uscita sta ad almeno 8 dal bordo della
  finestra (4 nel binned).
- P0 0x17 bit0 mirror, bit1 flip [V]; col flip V anche P0 0x54 e P2 0x22
  (0x02/0x7c -> 0x03/0xfc) [V].
- Binning 2x2 a media: P0 0x33 = 0x20 in tutti i modi binned [V]; cambiano
  anche 0x1f, P2 0x14/15, BLK P1 0x49-4b, anti-blooming P1 0x44/4e [V].
  Il modo 1296x972 Intel dimezza anche la PLL (HTS 2920 -> 1460).
  Crop di pagina 1 in coordinate binned.
- Bayer con 0x17 = 0x80: x di uscita pari -> GRBG, dispari -> RGGB [V]
  (Intel x=8 SGRBG, ChromeOS x=7 SRGGB). Intel dichiara SGRBG anche per il
  binned con x=3: probabile errore.

GC8034 (nessun datasheet):
- P0 0x09/0a row start (58), 0x0b/0c col start (4), 0x0d/0e 2464,
  0x0f/10 3284 [V commentati].
- P0 0x91/92 crop y, 0x93/94 crop x, 0x95-98 uscita (pagina 0!) [V].
  P3 0x12/13 LWC MIPI = larghezza * 5/4, da aggiornare [V].
- P0 0x17 = 0xc0 normale, bit0 H, bit1 V [V].
- «Binning»: P0 0xad = 0x30 («binning and scalar»), 0x80 0x13 -> 0x10,
  0x66, 0xbc; finestra, HTS e VTS invariati, stessi fps: probabilmente
  digitale nell'ISP del sensore [V], da misurare (rumore, fps).

## Esperimenti (in ordine di valore)

E1 parità Bayer gc5035 (P1 0x94 8 -> 7); E2 col start e bit0 di 0x0c;
E3 mirror/flip gc5035 e 0x54/P2 0x22; E4 binning gc5035 (tabella 1296x972
e ablazione di 0x33 ecc., rumore su campo piatto); E5 finestra verticale
ridotta e frame length minima; E6 binning gc8034 (fps, rumore); E7 mirror
gc8034; E8 byte alti del crop gc8034; E9 estensione fisica dell'array
(NATIVE_SIZE e CROP_BOUNDS misurati); E10 unità di VTS/VB.

Fonti vendor (URL nel rapporto della ricerca, copiati qui sotto quando
servono): ChromeOS chromeos-4.19 gc5035.c, MTK (Xiaomi, realme, astro),
Exynos 7870/8825, Rockchip, Ingenic, Allwinner, Spreadtrum gc8034_gj_2,
MTK Wiko k300 gc8034 (il più commentato), Ambarella gc8034.

## Risultati del 9/10 (driver da laboratorio, cucina con luce artificiale)

Dati in `data/lab-20261009-*` (in git solo i testi; i .raw no). Confronti
geometrici con `scripts/lab/lab-confronta.py` (media mobile 2x2, quindi
indipendente dalla fase Bayer, risoluzione 1 px, riferiti all'angolo in alto
a sinistra). Sfarfallio della luce misurato: < 0,5% per riga, < 0,2% fra
fotogrammi. Ogni fallimento «CSI» qui sotto = zero fotogrammi e raffica di
errori IPU6 (CRC del payload, header, long packet incompleto, frame/line sync).

GC5035, geometria:
- Parità dell'uscita P1 0x92/0x94: x dispari -> RGGB, y dispari -> BGGR;
  1 px per unità (x 8->7: dx -1).
- Row start P0 0x0a: lineare, 1 riga per unità (0 -> -4, 5 -> +1, 6 -> +2,
  12 -> +8 rispetto a 4).
- Col start P0 0x0c (R9, due corse, piani Bayer separati su 6 fotogrammi
  mediati): dx(c) = 4 * (floor((c - 1) / 2) - 1) colonne rispetto a c = 3
  (1 e 2: -4; 3 e 4: 0; 5 e 6: +4; 7: +8; 11: +16). Passi di 4
  colonne: la fase Bayer non cambia mai. I valori pari danno la stessa
  posizione del dispari precedente ma un'immagine degradata (correlazione
  0,38-0,49 contro 0,85 dei dispari e 0,87 fra due basi; in una corsa un
  piano incoerente). Usare solo valori dispari (i vendor usano 3). Le misure
  del primo giro (spostamenti dispari, piani incoerenti) erano su un solo
  fotogramma e su valori pari: superate.
- Altezza della finestra P0 0x0d/0e: non sposta l'immagine (1962..2000 a row
  start 0: sempre dy -4).
- Area valida (R8, due corse identiche; row start 0, col start 1, finestra
  2040x2640, uscita da 0,0): righe 0-3 fisse a 1019, immagine nelle righe
  4-1967 (1964), poi nero con una banda di 10 righe (1972-1981) e una riga a
  1023 (1992); colonne 0-1 nere, 2-3 a 1023, immagine nelle colonne 4-2611
  (2608), poi 2612-2613 a 1023 e nero. Le misure precedenti con col start 0
  (pari) sono superate. Il fotogramma della tabella (row 4, col 3, uscita
  2592x1944 da 8,8) sta a (8, 8) dentro quest'area: dx = dy = +12 rispetto
  alla cattura dell'area, due corse; restano 8 colonne a destra e 12 righe
  sotto. «Area valida» = la più grande area misurata non costante, non
  l'array fisico.
- Margine fra finestra e uscita: verticale anche 0; orizzontale serve
  x + w <= larghezza finestra - 2 (destra 0 e 1 falliscono, sinistra 0 va).
  Tutti i fallimenti del primo E9 avevano margine destro 0.
- Finestra analogica stretta (1312 colonne da col 651): fotogrammi senza
  errori ma neri (media 0,6 LSB, sotto il nero). Crop orizzontale solo
  d'uscita.
- Finestra verticale ridotta (1016 righe, uscita 1000): 54,4 fps.
- Mirror P0 0x17 bit0: ribaltamento puro. Flip bit1: ribaltamento + 1 riga
  (dy -1, fase verticale cambiata); P0 0x54 = 0x03 e P2 0x22 = 0xfc non
  cambiano nulla di misurabile.

GC5035, binning (ablazione della tabella vendor 1296x972 = PLL P0 0xf5-fa,
«T0» P0 0x21..0xd5, MIPI P3, ISP 0x1f/0x33/P1 0x44-4e/P2 0x14-15, uscita):
- Completa: 1296x972 a 29 fps. Rumore temporale per pixel su 64 fotogrammi
  2,71 -> 1,42 LSB a parità di media; rapporto delle varianze 3,61-3,69 su
  quattro fasce di segnale: media di 4 campioni, non salto (che darebbe ~1).
  Fase RGGB con x=3 y=4 (Intel dichiara SGRBG: sbagliato).
- Senza P3: CSI. Senza PLL: tutto a 1023. PLL+T0+P3 a risoluzione piena: CSI.
- Senza T0: immagine ma niente media (rumore come il pieno, più luminosa).
- Solo 0x33 (senza gli altri ISP): media sì, ma 14,5 fps; gli altri ISP
  dimezzano il tempo di riga.
- Conclusione per il driver: il binning è un preset unico e indivisibile.

GC8034:
- Parità del crop: x 9->8 dx -1, y 8->9 dy +1. Mirror/flip: ribaltamenti
  puri, spostamento zero. Byte alto del crop y (P0 0x91 = 1, y 264):
  dy +256 esatto. Row start 58 -> 0 e crop 8/9 -> 0: dy -66, dx -9 esatti.
- Finestra ridotta a 1200 righe: 26,7 fps. Da row 0: 2464 e 2522 righe ok.
- «Binning» con 0xad = 0x30: CSI, riprodotto in 4 prove alternate con
  0xad = 0x00 (stesso crop 1632x1224 e LWC 2040), che invece va sempre.
  0xad = 0x30 rompe il CSI anche da solo a uscita piena 3264x2448, con i
  quattro registri ISP, con uscita larga 1632 e LWC 2040, e con P3 0x22 =
  0x03 (coppia della prima sezione della tabella globale Rockchip a 4 lane):
  7 combinazioni su 7. P3 0x22 = 0x03 da solo è innocuo (dy -1 al pixel con
  r 0,991, non confermato).
- Tabelle Rockchip (reference/gc8034-rockchip-bsp-4.19.c): il modo 1632x1224
  esiste solo a 2 lane e oltre ai 4 registri ISP cambia P0 0xfc 0xfe -> 0xea,
  P3 0x03 0x92 -> 0x9a, P3 0x22 0x05 -> 0x06, LWC; la nostra tabella a 4 lane
  usa già 0xea, 0x9a e 0x06. Nessuna fonte nota per il binning a 4 lane:
  fuori dalla v2 salvo una fonte nuova.

Rilettura dei registri (driver da laboratorio con debugfs «rilettura»,
R8, 9/10 sera): ogni registro della lista viene riletto subito dopo lo
stream on e di nuovo a cattura finita.
- GC5035: subito dopo lo stream on molti registri di pagina 0 e 2 (row/col
  start, finestra, 0x1f, 0x21, 0x29, 0x33, 0x44, 0x4e, 0x8c, 0xd0, 0xd5, P2
  0x14/15) restituiscono ancora il valore della tabella; a cattura finita
  hanno quello scritto. Sono a doppio buffer, applicati a un confine di
  fotogramma: la verifica valida è quella successiva.
- GC5035 P0 0xf9: scritto 0x12 (tabella vendor del binning), riletto 0x10
  sempre, in tutte e quattro le catture binned. Il bit 1 non resta; il
  binning funziona lo stesso.
- GC8034 P0 0xad: scritto 0x30, riletto 0x30: la scrittura arriva. In una
  corsa, dopo il flusso fallito, la rilettura successiva dava 0x00: non
  spiegato.
- Tutte le scritture delle prove R8 risultano applicate (a parte 0xf9), e i
  fallimenti di E4-noP3, margine destro 0/1 e 0xad si ripetono identici nelle
  due corse: non sono scritture perse o sulla pagina sbagliata.

Strumenti:
- Bug del driver da laboratorio (ereditato da driver-v1, latente lì perché
  l'altezza è fissa): con VBLANK il range dell'esposizione viene modificato
  con default fisso GC8034_EXP_DEF/GC5035_EXP_DEF; se il massimo scende sotto
  il default, __v4l2_ctrl_modify_range() dà -ERANGE e il vblank viene
  rifiutato. Nella v2 il default va limitato al massimo.
- lab-cattura.sh: formato prima dei controlli, vblank per primo, timeout 15 s.

Secondo parere (ChatGPT, 9/10, tre giri; solo revisore di ipotesi ed
esperimenti, nessun fatto sui registri viene da lì). Suggerimenti eseguiti:
ablazione per gruppi, scansione del margine un lato alla volta, rumore per
pixel su 64 fotogrammi, piani Bayer separati. Concordato:
- crop verticale esponibile con bounds = righe davvero valide, non tutta la
  finestra programmabile; orizzontale solo col crop d'uscita, col start
  dispari, margine destro >= 2;
- binning GC5035 come preset unico, chiamato «binning 2x2» (media di 4
  campioni dello stesso colore misurata; analogico o digitale non dimostrato);
- get_selection restituisce il rettangolo programmato davvero; codice Bayer
  misurato per ogni modo e orientamento;
- GC8034 0xad: correlazione causale forte ma manca la rilettura.
Revisione di gpt-5.5 via API (data/chatgpt/crop-binning/01-*), accolta:
- crop orizzontale con il crop d'uscita a passi di 1 px (codice Bayer
  calcolato) o 2 px, col start fisso a 3; i passi di 4 del col start non
  vincolano il left;
- NATIVE_SIZE/CROP_BOUNDS = 2608x1964 (area misurata), CROP_DEFAULT =
  2592x1944 a (8, 8) misurato; binning solo su CROP_DEFAULT finché non è
  provato altrove;
- crop, formato e binning vietati durante lo stream (-EBUSY);
- codice Bayer da parità di left/top, mirror, flip e dalla riga in più del
  flip GC5035;
- formulazioni prudenti: «consistent with averaging four same-colour
  samples», «registers appear to be shadowed», niente funzioni attribuite a
  0xad o al bit 1 di 0xf9; P3 0x22 del GC8034 non si cita.

Fatto la sera del 9/10: rilettura hardware (driver da laboratorio
ricompilato sul server 192.168.0.2, albero driver-v1-tablet, immagine podman
intelcam-build; ricaricato con unbind/rmmod/modprobe a stream fermo, senza
riavvio), area valida e col start (R8, R9). Da fare: correggere il default
dell'esposizione nella v2.
Errore mio corretto in corsa: una «traslazione di dH/2» con la finestra più
alta era un artefatto dell'analizzatore (spostamenti riferiti ai centri);
mandata la correzione anche a ChatGPT, che ha scartato il modello.

## Mappa per il crop della v2 (9/10 sera, R10-R24, due corse ciascuna)

Coordinate del crop = «area valida» (la più grande area misurata non
costante, non l'array fisico).

GC5035 (R10, R16; posizioni esatte al pixel, tempi esatti):
- Le righe/colonne anomale (1019, 1023, nero) sono del sensore, non della
  finestra: con la tabella (row 4, col 3) e uscita da (0, 0) non ce n'è
  nessuna e quel punto è l'origine dell'area.
- area_y = R - 4 + oy, area_x = 4 * floor((C - 1) / 2) - 4 + ox
  (R row start, C col start dispari, (ox, oy) crop d'uscita P1).
- Algoritmo provato: R = top + 4, C = 1, finestra 2616 x height, uscita
  (left + 4, 0) width x height. Limiti 2608x1964, default 2592x1944 a (8, 8)
  = tabella v1. Crop provati: limiti, default, 640x480 al centro, 128x96
  nell'angolo, 64x64: posizioni esatte, nessun errore CSI.
- Tempi a risoluzione piena e col crop: periodo = (height + vblank) * 2920 /
  168,96 MHz, esatto (64x64: 2,212 ms; 640x480: 9,401; 2608x1964: 35,050).
- Binning (R10-R11): con l'uscita binned a (4, 4) il fotogramma è il default
  dimezzato (area 8, 8) e la fase resta GRBG. Il registro della lunghezza del
  fotogramma conta righe del sensore (17,28 us, come a risoluzione piena) e
  il binned non scende sotto ~1996 righe (34,497 ms). Frequenza del
  collegamento nel binned non nota (la tabella cambia PLL e timing MIPI; il
  driver Intel dichiara la stessa LINK_FREQ e tempi che darebbero 57,6 fps,
  sbagliati di 2x): binning rimandato.

GC8034 (R12-R24):
- Tempi: righe del fotogramma = finestra + 20 + blanking (P0 0x07/08),
  riga 16,688 us. Con finestra = height + 16 e uscita a y = 8: blanking =
  vblank - 36, periodo = (height + vblank) * 16,688 us, esatto da 64 a 2448
  righe (1,869 / 2,403 / 2,937 / 4,005 / 5,073 / 7,210 / 8,811 / 41,654 ms).
  Due «anomalie» erano fotogrammi persi in cattura (lab-analizza ora usa la
  mediana e li conta).
- Finestre oltre la riga 2521 del sensore: tempi fuori modello (altezze
  2500/2510: +52/+62 righe; 128x96 in fondo all'area: -8). Area per il crop:
  righe 14-2513 del sensore (2500), colonne della finestra di tabella
  (col start 4, 3284). Righe valide misurate 14-2523 (13 più scura).
- Uscita larga quanto la finestra (margine totale 0): CSI. Margine destro 0
  con sinistro 4, o sinistro 0 con destro 4: ok. Larghezza massima 3280.
- Col start P0 0x0c: solo 2, 4 (tabella), 6 danno immagini coerenti; gli
  altri valori piani incoerenti e diversi fra le corse. Non si tocca.
  Finestra stretta (col 801): funziona ma il registro ignora i 2 bit bassi.
- Algoritmo provato: R = top + 6 (16 bit, P0 0x09/0a), finestra height + 16,
  uscita (left, 8), LWC = width * 5 / 4. Default 3264x2448 a (9, 52) =
  tabella v1 (dy 0 in tre confronti). Estremi provati: crop in cima 3264x2448
  e 640x96, in fondo 640x96 e 640x480: tempi esatti, nessun errore.
  Posizione del 640x480 in fondo non confermata (correlazione 0,38).
- Trappola: la tabella v1 scrive solo i byte bassi di row start e crop
  (0x0a, 0x92, 0x94); un byte alto lasciato da uno stream precedente
  sopravvive finché il sensore resta acceso e rompe lo stream dopo (2 su 3;
  0 su 3 riscrivendo i byte alti). La v2 scrive tutta la geometria a 16 bit
  a ogni avvio.

Regole per la v2 (entrambi):
- geometria e controlli tutti riscritti a ogni stream on;
- limiti di VBLANK ed esposizione ricalcolati a ogni cambio di formato o
  crop; default dell'esposizione limitato al massimo;
- crop, formato vietati durante lo stream;
- left/top e larghezza/altezza ai passi che mantengono il codice Bayer
  (left e top pari nelle coordinate dell'area) e larghezza multipla di 4.

## Driver v2 sul tablet (9/10 sera)

`patches/wip/driver-v2/gc5035.c`, `gc8034.c` (copie della v1 modificate).
Geometria calcolata dal crop a ogni stream on, `set_selection` (CROP),
`set_fmt` che centra il crop come ov01a10 (Hans de Goede: «Center image for
userspace which does not set the crop first»), limiti di HBLANK/VBLANK/
esposizione aggiornati a ogni cambio, crop e formato vietati in stream
(EBUSY). Binning non incluso. Strumenti: `scripts/v2/` (cattura-crop.sh,
scambia-modulo.sh = ricarica a stream fermo senza riavvio, prova-crop.py con
esito automatico e riferimento catturato subito prima di ogni crop,
verifica-posizione.py).

Esiti (data/v2-*):
- A/B v1 -> v2 -> v1 al crop di default: stessa immagine (medie per fase
  uguali al centesimo, spostamento 0) e stesso periodo, su entrambi.
- prova-crop.py, due corse per sensore, 0 KO: rettangolo applicato uguale a
  quello atteso dalle regole (anche per richieste dispari o fuori area),
  periodo uguale al modello, fotogrammi completi, posizione al pixel dove
  la scena ha dettaglio (crop piccoli in zone uniformi: massimo nel punto
  atteso in 9 confronti su 9 ma correlazione 0,3-0,5, quindi prova debole).
- GC8034 PIXEL_RATE corretto a 256 MHz (era 255,91, scelto per 24 fps
  tondi): i periodi misurati, da 1,869 a 41,653 ms, tornano solo così.
- GC8034: larghezze di uscita <= 384 danno flussi rotti (centinaia di buffer
  scartati, fotogrammi saturi, timestamp nulli) anche a 24 fps; >= 448 ok.
  Minimo nel driver: 512. GC5035 a 64 colonne funziona.
- IPU6 oltre ~500 fps (GC8034 64 righe): timestamp nulli o non crescenti;
  GC5035 a 452 fps pulito. Limite del ricevitore, non del driver.
- Deriva lenta di un pixel della scena del GC8034 fra catture distanti un
  minuto (consecutive: 0): per questo il riferimento adiacente.
- v4l2-compliance da git 1616bf9e3c81 con -z: 54/54, 0 avvisi su entrambi
  (spariti i due avvisi della v1 sul CROP non scrivibile).
- libcamera (build in ~/src/libcamera): 60/60 fotogrammi, 0 errori, in tre
  configurazioni per camera.

Revisione del codice v2 di gpt-5.5 (data/chatgpt/crop-binning/02-*):
- accolto: set_fmt ricentrava entrambi gli assi anche cambiandone uno solo
  (GC5035: 2608x1944 spostava il top da 8 a 10); ora per asse, provato.
- accolto: commento GC5035 sull'origine (diceva col start 3, il codice usa 1
  con uscita + 4: equivalenti, riscritto).
- verificato sul tablet: esposizione al massimo e poi crop di 64 righe ->
  esposizione portata al nuovo massimo (112 / 108); vblank al massimo e poi
  crop pieno -> vblank portato al nuovo massimo (14416 / 5743).
- respinto: aggiornare i controlli prima dello stato (il gestore di VBLANK
  legge l'altezza dallo stato attivo; modify_range fallisce solo con limiti
  non validi, qui validi per costruzione); lock (state_lock = lock dei
  controlli dal probe della v1); controllo del pad (lo fa il core).
- checkpatch: una riga di 81 colonne nel GC8034, corretta.

Revisione avversaria (agente con contesto pulito, 9/10 sera): nessun bug
bloccante. Corretto: set_fmt ricentrava sul centro dell'area e non tornava
al default (GC8034: default -> 1920x1080 -> 3264x2448 finiva 26 righe più
su; GC5035 2); ora centra sul crop di default, provato (torna a (8, 8) e
(8, 52)). Allineato a imx219/ov01a10: VBLANK al default a ogni cambio di
dimensione. Aggiunti include minmax.h/align.h, commento sul massimo di 2448
righe del GC8034 (motivo misurato), round_down dell'esposizione al probe del
GC8034, frase ambigua del commento GC5035. Da dire nei messaggi: crop
orizzontale digitale (uscita del sensore), set_selection prima del modello
comune (precedente ov01a10), CROP_DEFAULT diverso da CROP_BOUNDS, set_fmt
che tocca il crop. Lasciato: stato già scritto se update_ctrls fallisce
(limiti validi per costruzione, ov01a10 ignora l'errore). Prova completa v2
(scripts/v2/prova-completa-v2.sh): tutto OK tranne il WARN noto IPU6
ipu6-isys-queue.c:203 (19 volte, come la v1) e l'esposizione dispari non
decidibile per luce.

## Stato dell'arte verificato (ricerca del 9/10 sera, patchwork API)

- IMX908 v3, 1/10/2026: Sakari `<ar5RFpomHbdAAMLx@kekkonen.localdomain>`
  «We don't really have cropping behaviour documented before the common raw
  sensor model. I'd just postpone this...»; Laurent
  `<20261001133138.GM944070@killaraus.ideasonboard.com>` «drop the
  .set_selection() handler and hardcode full resolution ... We'll add it
  back one kernel version later by adding crop support based on the raw
  camera sensor model.»; Sakari `<ar5kBpv8hdkpldp9@kekkonen.localdomain>`
  d'accordo. Citazioni ricontrollate da Claude sul JSON di patchwork 157102.
- Laurent a noi, 9/10 `<20261009094818.GB693830@killaraus.ideasonboard.com>`:
  crop analogico richiesto 8 giorni dopo. Ambiguo.
- Modello comune: v12 (86 patch) tutte «New»; preparazione (argomento
  client_info) accettata; data d'ingresso ignota. Col modello il formato del
  pad interno = array fisico, che non conosciamo.
- Accettati nel 2026 senza set_selection né binning: imx678, imx576,
  os02g10, s5kjn5, ov05c10. Con crop in mainline: ov01a10, t4ka3.
- Assisted-by: formato di Documentation/process/coding-assistants.rst
  dell'albero di destinazione; Sakari chiede se è rilevante.
Decisione proposta a Nic: chiedere a Laurent prima della v2 (crop ora come
ov01a10 o dopo come IMX908) e preparare la serie divisa: patch base senza
tabelle di modo a risoluzione fissa + patch separata col crop.

Posizione al pixel con scena di dettaglio (tazza scura, 9/10 sera,
scripts/v2/prova-posizione.py: crop piccoli scelti dove c'è più gradiente,
riferimento dell'area intera catturato subito prima di ogni crop):
18 crop su 18 esatti (64x64, 128x96, 640x480 sul GC5035; 512x64, 512x256,
640x480 sul GC8034), r 0,91-0,99. verifica-posizione.py ora confronta il
mosaico grezzo: con la media 2x2 due crop del GC8034 davano pareggi a +1
colonna (0,9476 contro 0,9469); sul grezzo +1 dà r circa 0 e il massimo è
nel punto atteso con margine netto. Anche i +1 della prova sulla larghezza
minima erano questo artefatto.

Serie divisa (9/10 sera), ramo driver-v2-diviso nel worktree driver-v2 sul
server; la serie completa resta in driver-v2-completa:
1. media: i2c: Add GC5035 image sensor driver (base: niente tabella di
   geometria, registri calcolati dallo stato, crop fisso = default, come la
   v1; PIXEL_RATE e default dell'esposizione corretti)
2. media: i2c: Add GC8034 image sensor driver (idem)
3. media: ipu-bridge: Add GalaxyCore GC5035 and GC8034 (invariata)
4. media: i2c: gc5035: Add analog crop support (+143 -11)
5. media: i2c: gc8034: Add analog crop support (+143 -9)
L'albero dopo la 5 è identico alla v2 completa. Base provata sul tablet con
prova-completa-v2.sh: tutto OK, compliance 54/54 con i 2 avvisi attesi della
v1 (CROP non scrivibile), WARN IPU6 19 volte. Sorgenti base in
patches/wip/driver-v2-base/.

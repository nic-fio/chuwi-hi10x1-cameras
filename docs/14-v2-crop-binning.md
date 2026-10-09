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
- Col start P0 0x0c: valori dispari = 2 colonne per unità, immagine
  coerente (5: +4,0 px su tutti e quattro i piani Bayer; 11: +16). Valori
  pari = immagine incoerente: i piani delle colonne pari restano fermi, quelli
  delle dispari si spostano di quantità diverse (col 2: 0 / -4 / 0 / -32 px);
  la correlazione globale dava un falso spostamento dispari. Usare solo
  valori dispari (i vendor usano 3).
- Altezza della finestra P0 0x0d/0e: non sposta l'immagine (1962..2000 a row
  start 0: sempre dy -4). Righe attive fino a circa la 1968 della finestra
  (row start 0), poi livello del nero (64) e una riga isolata a 1023.
- Colonne attive: con col start 0 l'immagine finisce alla colonna 2611 della
  finestra; seguono due colonne fisse a 1023, poi nero. Circa 2612 colonne.
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
Da fare: rilettura hardware dei registri a fine sequenza (serve ricompilare
il driver da laboratorio: albero di build su /media/INTEL-CAMERA, non montato
il 9/10); limite inferiore dell'area valida GC5035 (riga ~1968 della
finestra, colonna 2611) da fissare con margine; correggere il default
dell'esposizione nella v2.
Errore mio corretto in corsa: una «traslazione di dH/2» con la finestra più
alta era un artefatto dell'analizzatore (spostamenti riferiti ai centri);
mandata la correzione anche a ChatGPT, che ha scartato il modello.

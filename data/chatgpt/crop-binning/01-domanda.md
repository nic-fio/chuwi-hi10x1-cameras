Ti chiedo una revisione tecnica severa. Contesto: sviluppo driver V4L2 upstream
per due sensori GalaxyCore (GC5035, GC8034; RAW10, MIPI CSI-2 a 4 lane) su un
tablet con Intel IPU6. Il maintainer (Laurent Pinchart) ha chiesto di rendere
i driver liberamente configurabili, con crop analogico e binning dove
supportato. Non uso datasheet: le fonti sono le tabelle di registri dei driver
vendor pubblici e le misure fatte con un driver "da laboratorio". Il progetto
e' seguito da vicino: non posso permettermi affermazioni non dimostrate.
Se non sai cosa fa un registro, dillo; non inventare.

Qui sotto i risultati, cosi' come li ho registrati (in un'altra conversazione
li hai gia' rivisti in parte: ci sono correzioni rispetto ad allora, in
particolare sul col start e sull'area valida).

----
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
  mediati): posizione = 4 * floor((c - 1) / 2) colonne rispetto a c = 1
  (1 e 2: -4 rispetto a 3; 4: 0; 5 e 6: +4; 7: +8; 11: +16). Passi di 4
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
  (pari) sono superate.
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
Fatto la sera del 9/10: rilettura hardware (driver da laboratorio
ricompilato sul server 192.168.0.2, albero driver-v1-tablet, immagine podman
intelcam-build; ricaricato con unbind/rmmod/modprobe a stream fermo, senza
riavvio), area valida e col start (R8, R9). Da fare: correggere il default
dell'esposizione nella v2.
Errore mio corretto in corsa: una «traslazione di dH/2» con la finestra più
alta era un artefatto dell'analizzatore (spostamenti riferiti ai centri);
mandata la correzione anche a ChatGPT, che ha scartato il modello.
----

Domande:
1. Il modello del col start (passi di 4 colonne, valori pari = stessa
   posizione ma immagine degradata) e' sostenuto dai dati? Che cosa
   controlleresti ancora prima di scriverlo in un commit message?
2. Per il GC5035 propongo nel driver v2:
   - NATIVE_SIZE e CROP_BOUNDS = area valida misurata, 2608x1964, con
     origine nella prima colonna/riga d'immagine (colonna 4, riga 4 della
     finestra a col start 1 e row start 0);
   - crop (set_selection V4L2_SEL_TGT_CROP): top libero a passi di 1 riga,
     left a passi di 4 colonne, larghezza e altezza pari; il driver programma
     row start, finestra e crop d'uscita rispettando margine destro >= 2 e
     col start dispari;
   - binning 2x2 come unico preset (set_fmt a meta' del crop), solo con
     crop pieno finche' non provo il binning con crop ridotto.
   Ci sono errori o rischi? Cosa direbbe un revisore del sottosistema media
   su NATIVE_SIZE/CROP_BOUNDS/CROP_DEFAULT in questo caso (righe fisse a
   1019/1023 ai bordi, colonne nere)?
3. I registri a doppio buffer (valore vecchio subito dopo lo stream on):
   che conseguenze hanno per l'aggiornamento dei controlli durante lo
   streaming (esposizione, VBLANK) e per il cambio di crop?
4. GC8034: con 0xad = 0x30 il flusso CSI si rompe in ogni combinazione, la
   scrittura arriva al sensore (rilettura 0x30), il modo esiste nei driver
   vendor solo a 2 lane. E' ragionevole dichiarare il binning GC8034 non
   supportato nella v2 e scriverlo cosi' nella cover letter? Come lo
   formuleresti in modo verificabile?
5. C'e' qualcosa nei risultati che ti sembra sbagliato, non dimostrato o
   misurato male?
Rispondi in italiano, conciso, per punti.

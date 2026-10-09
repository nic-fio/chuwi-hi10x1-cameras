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

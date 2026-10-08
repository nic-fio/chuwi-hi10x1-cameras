# 13 — Driver gc5035/gc8034 verso l'invio upstream (driver-v1)

Dall'8 ottobre 2026 l'obiettivo è uno solo: far entrare i due driver in
mainline. Niente patch sull'unbind (bocciate da Laurent e da Sakari, vedi
`docs/12`). Si spedisce solo quando tutto è in regola.

## Dove sta il lavoro

- Sorgenti dei driver: `patches/wip/driver-v1/gc5035.c`, `gc8034.c` (fonte
  di verità; si copiano nel worktree e si compilano lì).
- Server `192.168.0.2`, worktree `/media/INTEL-CAMERA/sorgenti/driver-v1`,
  ramo `driver-v1-lavoro`, base `next` di media `8e26d4c20` (invariato dal
  01/10 al 08/10).
- Il server ha la radice in RAM: i pacchetti installati spariscono a ogni
  riavvio (l'8/10 mancava `gcc`). La toolchain è un'immagine podman:
  `podman build --network=host -t localhost/intelcam-build /media/INTEL-CAMERA/build/podman`
  (gcc 14.2, sparse 0.6.5-rc1 da git, smatch, coccinelle 1.3, dtschema).
  Si lancia con `podman run --rm --network=host -v /media/INTEL-CAMERA:/media/INTEL-CAMERA ...`.
- Verifica commit per commit: `/media/INTEL-CAMERA/tablet/driver-v1-verifica.sh`.

## Verifiche che dicevano "pulito" senza aver girato

- sparse 0.6.4 di Debian: il kernel lo rifiuta ("not available or not up to
  date") e compila senza controllare. Si vede solo dalle righe `CHECK`.
- coccinelle senza `libpython3.13`: `spatch` fallisce in silenzio su ogni
  script. Controprova obbligatoria: un file con un `if (p) kfree(p)` deve
  far scattare `ifnullfree.cocci`.
- La cover letter di agosto dichiarava "sparse, coccinelle: clean": non era
  dimostrato.

## Rilievi e decisioni

Fonte dei rilievi: ricerca sulle review di linux-media 2024-2026 (gc05a2,
gc08a3, ov05c10, t4ka3, ov02c10, imx471, imx908, ...), ogni punto
verificato sul codice di `next` prima di applicarlo.

| # | Rilievo | Esito |
|---|---|---|
| 1 | `V4L2_SUBDEV_FL_HAS_EVENTS` + subscribe/unsubscribe | **Non serve**: in `next` `v4l2_subdev_init_finalize()` lo imposta da sola (`v4l2-subdev.c:1761`). Aggiunto e poi tolto. Il FAIL 45/46 di agosto era del kernel 7.2: da riverificare sul tablet con `next` |
| 2 | `pm_runtime_get_if_active() <= 0` | **Sbagliato** (era la "correzione" M8 di agosto): con `CONFIG_PM=n` lo stub dà `-EINVAL` e i controlli non venivano mai scritti. Ora `!pm_runtime_get_if_active()`, come dice `camera-sensor.rst` |
| 3 | clock chiesto per nome `"clk"` | Il binding non ha `clock-names`: su DT il probe falliva sempre. Ora `NULL` |
| 4 | clock qualsiasi accettato, link frequency derivata | Ora solo 19,2 MHz (l'unica provata); link frequency e pixel rate costanti. Il racconto della misura va nella cover |
| 5 | `cur_mode` nella struct | Tolto: altezza dallo stato attivo in `s_ctrl`, modo dal formato in `enable_streams` (come imx219) |
| 6 | `disable_streams` restituisce l'errore | Ora 0 e `dev_err` |
| 7 | `-EPROBE_DEFER` a mano sull'endpoint | Tolto: lo fa già `__v4l2_fwnode_endpoint_parse()` con endpoint NULL |
| 8 | ordine dei controlli | `v4l2_fwnode_device_parse` prima, flag dopo `hdl->error`, ctrl_ops NULL per LINK_FREQ/PIXEL_RATE/HBLANK |
| 9 | include | `module.h`, `mod_devicetable.h`, `math.h`, `time64.h`, `build_bug.h`; tolti `acpi.h`, `bits.h`, `math64.h` |
| 10 | gc8034, lista registri unica | Separata in `gc8034_global_regs` (182) + `gc8034_mode_3264x2448` (51), stesso ordine di scrittura. Nel BSP i 233 registri a 4 lane stanno tutti nella lista globale e quella di modo è vuota; il taglio è dove il BSP separa globale e modo nelle liste a 2 lane (SYS, ISP, Crop, MIPI). Verificato con `regtab-to-cci.py --check` |
| 11 | commenti lunghi, racconti nel codice | Accorciati; misure e provenienza nella cover |
| 12 | `link_freq_bitmap` nella struct mai letto (M2 di agosto) | Variabile locale |
| 13 | `8192 * USEC_PER_SEC` in gc8034 | Overflow a 32 bit, c'era già ad agosto. Riscritto in ms; build i386 pulita |
| 14 | messaggi di commit con note interne in italiano ("NON INVIABILE", "PROVATO SU HARDWARE") | Da riscrivere, brevi, in inglese |
| 15 | uso dell'LLM non dichiarato nella cover | Da dichiarare come chiede `generated-content.rst` |
| 16 | binding DT mai provati | Proposta: togliere binding e `of_match_table` (Sakari su imx471 v4: il DT a chi lo userà) |

Rischi aperti, non difetti accertati: guadagno analogico che pilota anche il
digitale (Laurent su ar0234), ordine dei regolatori e ritardi senza fonte,
OTP ignorato, rettangolo di crop della tabella gc8034.

## Ancora da fare

1. Binding DT (16), messaggi di commit (14), cover letter (15).
2. Kernel `next` + serie sul tablet: streaming, `v4l2-compliance -u` completo
   in testo, frame rate, guadagno, test pattern gc5035.
3. Verifica completa ripetuta sulla versione finale, rilettura da capo.

## Kernel di prova sul tablet (8 ottobre, 14:03)

`7.3.0-rc1-intelcam-debug-gbf2e1eb29b92` = `next` 8e26d4c20 + serie
driver-v1 (commit `bf2e1eb29`), config del kernel di debug `isys-pm-fix`
(KASAN, kmemleak, lockdep), 0 avvisi di compilazione. Niente int3472 né
patch ipu6. Sulla ESP come `vmlinuz-new-driver-v1`; `startup.nsh` lo avvia
in automatico, la versione precedente è in `startup-fix.nsh.bak`.
La serie ricostruita dopo (`fbf67ecf5`) differisce solo per tre righe di
commento in gc8034.c.

Prova: `sudo ./scripts/prova-completa.sh`, con una scena illuminata (non
abbagliante) davanti alle due camere.

## Registro completo dei rilievi (richiesto da Nic l'8/10 prima del riavvio)

Regola: prima si raccolgono TUTTI i rilievi ricevuti o prevedibili, poi si
correggono, poi una sola prova sul tablet.

Fonti:

| Fonte | Esito per i driver |
|---|---|
| Sakari 12/09 (invio 1 v2): unbind a streaming acceso non supportato in MC | non riguarda i driver; nessun test di unbind in streaming nella prova |
| Laurent 08/10 (v3 1/2): «non sviluppiamo né proviamo su 6.12.86»; «hack» con controllo seguito da uso | lezioni generali: base e prove solo su `next` (fatto: kernel di prova = next + serie); cercare controlli seguiti da uso nella revisione |
| Sakari 08/10 (v3 2/2): unregister dei nodi subdev non sicuro | non riguarda i driver |
| Sashiko 12/08, O2-O9 (`docs/11`) | tutti su ipu6-isys/v4l2-subdev, patch abbandonate: non applicabili |
| Revisione pre-invio 11/08 (`docs/09`) M1-M8, L1-L5 | M1, M3-M7, L1-L3 risolti nel codice; M2 risolto oggi; M8 era sbagliato, invertito oggi (riga 2 sopra); L4 (`T:`) non va messo; L5 (errori CSI-2 intermittenti gc5035) da ricontrollare nella prova |
| Ricerca sulle review 2024-2026 (agente, 08/10) | righe 1-16 della tabella sopra; aperti: guadagno, accensione, OTP, crop |
| Review 2020 del GC5035 (Sakari, Rob Herring) | agente in corso |
| Revisione avversariale indipendente di gc5035.c e gc8034.c | agenti in corso |
| Modello del guadagno; sequenza di accensione | agenti in corso |

### Rilievi raccolti (da verificare sul codice prima di correggere)

Review 2020 GC5035 (agente, thread V3/v4 letti per intero):
- R20-1 regolatori: iovdd/dovdd prima, almeno 50 µs, poi avdd/dvdd; spegnimento inverso. Figa: «regulator_bulk_enable() is async», Sakari «Ack» (20200831174057.GO31019). Vale per gc5035 e gc8034.
- R20-2 ritardi senza fonte in gc5035 (5 ms); la v4 usava 1200 cicli MCLK prima dell'I2C e 2000 cicli dopo lo stop.
- R20-3 `ret = 0` superfluo in set_ctrl (entrambi).
- R20-4 0xf8=0x49 in gc5035_init_regs è residuo dei 24 MHz (sovrascritto dal modo con 0x58): solo nota, le tabelle restano identiche al vendor.
- R20-5 i modi binned della v4 cambiano anche il PLL: il commento che dichiara sbagliati i loro HBLANK va riformulato.

Revisione avversariale gc8034:
- G8-A set_format ACTIVE riporta l'esposizione al massimo di vts_def ignorando VBLANK: fare come imx219 (riporta anche VBLANK al default).
- G8-B massimo/default dell'esposizione dispari con passo 2: round_down e default fisso.
- G8-C selezioni: tabelle programmano finestra 3284x2464 e crop ISP a (9,8) 3264x2448; il driver dichiara NATIVE_SIZE 3264x2448 e crop a (0,0).
- G8-D offset VTS: il BSP lo dichiara (VB = VTS - 2448 - 36), non è inferito; correggere il commento. PIXEL_RATE ricavato dai fps misurati assorbe un errore dell'offset: misurare fps a due VBLANK.
- G8-E accensione: BSP regolatori in ordine, 100-200 µs, clock, 1 ms, pwdn, 0,5-1 ms, reset, 6 ms + 8192 cicli.
- G8-F pagina 0 non riscritta in set_ctrl/disable_streams: dopo un errore I2C a metà della sequenza bias si scrive in pagina 1.
- G8-G scritture CCI_REG16 con autoincremento mai verificate in scrittura: rileggere 0x03/0x04 e 0x07/0x08.
- G8-I ANALOGUE_GAIN contiene guadagno digitale (UAPI): codici analogici + DIGITAL_GAIN separato.
- G8-J commento su PIXEL_RATE misurato; default esposizione fisso.
- G8-K scrittura guadagno non atomica: al più un commento.

Revisione avversariale gc5035:
- G5-1.1 come G8-A: dopo S_FMT ACTIVE l'esposizione torna a [4, 1992] con VBLANK alto. Con un solo modo: togliere `update_mode_controls` e il ramo ACTIVE di set_format. Default esposizione fisso (0x3d8 = 984 della tabella), limitato al massimo.
- G5-1.2 come G8-F: pagina 0 da ripristinare anche in errore nel test pattern, e prima di STREAM_OFF.
- G5-1.3 esposizione dispari: il vendor arrotonda al pari e compensa col digitale. Da provare sull'hardware (luminosità N contro N+1).
- G5-2.1 come G8-I: ANALOGUE_GAIN con compensazione digitale.
- G5-2.2 DEFINE_RUNTIME_DEV_PM_OPS aggiunge i gestori di system PM (force_suspend/resume); camera-sensor.rst: «should in general not implement the system PM handlers». imx219/ov05c10 usano solo RUNTIME_PM_OPS, gc05a2/gc08a3 come noi. Da decidere.
- G5-2.3 selezioni: finestra 2608x1960 da (4,3) e crop (8,8) in pagina 1; dichiariamo NATIVE_SIZE 2592x1944. Minimo: togliere NATIVE_SIZE come gc05a2; completo: matrice reale.
- G5-3 tabella di modo che ripete quasi tutta quella init, PLL compresa (0xf8: 0x49 poi 0x58): spiegarlo o togliere il doppione; commento che cita gc05a2 da riscrivere.

### Stato dopo le correzioni dell'8/10 sera (serie 56b05476c..5ed52a522)

Chiusi nel codice, confermati da un secondo giro di revisione indipendente
(un revisore per driver, nessun difetto bloccante):
- guadagno (G5-2.1, G8-I): ANALOGUE_GAIN = indice del gradino analogico
  (gc5035 0..16 mappato su 0xb6, gc8034 0..6 = 0xb6 più bias); digitale a
  1x come da tabelle. Niente DIGITAL_GAIN: per gc8034 la larghezza di 0xb1
  non è nota e il BSP non supera ~2,2x, un range sarebbe inventato.
- set_format senza ramo ACTIVE, default esposizione fisso 984 / 2246 (G5-1.1, G8-A)
- esposizione massima pari su gc8034 (G8-B)
- regolatori e ritardi con fonte (R20-1, R20-2, G8-E): gc5035 Figa 2020 +
  Intel, gc8034 BSP develop-5.10; commento falso sul clock gated tolto
- pagina 0 in s_ctrl, nel test pattern anche in errore, prima dello stop (G5-1.2, G8-F)
- selezioni dalla geometria delle tabelle, CROP_DEFAULT costante (G5-2.3, G8-C)
- solo RUNTIME_PM_OPS (G5-2.2)
- offset VTS come formula del BSP (G8-D, commento); pixel rate dichiarato misurato (G8-J)
- PLL ripetuta nella tabella di modo spiegata (R20-4, G5-3); commento binned (R20-5)
- tabelle dei guadagni ridotte ai dati usati (secondo giro)
- VBLANK gc5035 a passo 4 come dichiarano i vendor: valido in entrambe le
  ipotesi, nessuna prova necessaria (secondo giro)
- `ret = 0` superfluo (R20-3)
- L5: non è del driver (stessa firma su gc8034 e su altri sensori IPU6, non
  riprodotto dal 12/08); docs/08 diceva il falso su «mai sul GC8034»

Da chiudere sulla prova (scripts/prova-completa.sh, scripts/prova-csi2.sh):
- G5-1.3 esposizione dispari gc5035 (8 contro 9 righe): se arrotonda, passo 2
- G8-G scritture a 16 bit: rilettura I2C di esposizione e VBLANK
- G8-D offset di gc8034: frame rate a VBLANK 2000, righe in più ricavate
- guadagno minimo/massimo col controllo a indice (15,60 e 7,66)
- v4l2-compliance -u: 0 fallimenti
- L5 prove A-D

Kernel di prova aggiornato (8/10 sera): `7.3.0-rc1-intelcam-debug-g5ed52a522476`
= next 8e26d4c20 + serie 56b05476c..5ed52a522, 0 avvisi di compilazione.
Sostituisce `gbf2e1eb29b92` sulla ESP (`vmlinuz-new-driver-v1`, avviato da
`startup.nsh`); moduli del vecchio tolti. Dopo il riavvio, nell'ordine:
`sudo ./scripts/prova-csi2.sh`, poi `sudo ./scripts/prova-completa.sh`.

### Prova sul kernel g5ed52a522476 (8/10, dopo il riavvio)

`prova-csi2.sh` (data/prova-csi2-20261008-160605): A, B, C, D tutte a 0
righe di errore CSI-2, catture vere (fotogramma 2592x1944 controllato a
parte). L5 non riprodotto, coerente con «non è del driver».

`prova-completa.sh`, prima corsa (data/prova-20261008-160919): 22 OK, 6 KO.
Nessuno dei KO era del driver; quattro erano della prova, corretta:
- scritture a 16 bit rilette 0: i registri sono a doppio buffer. A sensore
  acceso senza stream si legge 0, dopo uno stream il valore della scrittura
  precedente (1112 -> 1111, 1109 -> 1112). La traccia regmap mostra il driver
  scrivere 2 byte su 0x03 (`04 57`, `04 58`). Riletti in streaming:
  gc5035 esposizione esatta (anche 2049), frame length 1944+VBLANK a passo 4
  (301 -> 2244, 302 -> 2248); gc8034 esposizione a passo 2 (1111 -> 1112),
  VB = VTS - 2448 - 36 (264, 265, 266). G8-G chiuso. La prova ora rilegge
  durante uno stream.
- guadagno gc5035 9,76 invece di 15,6: una luce già satura a 1x, lo 0,5% dei
  pixel col 37% di un segnale medio di 9 LSB. Il fotogramma a 1x di quella
  corsa con 15,6x ideale e taglio a 1023 prevede 9,87. La soglia «più del 2%
  di pixel saturi» non lo vede; la prova ora fa il rapporto sui soli pixel
  non saturi nel fotogramma a guadagno massimo.
- curve complete col nero misurato a ogni gradino (64,0-65,2), esposizione
  lunga, nessun pixel saturo: gc5035 1,184 1,428 1,693 2,013 2,382 2,863
  3,379 3,985 4,712 5,650 6,680 7,864 9,316 11,207 13,300 16,086 contro la
  tabella 1,180 ... 15,602 (scarti entro il 3%); gc8034 1,424 1,989 2,818
  3,856 5,539 7,564 contro 7,66 finale. Sul gc8034 il primo fotogramma dopo
  l'avvio ha ancora il guadagno vecchio, il secondo no: la prova usa il secondo.
- `misura-guadagno.sh` usava ancora i valori assoluti (256/4096, 64/490),
  saturati dal controllo a indice: aggiornato agli indici, 3 corse OK.
- 42 BUG/WARNING: tutti `ipu6-isys-queue.c:203` (lockdep_assert in
  ipu6_isys_buffer_list_get, docs/12), uno per stream; righe «lockdep» delle
  tracce contate in più. Nessun messaggio dei sensori.

Seconda corsa (data/prova-20261008-161830): 27 OK, 1 KO (lo stesso WARN
noto, 16 volte), 1 non misurabile.

G5-1.3 chiuso: il gc5035 accetta l'esposizione dispari, il passo 1 resta
(data/esposizione-dispari-20261008, script ultimo.py). Torcia davanti al
sensore frontale, 15,6x, media sui pixel sotto 900 nel fotogramma a 250
righe (97,2%), 16 cicli di 150, 200..208, 250 righe in andata e ritorno.
Quattro cicli avevano un salto di luce a gradino (150 righe a 75,9-76,0
invece di 76,5) e sono esclusi con quel criterio. Sui 12 puliti:
- pendenza 200->208 0,0832 ± 0,0024 LSB/riga, 150->250 0,0837: lineare. Il
  dimezzamento visto nelle corse precedenti era la deriva della torcia.
- passi pari->dispari 200->201 +0,025, 202->203 +0,121 (4,9 sigma),
  204->205 +0,020, 206->207 +0,098 (5 sigma): con l'arrotondamento al pari
  sarebbero tutti 0. Confronto fra-coppie meno dentro-coppia +0,034 ± 0,021
  contro 0 se accetta (1,6 sigma) e 0,167 se arrotonda (6,4 sigma).
- da spiegare, non del driver: i passi hanno periodo 4 righe. 200->202
  0,075, 202->204 0,254, 204->206 0,074, 206->208 0,263 contro 0,167
  uniformi (circa 3,5 sigma). Ogni riga in più aumenta comunque il segnale.

## Revisione «come Sakari» e «come Laurent» (8/10 sera)

Obiettivo di Nic: niente che Laurent o Sakari possano contestare. Due
revisori indipendenti, ciascuno sulle review vere 2025-2026 della persona
(Message-ID nei rapporti), sulla serie 5ed52a522. Nessun difetto bloccante
nel codice. Applicato (serie `70f2a0b04..bce5c5710`, kernel di prova
`gbce5c5710226`; W=1, sparse, smatch, checkpatch --strict, coccinelle
puliti, a parte il Signed-off-by voluto):

- Tabelle senza i registri scritti dai controlli (Sakari su IMX681, S5K3T2,
  t4ka3; ov01a10 nel suo ramo). Stato finale simulato pagina per pagina:
  identico salvo quei registri.
- gc5035: una sola tabella (la init era quasi tutta riscritta dalla modo, PLL
  compresa: Laurent su ov2735). Restano 4 scritture della init (pagina 2,
  0x91-0x94 = 0). 323 -> 160 scritture.
- gc8034: una sola tabella; tolte le impostazioni del modo binned che il BSP
  scrive e poi sovrascrive (ISP, crop, DPC, MIPI). I blocchi SYS restano
  entrambi: fra le commutazioni del clock, e a sensore senza clock i
  registri non tengono le scritture (visto oggi). Gli impulsi 0xfe = 0x10
  restano (non sono pagine). 233 -> 182.
- Registri con nome (Sakari su S5KJN5/IMX471, Laurent su ox05b1s): pagina,
  stream, finestra letta, crop di uscita, lunghezza di riga, PLL del
  gc5035, scritti dalle stesse costanti delle selezioni. Nomi dedotti dai
  valori (1960/2608, 1944/2592, 2464/3284, 2448/3264): detto nel commento.
- Link frequency gc5035 = XCLK x 0xf8 / 4 (24 x 0x49 / 4 = 438, il valore
  vendor; 19,2 x 0x58 / 4 = 422,4): non era «sbagliato», Intel ha cambiato
  la PLL e lasciato la costante. Ora LINK_FREQ è calcolata dalla PLL.
- init_state senza set_fmt con client info NULL (Laurent e Sakari, v7 14/14
  del 02/09: da far notare nelle review); gc*_fill_state.
- .get_frame_desc (Laurent su AR0234). Identico al ripiego dell'IPU6.
- Un solo modo: tolti struct mode, reg_list, v4l2_find_nearest_size.
- Tolti vblank/hblank dalla struct; `return v4l2_ctrl_handler_free()`;
  commenti colloquiali e «Alder Lake-M» tolti.
- Test pattern gc5035: «Color Bar» -> «Test Chart» (è una mira a mosaico,
  data/prova-20261008-161830/gc5035-test-pattern.png).
- Prova completa: nuove sezioni GEOMETRIA (rilettura a stream vivo) e TEST
  PATTERN (mira deterministica: 100% di pixel uguali fra due fotogrammi
  contro 27,8% della scena).

Esperimento del pomeriggio: 0x8c pagina 1 = 0x90 scritto a stream vivo
ferma l'uscita; l'arresto ha poi bloccato l'ISYS fino al riavvio («isys
power cycle required»). La tabella scrive 0x90 all'inizio e 0x10 alla fine:
0x10 è lo stato voluto, il driver è giusto.

Corsa sul kernel `gbce5c5710226` dopo il riavvio (data/prova-20261008-174719):
30 OK, 1 KO, 2 non misurabili. Il KO è il WARN noto `ipu6-isys-queue.c:203`
(19 volte, una per stream; le altre righe contate sono le sue tracce). Nessun
messaggio dei sensori. Non misurabili per la luce: guadagno gc8034 (segnale
64 sul piedistallo 64) ed esposizione dispari gc5035. Frame rate, VBLANK,
16 bit, geometria, test pattern, compliance 46/46 e bind/unbind come prima:
la revisione non ha rotto niente.

Tablet in verticale (data/prova-20261008-175533, output in verdetto.txt):
32 OK, 1 KO (lo stesso WARN, 19 volte), 1 non misurabile. Guadagno gc8034
7,37 contro 7,66 (3,8%), gc5035 15,42 contro 15,60. Esposizione dispari
ancora al buio (64,5 sul piedistallo a 8 righe), ma G5-1.3 è già chiuso con
la torcia. Difetto della prova trovato contando le verifiche: «ipu-bridge ha
collegato le camere» cercava il «Connected 2 cameras» del boot, che il
`dmesg -C` della prova stessa cancella, e senza ramo KO spariva in silenzio
dalla seconda corsa in poi. Ora legge il grafo media (sensore -> CSI2
abilitato), una verifica per sensore.

Da fare, non nel codice:
- Cover letter e messaggi di commit: li riscrive Nic con parole sue
  (Laurent: bot contro i testi da LLM, 25/09). Fatti e numeri per la cover:
  questa pagina e le misure dell'8/10.
- `Assisted-by:` con il modello (Sakari: «Which one?»), attaccato al
  Signed-off-by.
- v4l2-compliance da git (Hans chiede l'hash), output in cover.
- Patch libcamera: helper `AnalogueGainExp` gc5035 1,50 dB/passo, gc8034
  2,95 dB/passo (fit sulle curve misurate, scarto massimo 1,5%), black
  level 4096; senza, l'AE di libcamera prende l'indice per un guadagno.
- In cover: PIXEL_RATE gc8034 > capacità del link è coerente (HTS comprende
  il blanking), PLL non documentata.
- Facoltativi: HFLIP/VFLIP gc8034 (registro 0x17 noto dal BSP), pagine con i
  bit privati CCI.

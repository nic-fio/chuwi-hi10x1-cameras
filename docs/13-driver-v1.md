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

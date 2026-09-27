# Run 2 del test della corsa (27/09/2026, 13:35-13:47 ora italiana)

Tre kernel da media next: base `2dcdfb625`, p1 `683e31f9f` (solo 1/2),
v3 `f07d7e256` (1/2 + 2/2). Un avvio QEMU/KVM per fase, 60 s ciascuna.

## 1/2 (subdev_open): DIMOSTRATA

| kernel | fase | oops in subdev_open | oops/KASAN/WARNING totali |
|---|---|---|---|
| base | open 1 ms | 516 (tetto del test) | 516 |
| base | open 30 ms | 516 (tetto del test) | 516 |
| p1 | open 1 ms / 30 ms | 0 / 0 | 0 / 0 |
| v3 | open 1 ms / 30 ms | 0 / 0 | 0 / 0 |

Tutti gli oops di base sono `KASAN: null-ptr-deref` con RIP in
`subdev_open`. p1+v3: ~8,1 milioni di open riuscite, ~1,15 milioni
respinte con ENODEV, 1437 cicli di unbind/bind, nessun oops/KASAN/WARNING.

## 2/2 (EXT_CTRLS): il difetto esiste, prova non ancora pulita

- p1, ioctl 1 ms: **286 oops `KASAN: null-ptr-deref` in `subdev_do_ioctl`**,
  poi i minori video finiscono ("videodev: could not get a free minor",
  i thread uccisi tengono i nodi), bind con ENFILE (23): avvio NON VALIDO.
- p1, ioctl 30 ms: **301 oops** idem; la riga RACE-PHASE e' spezzata da un
  oops stampato in mezzo e il controllo di validita' non se n'e' accorto
  (buco del test, corretto nel run 3).
- v3, ioctl 1 ms / 30 ms: **0 oops, 0 KASAN, 0 WARNING**, ~928 milioni di
  VIDIOC_G_EXT_CTRLS, ~24 mila ENODEV, 1044 cicli di unbind.

Il difetto della 2/2, trovato leggendo il codice, e' quindi **reale e
riprodotto**. Il messaggio della 2/2 va aggiornato di conseguenza.

## Le altre segnalazioni KASAN in p1 (fasi ioctl)

~3700 `slab-use-after-free` in `v4l2_device_unregister_subdev`,
`v4l2_device_unregister`, `media_device_unregister_entity`. Tutte le
tracce complete passano da `vimc_probe()` -> percorso di errore dopo
"could not get a free minor" -> `v4l2_device_unregister()` su entita' gia'
liberate; le altre sono troncate ("printk messages dropped") ma con le
stesse funzioni e lo stesso task del bind. E' il difetto del percorso di
errore di vimc che Nguyen Ngoc Thang ha descritto come "unrelated
finding" il 19/09: preesistente, non nostro, innescato qui solo perche' i
thread uccisi esauriscono i minori. Non compare mai in v3.

## Correzioni per il run 3

- tetto di ricreazione 100 (sotto la soglia ~280 dei minori)
- pausa di 2 s prima della riga RACE-PHASE (console del kernel svuotata)
- validita' solo con riga RACE-PHASE completa (fino a bind_errno=N)

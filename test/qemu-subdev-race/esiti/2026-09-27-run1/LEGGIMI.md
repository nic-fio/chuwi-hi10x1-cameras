# Run 1 del test della corsa (27/09/2026, 11:19-11:31 ora italiana)

Kernel: media next `2dcdfb625` ("base") e serie v3 `f07d7e256` ("v3"),
x86_64_defconfig + kvm_guest + KASAN inline + vimc, QEMU/KVM 4 vCPU 4 GB.

## Esito

- **base, fase 1 (open, 1 ms)**: 516 oops, tutti `KASAN: null-ptr-deref`
  con RIP in `subdev_open`; 516 = tetto del test (16 + 500 ricreati).
- **base, fase 2**: altri 504 oops in `subdev_open`, poi bind/unbind di vimc
  falliscono a ogni ciclo (825/842). Fasi 3-4 (ioctl) senza vimc attaccato:
  **run NON VALIDO** per la 2/2, come segnalato dal controllo di validita'.
- **v3, 4 fasi**: valide, **0 oops, 0 KASAN, 0 WARNING**; ~4,4 milioni di
  aperture riuscite e ~620 mila respinte con ENODEV durante 716 cicli di
  unbind/bind nelle fasi open; ~990 milioni di VIDIOC_G_EXT_CTRLS riusciti.

## Difetti del test emersi (corretti nel run 2)

1. I thread uccisi lasciano nodi aperti per sempre: dopo ~1000 morti vimc
   non si riattacca piu' (codice d'errore non registrato: da aggiungere).
   Rimedio: un avvio QEMU separato per ogni fase.
2. Nelle fasi ioctl anche l'apertura passa da `subdev_open`: la 2/2 va
   provata su "solo 1/2" contro "1/2 + 2/2", non sul kernel base.
3. I due "NB: nessun oops ..." sono FALSI: `set -o pipefail` + `grep -q`
   che esce presto -> SIGPIPE su awk -> pipeline "fallita".
4. L'attesa lato tablet usava `pgrep -f` e trovava se stessa: ha riportato
   "ancora in corso" per 2 ore a test finito da 1 ora e 50.

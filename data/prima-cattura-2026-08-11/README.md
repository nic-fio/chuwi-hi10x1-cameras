# Prima cattura — 2026-08-11, kernel Debian 6.12.86

Prove della prima esecuzione dei due driver su hardware. Analisi completa in
`docs/08-prova-hardware.md`.

| File | Cos'e' |
|---|---|
| `gc5035-soffitto.png` | frontale, 2592x1944, guadagno 16x — un soffitto |
| `gc8034-scrivania.png` | posteriore, 3264x2448, guadagno 7,7x |
| `gc5035-frame.raw` | un fotogramma grezzo, SGRBG10 in parole a 16 bit |
| `gc8034-frame.raw` | idem, SRGGB10 |
| `compliance-gc5035.txt`, `compliance-gc8034.txt` | `v4l2-compliance`: 45/46 |
| `controlli-gc5035.txt`, `controlli-gc8034.txt` | `v4l2-ctl --list-ctrls` |
| `media-topology.txt` | `media-ctl -p` con il grafo completo |
| `journal-camera.txt` | il journal del kernel, filtrato sulla catena camera |

I `.raw` sono fuori da git (10 e 16 MB). I PNG sono ridotti a 640 px: le
versioni piene si rifanno da `.raw` con `scripts/raw-to-png.py`.

**Le immagini sono tutte fuori dal repository**, dal 2026-08-12: sono
fotografie fatte in casa, e la camera frontale riprende chi sta davanti al
tablet. La regola sta in `.gitignore` con la sua motivazione. Restano sul
disco — il repository e' pubblico, il disco no — e chi vuole rivederle le
trova qui, o le rifa' da `.raw` con `scripts/raw-to-png.py`.

Vale in particolare per `gc8034-scrivania.png`, che ritrae una persona.

## Come sono stati prodotti

```bash
cd build-6.12 && make && sudo ./carica.sh
v4l2-ctl -d /dev/v4l-subdev4 --set-ctrl=analogue_gain=4096   # gc5035, 16x
./scripts/cattura.sh gc5035 3
./scripts/raw-to-png.py gc5035.raw 2592 1944 grbg
```

I numeri di `/dev/v4l-subdev*` e `/dev/video*` cambiano a ogni boot: ricavarli
da `media-ctl -p`, o lasciar fare a `cattura.sh`.

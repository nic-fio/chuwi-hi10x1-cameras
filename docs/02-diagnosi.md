# 02 — Diagnosi

> ## Tutti e tre i blocchi sono chiusi — 2026-08-11
>
> **Questo documento descrive un problema risolto.** Le fotocamere funzionano:
> entrambe fanno probe, leggono il proprio chip ID e catturano
> (`docs/08-prova-hardware.md`). Resta qui perche' e' il ragionamento che ha
> portato alla soluzione, e perche' due dei tre blocchi si sono rivelati
> diversi da come sono descritti sotto.
>
> | Blocco | Come e' finito |
> |---|---|
> | 1 — GPIO controller senza driver | **non era un difetto da correggere**: `pinctrl-alderlake` e' in mainline dalla 5.18, mancava solo nel kernel 7.0 compilato a mano. Il kernel Debian lo ha, e con lui i blocchi 2 e 3 sono caduti da soli |
> | 2 — `int3472` in probe rimandata | conseguenza del 1 |
> | 3 — driver dei sensori inesistenti | **e' l'unico blocco vero**, ed e' il progetto: i due driver sono scritti e girano |
>
> C'era anche un quarto blocco sospettato, `CJAK519`, che **non esisteva**:
> vedi il commit «Chiuso un secondo blocco fantasma».

Perche' le fotocamere non funzionavano. Tre blocchi in cascata: **anche
risolvendone due, non si catturava un fotogramma.**

Sintomo osservabile all'epoca:

```
$ ffmpeg -f v4l2 -i /dev/video0 ...
ioctl(VIDIOC_STREAMON): Link has been severed
```

`ENOLINK` = la pipeline non ha sorgente. IPU6 crea 32 nodi `/dev/video*` e 4
subdev `Intel IPU6 CSI2 0-3`, ma **nessun subdev sensore**.

---

## Blocco 1 — GPIO controller senza driver

**Solo locale. Nulla da inviare a mainline.**

Al boot, 63 volte:

```
int3472-discrete INT3472:01: cannot find GPIO chip INTC1057:00, deferring
int3472-discrete INT3472:02: cannot find GPIO chip INTC1057:00, deferring
...
platform INT3472:01: deferred probe pending: int3472-discrete: Failed to get GPIO
platform INT3472:02: deferred probe pending: int3472-discrete: Failed to get GPIO
```

`INTC1057` (`\_SB.GPI0`) e' il controller GPIO/pinctrl dell'Alder Lake-N.
In questo kernel non lo rivendica **nessun** modulo:

- nessuna voce `INTC1057` in `modules.alias`
- `pinctrl-tigerlake.ko` copre solo `INT34C5`, `INT34C6`, `INTC1055`
- **`pinctrl-alderlake` non e' stato compilato** — ci sono broxton, cannonlake,
  cedarfork, cherryview, denverton, emmitsburg, geminilake, icelake, jasperlake,
  lewisburg, meteorlake, sunrisepoint, tigerlake, e non alderlake

`INTC1057` e' mappato su `adln_soc_data` in
`drivers/pinctrl/intel/pinctrl-alderlake.c`, sotto `CONFIG_PINCTRL_ALDERLAKE`,
**in mainline dalla 5.18** e presente in 7.0/7.1.

Conseguenza: nessun GPIO chip -> `int3472` non ottiene reset/powerdown/clock ->
i sensori resterebbero non alimentati **anche avendo i driver**.

Fix locale: `./scripts/fix-pinctrl-alderlake.sh`.

---

## Blocco 2 — Nessun driver per i due sensori

**Questo e' il lavoro upstream vero.**

`/lib/modules/7.0/kernel/drivers/media/i2c/` contiene 42 moduli: tutti decoder
video e deserializzatori (adv7604, tvp5150, max9286, ds90ub9xx...) piu' il VCM
`dw9768`. **Zero driver di image sensor.** Nessuno nemmeno builtin.

Ma il punto non e' il `.config` locale: **`gc5035` e `gc8034` non esistono in
mainline**, in nessuna versione. In `drivers/media/i2c/Kconfig` non ci sono
`VIDEO_GC5035` ne' `VIDEO_GC8034`. Non c'e' opzione da abilitare.

Stato del codice esistente altrove:

| Sensore | Codice esistente | Utilizzabile? |
|---|---|---|
| GC5035 | patch out-of-tree Intel, `ipu6-drivers/patch/gc5035-on-adlm/` | da portare da ADL-M ad ADL-N |
| GC8034 | driver BSP Rockchip `gc8034.c`, device-tree | da riscrivere per x86/ACPI |

---

## Blocco 3 — `ipu-bridge` non conosce questi sensori

La tabella `ipu_supported_sensors[]` in
`drivers/media/pci/intel/ipu-bridge.c` elenca gli HID ACPI per cui il kernel
costruisce il grafo fwnode (software node) che collega il sensore alla porta
CSI-2. HID presenti nel modulo compilato:

```
HIMX11B1 HIMX2170 HIMX2172 INT0310  INT33BE  INT33F0  INT343E  INT3474
INT3479  INT347A  INT347E  INT3537  INTC10C5 OVTI01A0 OVTI01AS OVTI02C1
OVTI02E1 OVTI05C1 OVTI08A1 OVTI08F4 OVTI13B1 OVTI2680 OVTI8856 OVTIDB10
SONY471A XMCC0003
```

**Nessun `GCTI*`.** Senza voce qui, anche con i driver dei sensori nessun link
CSI-2 verrebbe creato.

---

## Stato dei semafori

`collect-diag.sh` li stampa a ogni esecuzione. Snapshot iniziale
(`data/20260811-112600`, kernel 7.0 locale):

```
[KO] pinctrl-alderlake ASSENTE  -> INTC1057 senza driver
[KO] nessun gpiochip            -> int3472 non puo' agganciarsi
[KO] INT3472:01 NON agganciato  -> niente clock/reset ai sensori
[KO] ipu-bridge senza voci GCTI -> nessun grafo fwnode CSI-2
[KO] gc5035/gc8034 ASSENTI      -> nessun subdev sensore
```

Obiettivo: cinque `[OK]` su kernel **vanilla**, ottenuti solo tramite `.config`.

---

## Nota metodologica

Il journal di questa macchina **non e' persistente** (`/var/log/journal`
assente) e il ring buffer del kernel si satura in poche ore: i messaggi di boot
dell'IPU6 erano gia' stati sovrascritti alla prima analisi, il che ha nascosto
il Blocco 1. Prima di ogni sessione di debug:

```
sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald
```

Attenzione anche ai `grep` su `dmesg`: le righe `Modules linked in:` dei
WARNING i915 contengono `ipu6` e `int3472` e inquinano qualsiasi ricerca.
`collect-diag.sh` le filtra.

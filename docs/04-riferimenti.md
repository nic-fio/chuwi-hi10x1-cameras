# 04 — Riferimenti

## Documenti normativi — leggere questi per primi

- [**`camera-sensor.rst`** — driver API](https://docs.kernel.org/driver-api/media/camera-sensor.html) —
  il documento di riferimento per i driver sensore. Clock, runtime PM, cosa e'
  vietato implementare
- [`camera-sensor.rst` — userspace API](https://docs.kernel.org/userspace-api/media/drivers/camera-sensor.html) —
  semantica dei controlli, formula del frame interval, regole HFLIP/VFLIP
- [`v4l2-subdev.rst`](https://docs.kernel.org/driver-api/media/v4l2-subdev.html) —
  sezione *Centrally managed subdev active state*
- [`tx-rx.rst`](https://docs.kernel.org/driver-api/media/tx-rx.html) —
  `pixel_rate_bus = link_freq * 2 * nr_lanes * 16 / k / bpp` (k=16 per D-PHY)
- [`maintainer-entry-profile.rst`](https://docs.kernel.org/driver-api/media/maintainer-entry-profile.html) —
  `v4l2-compliance` obbligatorio, `checkpatch --strict --max-line-length=80`,
  build `C=1 W=1` con sparse e smatch

## Template mainline (il punto di partenza per il codice)

> Il modello **x86/ACPI** piu' aggiornato e' `drivers/media/i2c/t4ka3.c`
> (merged 7.1): ACPI-only, CCI, state centralizzato, `enable_streams`,
> selection completo, runtime PM moderno. I template GalaxyCore qui sotto
> restano i riferimenti per struttura e registri, ma usano `.s_stream`, oggi
> deprecato.

- [`gc08a3.c` — merge in media_stage](https://www.mail-archive.com/linuxtv-commits@linuxtv.org/msg46482.html)
- [`gc05a2.c` — merge in media_stage](https://www.mail-archive.com/linuxtv-commits@linuxtv.org/msg46481.html)
- [Serie v9 GC08A3](https://lkml.rescloud.iu.edu/2406.1/03920.html) — utile per
  vedere l'evoluzione da v1 a v9 e cosa chiedono i revisori
- [`galaxycore,gc05a2.yaml`](https://mjmwired.net/kernel/Documentation/devicetree/bindings/media/i2c/galaxycore,gc05a2.yaml) — modello di binding
- [`drivers/media/i2c/Kconfig`](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/Kconfig)

## Sorgenti registri

- [intel/ipu6-drivers](https://github.com/intel/ipu6-drivers)
- [patch GC5035 per ADL-M](https://github.com/intel/ipu6-drivers/blob/master/patch/gc5035-on-adlm/0001-Add-the-camera-sensor-gc5035-to-support-ADL-M.patch)
- Driver BSP Rockchip `gc8034.c` — nei kernel vendor Rockchip (4.19 / 5.10),
  device-tree, GPL-2.0

## ipu-bridge

- [`ipu-bridge.c`](https://github.com/torvalds/linux/blob/master/drivers/media/pci/intel/ipu-bridge.c)
- [Patch de Goede: aggiunta HID dal driver out-of-tree](https://patchwork.devel.linuxdvb.org/project/linux-media/patch/20240610173418.16119-2-hdegoede@redhat.com/) — modello per la Serie 3
- [Sort di `ipu_supported_sensors[]` per HID](https://www.mail-archive.com/linuxtv-commits@linuxtv.org/msg46432.html)
- [ipu6-sensor-guide (hao-yao)](https://github.com/hao-yao/ipu6-sensor-guide) —
  guida Intel all'abilitazione di nuovi sensori su IPU6

## Documentazione kernel

- [IPU6 ISYS — admin guide](https://docs.kernel.org/admin-guide/media/ipu6-isys.html)
- [IPU6 driver — driver API](https://docs.kernel.org/driver-api/media/drivers/ipu6.html)
- [ACPI device enumeration](https://docs.kernel.org/firmware-guide/acpi/enumeration.html)

## Pinctrl (contesto Blocco 1, non materiale upstream)

- [`CONFIG_PINCTRL_ALDERLAKE` — LKDDb](https://cateee.net/lkddb/web-lkddb/PINCTRL_ALDERLAKE.html)
- [`pinctrl-alderlake.c`](https://github.com/torvalds/linux/blob/master/drivers/pinctrl/intel/pinctrl-alderlake.c)

## Contesto e precedenti sul dispositivo

- [Issue #341 intel/ipu6-drivers — GC8034](https://github.com/intel/ipu6-drivers/issues/341) —
  stessa coppia di sensori, aperta e senza risposta
- [Forum CHUWI — Hi10 X1 cameras in Linux](https://forum.chuwi.com/t/hi10-x1-n150-tablet-cameras-in-linux-ubuntu/51341)
- [Forum CHUWI — Hi10 X1 Debian](https://forum.chuwi.com/t/hi10-x1-linux-debian-bookworm-user-support-experience/48339)

## Canali upstream

| | |
|---|---|
| Mailing list | `linux-media@vger.kernel.org` |
| Patchwork | https://patchwork.linuxtv.org/project/linux-media/list/ |
| Tree intermedio | `media_stage` — https://git.linuxtv.org/media_stage.git |
| **Tree finale** | `torvalds/linux` — https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git |
| Tool serie | `b4` — https://b4.docs.kernel.org/ |
| Archivio lista | https://lore.kernel.org/linux-media/ |

## Processo di contribuzione (obbligatorio conoscerlo)

Il codice giusto non basta: le serie muoiono piu' spesso per il processo che per
la tecnica. Vedi `03-piano-upstream.md`.

- [Submitting patches — la guida canonica](https://docs.kernel.org/process/submitting-patches.html)
- [Developer's Certificate of Origin](https://docs.kernel.org/process/submitting-patches.html#sign-your-work-the-developer-s-certificate-of-origin) —
  perche' serve il nome reale nel `Signed-off-by`
- [Maintainer handbooks](https://docs.kernel.org/process/maintainer-handbooks.html) —
  regole specifiche per sottosistema (verificare se linux-media ne ha una
  aggiornata prima del primo invio)
- [LinuxTV wiki — submitting patches](https://linuxtv.org/wiki/index.php/Development:_How_to_submit_patches) —
  link da confermare: il wiki LinuxTV riorganizza le pagine
- [Email clients info](https://docs.kernel.org/process/email-clients.html) —
  come non farsi corrompere la patch dal mailer
- [Submitting drivers](https://docs.kernel.org/process/submitting-drivers.html)
- [How the development process works](https://docs.kernel.org/process/2.Process.html) —
  merge window, `-rc`, tempi reali
- [Kernel test robot](https://github.com/intel/lkp-tests/wiki) — chi segnala per
  primo se la patch rompe qualcosa una volta applicata

## Maintainer di riferimento

Da confermare sempre con `scripts/get_maintainer.pl` sulle patch effettive.

- **Sakari Ailus** — V4L2 / sensori, revisore principale
- **Bingbu Cao** — IPU6
- **Hans de Goede** — abilitazione camere x86, `ipu-bridge`, `int3472`
- **Zhi Mao** (MediaTek) — autore di `gc08a3.c` e `gc05a2.c`

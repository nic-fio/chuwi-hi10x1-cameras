# reference/ — materiale di terze parti

Codice **non nostro**, scaricato per studio e riuso. Ogni file ha una
provenienza e vincoli di attribuzione che vanno rispettati nelle patch inviate
upstream: il `Signed-off-by` e' una dichiarazione legale (DCO), e riusare
codice GPL senza catena di attribuzione e' un problema serio in review.

**Niente in questa directory va copiato in una patch senza compilare prima la
riga "attribuzione richiesta" qui sotto.**

## Template mainline — GPL-2.0, autore Zhi Mao (MediaTek)

| File | Origine |
|---|---|
| `gc05a2.c` | `torvalds/linux master`, `drivers/media/i2c/gc05a2.c` |
| `gc08a3.c` | `torvalds/linux master`, `drivers/media/i2c/gc08a3.c` |
| `galaxycore,gc05a2.yaml` | binding DT dello stesso |

**Attribuzione richiesta**: se si riusa struttura e boilerplate in modo
sostanziale, citarlo nel messaggio di commit. Copiare l'impianto di un driver
mainline e' pratica normale e accettata; spacciarlo per codice originale no.

## GC5035 — patch Intel per Alder Lake-M

| | |
|---|---|
| File | `gc5035-intel-adlm.patch`, `gc5035-intel.c` |
| Origine | `intel/ipu6-drivers`, `patch/gc5035-on-adlm/0001-Add-the-camera-sensor-gc5035-to-support-ADL-M.patch` |
| Commit repo | `9c03aac53983b03a6e08613157fa2abfa45bed68` — "Engineer release on 2023-08-07", Hao Yao \<hao.yao@intel.com\> |
| Header patch | From: liang.wang \<liang1.wang@intel.com\>, 18 aprile 2023 |
| `Signed-off-by` | liang.wang \<liang1.wang@intel.com\> |
| Licenza | GPL-2.0 |

Copyright dichiarati nel file: Bitland Inc. (2020), Google LLC (2020),
Intel Corporation (2022). `MODULE_AUTHOR`: Zhi Mao, Hao He
\<hao.he@bitland.com.cn\>, Xingyu Wu \<wuxy@bitland.com.cn\>, Tomasz Figa
\<tfiga@chromium.org\>.

> **Origine reale, da non sbagliare.** Il messaggio di commit dichiara che la
> patch deriva dalla serie ChromeOS/MediaTek di Tomasz Figa:
> `patchwork.kernel.org/project/linux-media/patch/20200902224813.14283-4-tfiga@chromium.org`
> L'attribuzione corretta va quindi a **quella serie + Bitland/Google**, non a
> Intel. Attribuire a Intel sarebbe un errore fattuale che un revisore puo'
> notare.

**Attribuzione richiesta**: `Co-developed-by:` / `Signed-off-by:` degli autori
originali, con le loro email vere. Da concordare con loro prima dell'invio —
non si aggiunge il `Signed-off-by` di qualcun altro senza il suo consenso.

## GC8034 — driver BSP Rockchip

| | |
|---|---|
| File | `gc8034-rockchip-bsp.c` (branch `develop-5.10`, 3387 righe), `gc8034-rockchip-bsp-4.19.c` (2775 righe) |
| Origine | `github.com/rockchip-linux/kernel`, `drivers/media/i2c/gc8034.c` |
| Commit del file | `34690d3be73e98c6b037e24c76b3200fb22b9e79` (2024-09-04) |
| Licenza | `// SPDX-License-Identifier: GPL-2.0` |
| Copyright | `Copyright (C) 2017 Fuzhou Rockchip Electronics Co., Ltd.` |
| `MODULE_AUTHOR` | **assente** |

Autori dai commit git, candidati per l'attribuzione:

- Zefa Chen \<zefa.chen@rock-chips.com\> — manutentore principale del file
- Wang Panzhenzhuan \<randy.wang@rock-chips.com\> — ottimizzazioni CTS (2020)
- Hu Kejun \<william.hu@rock-chips.com\> — parti OTP/eeprom
- Tao Huang \<huangtao@rock-chips.com\> — committer

**Attribuzione richiesta**: mantenere la riga di copyright Rockchip 2017 nel
file nuovo, aggiungere la propria, e `Co-developed-by:` degli autori sopra.
GPL-2.0 rende il riuso lecito; la catena di attribuzione lo rende accettabile
in review.

## ipu-bridge

| File | Origine |
|---|---|
| `ipu-bridge.c`, `ipu-bridge.h` | `torvalds/linux master`, `drivers/media/pci/intel/` |

Copie di lavoro per scrivere la Serie 3. Non si riusa codice: si aggiungono due
voci a una tabella.

---

## Cosa NON portare in mainline

Verificato leggendo i file, non per principio:

**Dal BSP Rockchip** (~34% del file e' materiale da buttare):
`gc8034_ioctl`/`compat_ioctl32` con la UAPI vendor `RKMODULE_*`; l'intero
blocco OTP (~990 righe) con `otp_eeprom.h` e `rk-camera-module.h`, header che
in mainline non esistono; `.s_power` in `core_ops`, rimosso da mainline;
configurazione a `#ifdef` compile-time per lane e mirror; pinctrl Rockchip.

**Dalla patch Intel**: `#include <linux/version.h>` e i `#if
LINUX_VERSION_CODE`; `.init_cfg` (rimosso in mainline 6.9+, ora `.init_state`);
mutex propria invece dello state lock del subdev; l'hack `use_independent_gpio`
in `int3472/discrete.c`, che matcha sul nome del modulo sensore (`CJAK519`) e
non sull'HID.

> **Correzione, 2026-08-11.** Qui c'era scritto che `CJAK519` era «quasi
> certamente diverso sul CHUWI». **E' falso**: la ACPI NVS di questa macchina
> riporta `L1M*` = `CJAK519`, identico, per il sensore frontale. L'hack riguarda
> quindi esattamente questo hardware e va capito prima di scartarlo. Il modulo
> posteriore si chiama invece `GC8034`. Vedi `docs/07-clock-e-registri.md`,
> punto 7.

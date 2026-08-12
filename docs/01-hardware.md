# 01 — Hardware

Rilevato il 2026-08-11 sulla macchina di sviluppo. Rigenerabile con
`./scripts/collect-diag.sh` (vedi `data/latest/00-system.txt` e `01-acpi.txt`).

## Macchina

| | |
|---|---|
| Modello | CHUWI **Hi10 X1** (tablet, DMI chassis type 30) |
| CPU | Intel **N100** — Alder Lake-N, 4 core |
| RAM | 7,5 GiB, nessuna swap |
| Storage | SATA SSD `RS256GSSD310` 238,5 GB (`sda1` 2G ESP, `sda2` root ext4) |
| GPU | Intel UHD ADL-N (`i915`) |
| Wi-Fi | Intel CNVi (`iwlwifi`) |
| Audio | HDA Intel PCH |
| BIOS | `SA10C.N1195.24071902.014` — 20/09/2024 |
| OS | Debian 13 trixie |
| Kernel in esecuzione | **`6.12.86+deb13-amd64`**, Debian — dal 2026-08-11 sera |
| Kernel di sviluppo (storico) | 7.0 compilato in locale (`/lib/modules/7.0/build -> /root/linux-7.0`) |

> Il kernel locale 7.0 **non** e' un vanilla pulito: gli manca almeno
> `CONFIG_PINCTRL_ALDERLAKE`. Vedi `02-diagnosi.md`. Non e' piu' quello che
> avvia: e' rimasto solo l'albero moduli in `/lib/modules/7.0`. Per il lavoro
> upstream si usano i sorgenti vanilla in `/home/nicfio/linux`.

## Stato dell'ambiente di sviluppo

> **Superato il 2026-08-11 sera, e la tabella qui sotto e' storia.** Da quando
> avvia il kernel Debian la macchina compila, carica e prova i propri moduli.
> Stato di oggi, riverificato dopo il riavvio del **2026-08-12**:
>
> | Cosa | Stato |
> |---|---|
> | Kernel che avvia | `6.12.86+deb13-amd64`, con `pinctrl-alderlake` |
> | Headers per la build | `/usr/src/linux-headers-6.12.86+deb13-amd64` |
> | `/lib/modules/6.12.86+deb13-amd64/build` | symlink **valido** |
> | `v4l-utils` | **1.30.1-1** — `v4l2-ctl`, `media-ctl`, `v4l2-compliance` |
> | Moduli del progetto | `build-6.12/`, fuori albero, da ricaricare a ogni boot |
> | Sorgenti mainline | `/home/nicfio/linux`, shallow su 7.2-rc7 |
>
> Un dettaglio che vale la pena sapere: **il kernel che avvia non risulta a
> `dpkg`**. I moduli e gli headers ci sono, ma `dpkg -l 'linux-image*'` e'
> vuoto e `dpkg -S` non trova un proprietario per
> `/lib/modules/6.12.86+deb13-amd64/`. Come ci sia finito non e' scritto da
> nessuna parte in questo repository, quindi non lo dico. La conseguenza si',
> ed e' pratica: **gli aggiornamenti di quel kernel non arriveranno da soli**,
> e un `apt install linux-image-amd64` fatto un giorno per distrazione
> installerebbe un kernel diverso da quello che sta funzionando.

Verificato il 2026-08-11. **Questa macchina non era in grado di compilare un
modulo per il proprio kernel.** I documenti precedenti lo davano per scontato.

| Cosa | Stato |
|---|---|
| `/root/linux-7.0` | **non esiste** |
| `/lib/modules/7.0/build` | symlink **rotto**, punta al path qui sopra |
| `/proc/config.gz` | assente |
| Alberi moduli presenti | `7.0` e `7.0.0-rc7` — **nessuno dei due** ha `pinctrl-alderlake` |
| Kernel Debian installato | **nessuno** (`dpkg -l 'linux-image*'` vuoto) |
| `/boot` | vuoto, contiene solo un file `log` |
| ESP (`sda1`, 2 GB vfat) | **non montata**, `/etc/fstab` vuoto |
| Bootloader come pacchetto | nessuno (ne' grub, ne' systemd-boot) |
| Meccanismo di boot | EFI stub: `vmlinuz initrd=initrd.img root=UUID=… hostname=CHUWI` |
| `initramfs-tools` | presente |
| `acpica-tools` (`iasl`) | presente |
| `v4l-utils` | **assente** — niente `v4l2-ctl`, `media-ctl`, `v4l2-compliance` |
| Assenti per la build | `libncurses-dev`, `rsync`, `dwarves`/`pahole` |

Conseguenza: **senza i sorgenti e la `.config` originali del 7.0, nessun modulo
compilato in locale sarebbe caricabile.** L'unica strada e' costruire un kernel
vanilla completo — che e' comunque la Fase 1 della ROADMAP.

Sorgenti vanilla clonate in `/home/nicfio/linux` (shallow, mainline 7.2).
Build riproducibile: `./scripts/build-kernel.sh`.

> Falso allarme da annotare: `modprobe`, `depmod`, `modinfo` e `insmod`
> sembrano assenti perche' `/usr/sbin` non e' nel `PATH` dell'utente non-root.
> Ci sono, sono symlink a `kmod`.

## Premesse verificate su mainline 7.2

Non sui documenti, ma sul sorgente clonato:

| Premessa | Esito |
|---|---|
| `gc5035`/`gc8034` assenti da mainline | **confermato** — in `drivers/media/i2c/` ci sono solo `gc0308`, `gc0310`, `gc05a2`, `gc2145`, `gc08a3` |
| Template presenti | **confermato** — `gc05a2.c` (34 KB), `gc08a3.c` (33 KB) |
| `pinctrl-alderlake` copre `INTC1057` | **confermato** — `pinctrl-alderlake.c:722` mappa `INTC1057` su `adln_soc_data` |
| `ipu-bridge` non conosce i `GCTI*` | **confermato** — 26 voci sensore, nessuna GalaxyCore |

## Catena camera

Non sono webcam USB/UVC. Sono due sensori **MIPI CSI-2** dietro l'**Intel IPU6**.

```
GC8034 (post.) ──┐
                 ├── MIPI CSI-2 ──> IPU6 ISYS ──> /dev/video*
GC5035 (front.) ─┘                  (00:05.0)
       ▲
       └── I2C (controllo) + INT3472 DSC0/DSC1 (clock, reset, powerdown, regolatori)
                                        ▲
                                        └── GPIO su INTC1057 (pinctrl ADL-N)
```

| Componente | ID | PCI/ACPI | Stato firmware |
|---|---|---|---|
| IPU6 | `8086:462e` | `00:05.0` — IPU6-v3, hw version 5 | attivo, driver `intel-ipu6` agganciato |
| Sensore posteriore | `GCTI8034` = **GalaxyCore GC8034** (8 MP) | `\_SB.PC00.LNK0` | **status=15** (presente, abilitato) |
| Sensore frontale | `GCTI5035` = **GalaxyCore GC5035** (5 MP) | `\_SB.PC00.LNK1` | **status=15** (presente, abilitato) |
| Power/clock post. | `INT3472` | `\_SB.PC00.DSC0` | status=15 |
| Power/clock front. | `INT3472` | `\_SB.PC00.DSC1` | status=15 |
| GPIO controller | `INTC1057` | `\_SB.GPI0` | status=15 |

### Sensori descritti nella DSDT ma NON montati

Tutti con `status=0`. Sono varianti previste dal BIOS per altri modelli della
stessa famiglia. **Non inseguirli**: su questa macchina non esistono fisicamente.

| ID | Sensore | Path |
|---|---|---|
| `INT3471` | OV2680 | `\_SB.PC00.I2C2.CAM0` |
| `INT3474` | OV5693 | `\_SB.PC00.I2C4.CAM1` |
| `INT33BE` | OV5693 | `\_SB.PC00.LNK3/4/5` |
| `OVTI01AS` | OV01A1S | `\_SB.PC00.LNK2` |
| `TXNW3643` | TI LM3643 (flash LED) | `\_SB.PC00.FLM0/1/2` |

## Firmware IPU6 — a posto

`/lib/firmware/intel/ipu/` contiene `ipu6ep_fw.bin`, `ipu6epadln_fw.bin` e gli
altri, dal pacchetto Debian `firmware-intel-graphics 20250410-2`. Al boot:

```
intel-ipu6 0000:00:05.0: Sending BOOT_LOAD to CSE
intel-ipu6 0000:00:05.0: Sending AUTHENTICATE_RUN to CSE
intel-ipu6 0000:00:05.0: CSE authenticate_run done
intel-ipu6 0000:00:05.0: IPU6-v3[462e] hardware version 5
```

**Non e' un problema di firmware, ne' di BIOS.** La DSDT descrive i due sensori
in modo completo e coerente. Il buco e' interamente lato driver kernel.

## Periferiche non correlate

- **Touchscreen**: `NYM TCA9537-B32`, **USB HID** via `hid-multitouch`. Funziona.
  Al momento della raccolta risultava scollegato (tablet staccato dalla base).
  Non e' un problema di driver e non c'entra con le camere.
- **Accelerometro**: `NSA2513` su i2c-6, driver `da280` disponibile.
- **WARNING i915 ricorrenti**: 1458 occorrenze in
  `drivers/gpu/drm/i915/display/intel_tc.c` (`adlp_tc_phy_connect`,
  `get_pin_assignment`) — PHY Type-C / DisplayPort su USB-C. Rumore nel log,
  **problema separato**, nessun legame con le camere. Compaiono nelle ricerche
  `grep ipu6` solo perche' la lista moduli nel footer dell'oops contiene `ipu6`.

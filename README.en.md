# INTEL-CAMERA

Mainline Linux support for the two cameras of the **CHUWI Hi10 X1** tablet
(Intel N100 / Alder Lake-N, Intel IPU6).

> **Language note.** This file and `FINDINGS.en.md` are in English. The rest of
> the documentation — about 4,800 lines of it — is in Italian, because that is
> the language the work was done in. The two English files carry everything a
> kernel developer needs; the Italian ones carry the reasoning behind it. Patch
> commit messages and source comments are in English, as they have to be.

## What this is

Two sensor drivers that do not exist in any kernel version, plus two entries in
`ipu-bridge`:

| | |
|---|---|
| Tablet | CHUWI Hi10 X1 — Intel N100 (Alder Lake-N) |
| ISP | Intel IPU6 `8086:462e` — already supported by mainline |
| Rear | GalaxyCore **GC8034** 8 MP — ACPI `GCTI8034`, i2c `0x37`, 4 lanes |
| Front | GalaxyCore **GC5035** 5 MP — ACPI `GCTI5035`, i2c `0x3f`, 2 lanes |

Everything else in the chain — IPU6, ISYS, firmware, `pinctrl-alderlake`,
libcamera — is already in mainline and already packaged.

## Status: both cameras work

On 2026-08-11, on a stock Debian 6.12.86 kernel, both drivers probed, both
sensors answered with their chip ID (`0x5035`, `0x8044`) and produced
recognisable frames — 5 MP front, 8 MP rear — with no kernel errors.
`v4l2-compliance`: 45 of 46 on both, and the 46th fails on every recent
mainline sensor driver too.

Re-verified on 2026-08-12 after a reboot: frame rate predicted by the driver
matches the measured one to within 0.04%, analogue gain follows the requested
value to within 1.0% and 3.7%, compliance unchanged.

**This is not the goal.** The goal is the code being in Linus' tree, so that
support reaches everyone through their distribution. The drivers currently run
as out-of-tree modules. Nothing has been submitted yet: see
`docs/09-revisione-preinvio.md` finding B1 — the submitter's real identity for
the `Signed-off-by` is not settled, and that is a decision, not a task.

## Two mainline bugs found on the way, with patches

Neither is in this project's code. Both are pre-existing NULL pointer
dereferences that these drivers make reachable on this hardware, and both crash
the kernel when a sensor goes away while something is still using it.

| | Where | Trigger | Patch |
|---|---|---|---|
| **A1** | `ipu6-isys-csi2.c` | unbind a sensor **during** a capture | `patches/wip/ipu6-fix/` |
| **A2** | `v4l2-subdev.c` | unbind a sensor while something **opens** `/dev/v4l-subdevN` | `patches/wip/subdev-fix/` |

A2 was not provoked: it was hit by `v4l_id`, run by udev on the node that was
appearing and disappearing during a bind/unbind loop. It reproduces on demand
at cycle 7 with `scripts/riproduci-oops-subdev.sh`. Full analysis, including
the disassembly that identifies the pointer, is in **`FINDINGS.en.md`**.

Both patches compile against 7.2-rc7, apply cleanly, carry a `Fixes:` tag, and
`checkpatch --strict` is clean on them apart from the deliberately missing
`Signed-off-by`. Neither has been submitted, for the reason above.

## Reproducing this

```bash
cd build-6.12 && make && sudo ./carica.sh   # build + load the out-of-tree modules
sudo ./scripts/prova-completa.sh            # every check, with a verdict
./scripts/cattura.sh gc5035 5               # or gc8034 — capture frames
./scripts/raw-to-png.py gc5035.raw 2592 1944 grbg
```

Nothing survives a reboot: the modules are out-of-tree and Debian's
`ipu-bridge` goes back in place. That is deliberate — the target is mainline,
not a working local install.

`scripts/prova-completa.sh` compares measured numbers against what the drivers
predict, rather than reporting "seems to work". Its output is dated and kept in
`data/`.

## Licence

**MIT** for this project's own material — documentation, scripts, collected
data.

**GPL-2.0** for the kernel drivers (`build-6.12/*.c`, `patches/`,
`reference/`), and not by preference: their register tables are reproduced from
existing GPL-2.0 work by Intel and Rockchip, and GPL-2.0 requires derivative
works to keep the same terms. The original copyright lines are preserved in the
file headers and the full provenance chain is documented in
`reference/README.md`. See `LICENSE`.

## Where things are

```
docs/01-hardware.md            inventory, camera chain, environment
docs/02-diagnosi.md            the three blockers, and how each one ended
docs/03-piano-upstream.md      what to submit, and what each patch must contain
docs/04-riferimenti.md         templates, register sources, maintainers
docs/05-parametri-sensori.md   every parameter, with where each value came from
docs/06-azioni-root.md         the steps that need root, and what they cost
docs/07-clock-e-registri.md    platform clock and register tables
docs/08-prova-hardware.md      the first run on real hardware, with measurements
docs/09-revisione-preinvio.md  adversarial pre-submission review, findings, verdict
docs/10-kernel-di-debug.md     KASAN and lockdep: how to boot it, what to look for
patches/wip/                   the patches, in draft form
data/                          dated snapshots and evidence
reference/                     third-party code and its attribution constraints
```

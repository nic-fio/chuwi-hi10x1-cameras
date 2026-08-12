# Findings — technical summary in English

Everything a kernel developer needs from this project, without reading the
Italian documentation. Each claim here is backed by a file under `data/`.

Hardware: CHUWI Hi10 X1, Intel N100 (Alder Lake-N), Intel IPU6 `8086:462e`,
BIOS `SA10C.N1195.24071902.014`. Kernel: Debian `6.12.86+deb13-amd64`. Mainline
tree used for patches: 7.2-rc7.

---

## 1. Sensor parameters, from the ACPI NVS and confirmed on hardware

The DSDT of this machine declares nothing directly: `_CRS`, `SSDB`, `CLDB` and
the `_DSM` methods are all parameterised by variables (`L1NL`, `L1CK`, `L1A0`,
`L1DI`, `C1F*`…) that the BIOS writes into **ACPI NVS** at boot. Reading the
DSDT alone gets you nothing; the values were read from NVS at `0x75886000`
after booting with `iomem=relaxed`, then confirmed by the sensors actually
streaming.

| | GC8034 (rear) | GC5035 (front) |
|---|---|---|
| ACPI HID / path | `GCTI8034` @ `\_SB.PC00.LNK0` | `GCTI5035` @ `\_SB.PC00.LNK1` |
| i2c address | `0x37` (+ `dw9714` VCM @ `0x0c`) | `0x3f` |
| i2c bus (NVS / Linux adapter) | 1 / `i2c-2` | 2 / `i2c-3` |
| CSI-2 lanes | 4 | 2 |
| MCLK | 19.2 MHz | 19.2 MHz |
| Control logic | `DSC0` | `DSC1` |
| GPIOs | `POWER_ENABLE` pin 85 | `RESET` pin 239, `POWER_ENABLE` pin 463 |
| Chip ID read back | `0x8044` | `0x5035` |

Note `0x8044`, not `0x8034`, for the GC8034 — the part number and the chip ID
do not match, which is normal for this vendor but easy to get wrong.

## 2. The declared link frequencies were wrong, and the fix is not a constant

Measuring the frame rate showed both published values to be wrong:

| | Declared | Measured | Relationship |
|---|---|---|---|
| GC5035 | 438 MHz (Intel out-of-tree patch) | **422.4 MHz** | 19.2 MHz × 22 |
| GC8034 | 336 MHz (Rockchip BSP) | **268.8 MHz** | 19.2 MHz × 14 |

Both measured values are integer multiples of the external clock, because the
register tables program the PLL once and the multiplier lives in the table. So
the drivers **derive the link frequency from the clock** instead of hardcoding
it: the same code is then correct on IPU6's 19.2 MHz and on a device tree's
24 MHz, with no per-machine quirk. With that change the frame rate a driver
predicts matches the measured one:

| | Predicted | Measured | Error |
|---|---|---|---|
| GC5035 | 28.8162 fps | 28.82 | 0.01% |
| GC8034 | 24.0000 fps | 24.01 | 0.04% |

## 3. The Rockchip 24 MHz tables work unchanged at 19.2 MHz

This was the project's main technical risk: the only register tables available
for the GC8034 come from a BSP running XVCLK at 24 MHz, while this platform
runs 19.2 MHz. The expectation was that four PLL registers (`0xf4`, `0xf5`,
`0xf7`, `0xfa`) would need re-tuning.

They do not. Every timing simply scales by 19.2/24 = 0.8, the sensor streams
3264×2448 with no corruption and no CSI-2 timeouts, and the measured frame rate
agrees with the scaled model to four digits.

Related, and still true: Alder Lake's IMGCLKOUT can produce **both** 24 MHz and
19.2 MHz — coreboot documents bit 0 of the `ICLK` register as *"0: 24MHz,
1: 19.2MHz"* — but the kernel always writes `1` and `int3472`'s clock exposes
no `.set_rate`. A patch to fix that is in `patches/wip/int3472/`. It is no
longer needed for this hardware; it still closes a real gap.

## 4. Two NULL pointer dereferences in mainline

Neither belongs to this project's drivers. Both are reached when a sensor
disappears while something is still using it — which these drivers make
possible on this hardware for the first time.

### A1 — `ipu6_isys_csi2_disable_streams()`

Trigger: unbind the sensor driver **while a capture is running**.

```
BUG: kernel NULL pointer dereference, address: 0000000000000020
RIP: 0010:ipu6_isys_csi2_disable_streams+0x3c/0x70 [intel_ipu6_isys]
 v4l2_subdev_disable_streams+0x1b7/0x370 [videodev]
 ipu6_isys_video_set_streaming+0x20f/0x930 [intel_ipu6_isys]
 stop_streaming+0x102/0x110 [intel_ipu6_isys]
 __vb2_queue_cancel+0x2a/0x2d0 [videobuf2_common]
 v4l2_release+0xbd/0xd0 [videodev]
```

`media_pad_remote_pad_first()` returns NULL once the link is gone, and both the
enable and the disable path in `ipu6-isys-csi2.c` dereference it unconditionally.
`CR2 = 0x20` is the offset of `entity` in `struct media_pad`. After the oops the
pipeline is stuck: a `media-ctl` sits in `D` state inside
`subdev_do_ioctl_lock`, holding a mutex owned by a dead task. Only a reboot
recovers it.

Patch: `patches/wip/ipu6-fix/`.
`Fixes: 3a5c59ad926b ("media: ipu6: Rework CSI-2 sub-device streaming control")`

### A2 — `subdev_open()`

Trigger: unbind the sensor driver while something **opens** its
`/dev/v4l-subdevN`. No streaming required.

```
BUG: kernel NULL pointer dereference, address: 0000000000000008
RIP: 0010:subdev_open+0x8a/0x190 [videodev]     Comm: v4l_id
 v4l2_open+0xa9/0x100 [videodev]
 chrdev_open+0xb2/0x230
 do_sys_openat2+0xae/0xe0
```

`v4l2_device_unregister_subdev()` clears `sd->v4l2_dev` (v4l2-device.c:279),
then unregisters the media entity — which sleeps — and only then unregisters
the device node (v4l2-device.c:291). In between, `/dev/v4l-subdevN` is still
openable and `subdev_open()` (v4l2-subdev.c:115) dereferences `sd->v4l2_dev`
unconditionally. The Debian kernel has no symbols, so the field was identified
from the disassembly of `videodev.ko`:

```
be83:  49 8b 85 98 00 00 00    mov  0x98(%r13),%rax      <- sd->v4l2_dev
be8a:  48 83 78 08 00          cmpq $0x0,0x8(%rax)       <- ->mdev, RAX = 0
```

`0x8` is the offset of `mdev` in `struct v4l2_device`, which is exactly the
`CR2` of the oops.

The same window leaves `sd->entity.graph_obj.mdev` NULL while
`sd->v4l2_dev->mdev` is not, and the second dereference on that same line goes
through it. That one was found by reading the teardown path, not by crashing on
it.

Reordering the teardown would narrow the window but not close it, because
`v4l2_open()` drops `videodev_lock` before calling `fops->open()`
(v4l2-dev.c:426-433), so the whole of `v4l2_device_unregister_subdev()` can
still run in between. The check belongs in `subdev_open()`.

**This was not provoked.** It was hit by `v4l_id`, run by udev on the node that
was appearing and disappearing during a bind/unbind loop. It then reproduced on
demand at cycle 7 with `scripts/riproduci-oops-subdev.sh` (four processes
opening every `/dev/v4l-subdev*` while the sensor is rebound in a loop).

Impact: the machine survives — the oops kills the opener, not the kernel — but
every hit leaks a `video_device` and its minor forever, visible as gaps in
`/dev/v4l-subdev*`. Unbinding needs root; **opening does not**, only membership
in the `video` group. And a plain `rmmod` of a sensor driver does the same
thing, with udev opening the node on its own.

`lore.kernel.org/linux-media` was searched three ways on 2026-08-12
(`subdev_open v4l2_dev`, `"v4l2_device_unregister_subdev" AND "NULL pointer"`,
`"subdev_open" AND "ENODEV"`): nobody has reported this. The closest hit is
from 2014 and addresses the dereference *inside* the unregister path, not a
racing open — and it was never applied.

Patch: `patches/wip/subdev-fix/`.
`Fixes: 61f5db549dde ("[media] v4l: Make v4l2_subdev inherit from media_entity")`

## 5. What has not been checked

Stated plainly, because an unmentioned gap reads as a covered one:

* **KASAN, UBSAN, KCSAN, lockdep and KMEMLEAK have never been run.** A debug
  kernel with all of them is built and ready (`docs/10-kernel-di-debug.md`) but
  has not been booted. Everything said about memory and locking in the review is
  inspection, not instrumentation. This is the largest gap.
* **System suspend/resume** has not been tested.
* **The `dw9714` VCM is instantiated but never exercised** — focus has not been
  moved.
* **Only one machine.** Every measurement comes from a single tablet, and
  per-machine quirks are the norm on IPU6.
* **No GalaxyCore datasheet.** The PLL, D-PHY and analogue bias registers are
  undocumented blobs carried over from existing GPL-2.0 code. `GC8034_VTS_OFFSET`
  is inferred.
* **Intermittent CSI-2 errors** on the GC5035 port only, at stream boundaries,
  never during a stream. A long isolated stream shows zero. Images are intact
  and the frame rate is stable. Unexplained.

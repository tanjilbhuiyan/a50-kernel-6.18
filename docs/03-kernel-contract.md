# 03 — Kernel contract: what the new kernel MUST provide

The new kernel is correct when every consumer below gets what it got from
the baseline kernel. Three consumers: (1) Ubuntu Touch / Halium userspace,
(2) the **stock vendor partition** (closed Android 11 binaries), (3) S-Boot.

## 1. Halium / Ubuntu Touch requirements

- Authoritative checker: `reference/halium-check-kernel-config.sh`
  (from Halium `halium-boot`, 244 `CONFIG_` options). Run it against every
  candidate `.config`; zero errors is required (M5 DoD).
- Additionally required by this port (from baseline behaviour):
  `CONFIG_SECURITY_APPARMOR` (UT confinement), `CONFIG_BLK_DEV_LOOP` with
  `loop.max_part=7`, ext4, `CONFIG_DEVTMPFS`, namespaces + cgroups for LXC,
  `CONFIG_USB_CONFIGFS*` gadget functions (rndis, adb/ffs, mtp, mass_storage),
  `CONFIG_PSTORE_RAM`.
- cmdline must be built in (`CONFIG_CMDLINE`, S-Boot drops header cmdline);
  must NOT contain `systempart=` (we use the `/data/ubuntu.img` layout).

## 2. Stock vendor ABI (closed binaries, never modified)

Source of truth: `reference/stock-vendor/` (ueventd.rc, init/*.rc, manifest,
HAL lists, firmware list). 157 device-node rules in `dev-nodes-ueventd.txt`.

### 2a. Android core kernel interfaces

| Interface | Used by | In ACK android17-6.18 | Action |
|---|---|---|---|
| binder, hwbinder, vndbinder (binderfs) | all HALs, Halium LXC | ✅ `drivers/android/` | config only |
| ashmem | libcutils (Android 11) | ✅ but **Rust** (`ashmem.rs`, `depends on SHMEM && RUST`) | Rust toolchain in build |
| **ION** (`/dev/ion`, Samsung heaps, `ion_fdt_exynos`) | gralloc.exynos9610, hwcomposer, camera, codec | ❌ removed (only dma-buf `system_heap`, `cma_heap`) | **port legacy ION as staging driver + Exynos heaps** (M6) |
| sync_file / sw_sync | HWC, gralloc fences | ✅ | config |
| wakelocks (`/sys/power/wake_lock`) | Halium, RIL | ✅ `CONFIG_PM_WAKELOCKS` | config |
| uevent / ueventd semantics | container init | ✅ | — |

### 2b. Samsung device ABIs (must match 4.14 ioctls/sysfs exactly)

Capture method for each: on the baseline, record which process opens which
node and which ioctl numbers it issues (M1 task "contract capture").

| Device node(s) | Driver (4.14) | Vendor consumer | Needed for |
|---|---|---|---|
| `/dev/mali0` (`/dev/mali` rule) | Mali kbase **r26p0** | libGLES_mali, vulkan.universal9610 | S2 |
| `/dev/graphics/fb*`, DECON/DPP ioctls | `video/fbdev/exynos/dpu20` | hwcomposer.exynos9610 | S2 |
| `/dev/ion`, `/dev/ionfd2phys` | ION + exynos heaps | gralloc, HWC, codecs | S2 |
| `/dev/g2d`, `/dev/fimg2d` | `gpu/exynos/g2d` | HWC (2D blits, may be optional) | S2 (verify) |
| `/dev/seiren`, ALSA cards, `/dev/ttyGS*` no | ABOX + tfa98xx | audio.primary/sec_primary | S6 |
| `/dev/scsc_*`, `/dev/mx_*`, wlan netdev `swlan0`/`wlan0` | `misc/samsung/scsc*`, `net/wireless/scsc` | wifi HAL, wpa_supplicant, BT HAL (`scsc_h4_`) | S4, S8 |
| `/dev/umts*`, `/dev/ipc`, `/dev/smd`, `/dev/drb`, `/dev/ramdump_memshare` | `misc/modem_v1`, `mcu_ipc`, `shm_ipc` | cbd (CP boot daemon), RIL | S7 |
| `/dev/ssp_*`, iio devices | sensorhub / nanohub | sensors HAL | stretch |
| `/dev/video*`, `/dev/v4l-subdev*`, `/dev/media*` | fimc-is2, MFC, scaler | camera provider, OMX | stretch |
| `/dev/tzdev`, `/dev/mobicore*` | TEE | keymaster, gatekeeper, TLC services | out of scope unless a DoD item needs it |
| `/sys/class/power_supply/*` (battery, usb, ac, otg) | sec_battery, sm5713 | health HAL, usb-moded, upower | S5, S9 |

### 2c. Firmware (loaded by drivers from `/vendor/firmware` or `/vendor/etc/wifi`)

33 files in `reference/stock-vendor/firmware-list.txt`: ABOX (`AP_AUDIO_SLSI.bin`,
`APBargeIn_*`, `APBiBF_*`), TFA9872 (`Tfa9872.cnt`, `tfadsp.bin`), MFC
(`mfc_fw.bin`), camera (`fimc_is_lib.bin`, `fimc_is_rta.bin`, setfiles), VIPX
(`calliope_*`), CHUB (`CC_*`). Wi-Fi firmware path:
`CONFIG_SCSC_CORE_FW_LOCATION="/vendor/etc/wifi"`. The runtime-firmware
baseline (aa17rf2) proves ABOX/TFA load at runtime without built-in blobs.

## 3. S-Boot constraints

- BOOT image: `ANDROID!` header v1, page 2048, kernel_addr `0x10008000`,
  tags `0x10000100`; **total ≤ 57,671,680 bytes**.
- DTB/DTBO come from their partitions (stock today). A new kernel will need
  our own DTB/DTBO (6.18 bindings differ) written to DTB/DTBO partitions;
  the stock ones stay in `reference/stock-images/` for rollback.
- Whether S-Boot accepts a gzip-compressed `Image.gz` is **unverified** (M1).

## 4. Debug contract

- ramoops: reuse the bootloader-preserved region `log_pstore` at
  **0xf9d10000, size 0x200000** (from live DT `reserved-memory/debug_snapshot`).
  Kernel log region `log_kernel` 0xf9010000/0x200000, header 0xf9000000/0x10000.
- simple-framebuffer at `0xca000000`, 1080×2340 (format/stride unverified; M2).

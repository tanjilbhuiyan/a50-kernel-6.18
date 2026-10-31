# 01 — Device facts (verified)

All values measured on this phone between 2026-10-31 and 2026-11-01.

## Identity

| Item | Value | Source |
|---|---|---|
| Model | SM-A505F, codename `a50`, product `a50dd` | `getprop` on stock Android |
| DT model string | `Samsung A50 SWA OPEN rev04 board based on Exynos9610` | `/proc/device-tree/model` |
| Root compatible | `samsung,armv8`, `samsung,exynos9610` | `/proc/device-tree/compatible` |
| Board revision / DTBO index | `androidboot.revision=6`, `androidboot.dtbo_idx=5` | `/proc/cmdline` |
| SoC | Exynos 9610: 4× Cortex-A73 2.31 GHz + 4× Cortex-A53 1.74 GHz | cpufreq sysfs |
| GPU | Mali-G72 MP3; vendor DDK `CONFIG_MALI_BIFROST_R26P0_R` | `halium_a50_defconfig` |
| RAM | 4 GB (`MemTotal` 3,690,784 kB) | `/proc/meminfo` |
| Storage | UFS, 64 GB (`sda` 62,464,000 KiB) | `/proc/partitions` |
| Display | 1080×2340, bootloader framebuffer at `0xca000000` | Mir log; `s3cfb.bootloaderfb=0xca000000` |
| Stock firmware | `A505FDDS9CWA2` (BL/AP), `A505FXXS9CWA2` (CP), CSC `BKD` | `getprop`; zip in `..` |
| Bootloader binary | revision 9; unlocked, `verifiedbootstate=orange` | `getprop` |
| Knox warranty bit | tripped (`ro.boot.warranty_bit=1`) | `getprop` |

## Partitions (UFS `sda`, names from PIT `A50_SWA_OPEN.pit`)

| PIT name | Block dev | Size (bytes) | Notes |
|---|---|---|---|
| BOOT | sda14 | 57,671,680 | **hard limit for kernel + ramdisk** |
| RECOVERY | sda15 | 67,633,152 | TWRP 3.7.1_12-0 now |
| DTB | sda12 | 8,388,608 | stock `dt.img` (Android DT table, magic `d7b7ab1e`) |
| DTBO | sda13 | 8,388,608 | stock `dtbo.img` (board overlays; idx 5 used) |
| VBMETA | sda23 | 65,536 | flags=3 (verification disabled) |
| SYSTEM | sda25 | 5,557,452,800 | stock Android 11 system |
| VENDOR | sda26 | 838,860,800 | **stock, unchanged; the ABI contract** |
| USERDATA | sda32 | ~56.3 GB | ext4; holds `/data/ubuntu.img` |
| EFS / SEC_EFS / CPEFS | sda3 / sda7 / sdd1 | 20 MB / 20 MB / 6 MB | IMEI, keys. **Never write** |

## Boot chain

- S-Boot (Samsung) loads BOOT: `ANDROID!` header **version 1**, page 2048,
  kernel at `0x10008000`, tags `0x10000100`, raw arm64 `Image` (baseline
  kernel_size 42,827,792 + ramdisk 10,792,361 = 53.6 MB of 57.67 MB).
- S-Boot **drops the boot header cmdline**; the author compiles needed args
  into `CONFIG_CMDLINE` (`a50-ubuntu-touch` exp. 065). Header cmdline today:
  `androidboot.selinux=permissive loop.max_part=7`.
- DTB comes from the DTB partition (SoC DT) + DTBO overlay idx 5, merged by
  S-Boot. The kernel does not carry its own DTB today.
- Halium initramfs (in the boot ramdisk) mounts `/data/ubuntu.img` (prefers
  `systempart=` if compiled in; the `rf2sp` kernel does that, ours must not).

## Modes and USB IDs

| Mode | How to enter | USB ID |
|---|---|---|
| Download (Odin) | power off, hold Vol Up + Vol Down, plug USB, Vol Up | `04e8:685d` |
| TWRP recovery | Vol Down+Power (force off) → immediately Vol Up+Power, **USB cable connected** | adb `recovery`, `twrp_a50` |
| Ubuntu Touch (usb-moded "charging only") | normal boot | `04b9:0afe` mass storage |
| Halium initramfs debug | boot fails before rootfs | telnet `192.168.2.15` (RNDIS) |
| UT devel RNDIS | when usb-moded sees a PC | ssh `10.15.19.82` |

## Debug channels (no physical UART is practical on this phone)

- `pstore`/ramoops: verify reserved-memory region in the stock DT before relying on it (M1 task).
- Bootloader framebuffer at `0xca000000` → `simple-framebuffer` for first light.
- Halium initramfs telnet over USB RNDIS (needs a working USB gadget).
- TWRP adb to read `/data`-persisted logs after a failed boot.

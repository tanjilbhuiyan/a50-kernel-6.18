# 02 — Baseline (known-good system on the phone)

Installed 2026-11-01. This is the reference every new kernel is compared
against and the state we restore to after a failed experiment.

## Composition

| Layer | Identity | Location |
|---|---|---|
| BOOT | `boot-aa17rf2.img` sha256 `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5` — Samsung/FreshROMs Mint 4.14.194 + a50-halium patches aa1–aa17, runtime-firmware variant 2, **no** `systempart=` | `baseline/ut-26.04-2026-10-19-aa17rf2/boot.img`; source `src/samsung-a50-4.14-aa17rf2` (branch `halium-a50-aa17rf2`, `4f37ef39`) |
| Rootfs | `ubuntu.img` sha256 `0d33d65db3de022ede1ea9b994ce5326dbced7f1c3727c61d87f178bb1cd6f32`, devel variant, ext4 without `orphan_file` | `baseline/…/ubuntu.img` → phone `/data/ubuntu.img` + `/data/.force-ssh` |
| Ubuntu base | rootfs `809e340e…` (sha256 `a213879c…`), channel `26.04-1.x/arm64/android9plus/daily`, 11 Oct 2026 | `baseline/…/rootfs-source.txt` |
| Android (Halium) GSI | Jenkins halium-11.0 build **1585** (`d08a92e4…`), `android-rootfs.img` `da6c3373…` | `baseline/…/gsi-source.txt` |
| Port overlay | `sadatdaniel/a50-ubuntu-touch` commit `b4556ed` (19 Oct 2026), 20 locked packages | `baseline/…/validated-packages.txt` |
| VENDOR, SYSTEM, DTB | stock `A505FDDS9CWA2` | firmware zip |
| RECOVERY | TWRP 3.7.1_12-0 `8535a9d9…` | `../backup/rescue-images/recovery-twrp.img` |
| VBMETA | stock with flags=3 | `../backup/rescue-images/vbmeta-disabled.img` |

Built in Docker `ubuntu:22.04` (privileged, loop nodes created with `mknod`)
using the port's `build-device-tarball.sh` + `build-rootfs-image.sh --devel`
with pinned `--rootfs-url/--rootfs-sha256`. Do not build rootfs images in a
24.04+ container: its `mke2fs` adds `orphan_file`, unmountable by 4.14.

## Measured behaviour on the baseline (the bar for S10)

| Function | Result (2026-11-01) |
|---|---|
| Boot to Lomiri, setup wizard | ✅ |
| AppArmor | ✅ `Y` |
| Android container | ✅ `sys.boot_completed=1`; `/run/a50-android` overrides generated |
| Audio | ✅ pulseaudio running; sinks `primary-out`, `fast`; source `primary-in` (playback not yet listened to) |
| Modem | ✅ LTE registered (GrameenPhone, SIM slot 2) |
| Wi-Fi | ✅ connected, SSH over Wi-Fi |
| Bluetooth | ✅ service active (pairing not tested) |
| Location service | ✅ active (fix not tested) |
| USB gadget | ⚠️ enumerates at boot (`04b9:0afe`, charging-only); replug re-enumerates; adb/RNDIS blocked by the PD issue below |
| Sensors | ⚠️ no `sensorfw` unit in this image; not tested |
| Failed units | `usb-tethering` only (consequence of the PD issue) |

Gaps to fill before kernel work starts (M0): listen-test audio, BT pairing,
GPS fix, one call/SMS, suspend counters. Record results in `log/`.

## Known issues

1. **Laptop USB-C detected as charger.** `/sys/class/power_supply/usb/online=0`,
   `ac/online=1`, battery driver `Cable(PDIC…)`, `cable_type(19)`; usb-moded
   logs `requested while not connected to pc`, mode stays `undefined`.
   Workaround until reboot (root):
   `echo "USB_MODED_ARGS=-f" > /run/usb-moded/90-force-pc.conf && systemctl restart usb-moded`.
   Update 2026-11-02 (M0.3): not constant. On a USB-C<->USB-C cable the phone
   reported `Cable(USB) rp(1)` (works without help) on one attach and
   `Cable(PDIC) rp(3)` on later ones; the `-f` override then gives a working
   RNDIS link (`docs/06-workflow.md` "USB link to the phone"). USB-A untested.
2. Root over SSH: key installed 2026-11-02 (M0.1, `log/2026-11-02-M0.1-root-ssh.md`).

## Restore the baseline (any state → baseline)

1. Download mode → `heimdall flash --BOOT baseline/…/boot.img --no-reboot`.
2. TWRP (Vol Down+Power → Vol Up+Power, cable in) → Wipe → Format Data → Reboot Recovery.
3. `adb push baseline/…/ubuntu.img /data/ubuntu.img`; verify sha256 on phone;
   `adb shell touch /data/.force-ssh`.
4. Reboot → System. Setup wizard; add SSH key (`docs/06-workflow.md`).

Full stock Android restore: BL+AP+CP+CSC from the firmware zip. VENDOR/SYSTEM
must be written from TWRP with `dd` (Heimdall fails on large images here).

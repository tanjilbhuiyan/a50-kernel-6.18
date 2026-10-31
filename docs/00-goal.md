# 00 — Goal, success criteria, scope

## Problem

The A50 runs Samsung's downstream Linux **4.14.194** (forked from Android 9-era
BSP, last vendor update Android 11, Jan 2023). Upstream 4.14 LTS ended in
January 2024. Every newer userspace adds shims for it (Ubuntu 26.04 `tar`
needs `openat2`; `mke2fs` `orphan_file`; Android 16 BPF fallback). The kernel
is the link in the chain that cannot be updated without porting.

## Goal

Ubuntu Touch 26.04 (Halium 11 GSI, `ubuntu.img` layout) boots and is usable on
the SM-A505F with a kernel based on **Google ACK `android17-6.18`** (Linux 6.18
LTS + Android features), with the A50 drivers forward-ported and the
**stock Android 11 vendor partition unchanged** (`A505FDDS9CWA2`, VNDK 30).

Decision record: `decisions/ADR-0001-base-kernel.md`, `ADR-0002-keep-stock-vendor.md`.

## Success criteria (Definition of Done for the whole project)

All measured on the phone, recorded in `log/`, same rootfs as the baseline:

| # | Criterion | How verified |
|---|---|---|
| S1 | Kernel reports `6.18.y` and boots from cold 10/10 times | `uname -r`, 10 logged boots |
| S2 | Lomiri UI with hardware-accelerated rendering through the stock Mali/HWC stack | UI visible, `glmark2-es2` or equivalent runs |
| S3 | Touch, power/volume keys | manual test checklist |
| S4 | Wi-Fi connects; SSH over Wi-Fi works | `nmcli`, ssh |
| S5 | USB gadget: adb or RNDIS SSH from a PC | `adb devices` / ssh 10.15.19.82 |
| S6 | Speaker + microphone audio | `paplay`, `parecord` round trip |
| S7 | Modem: LTE registration, one call, one SMS | ofono properties, real call |
| S8 | Bluetooth pairs and plays audio | A2DP test |
| S9 | Battery %, charging state, suspend/resume 10 cycles | upower, `/sys/power` counters |
| S10 | No regressions vs. baseline on S3–S9 | checklist diff vs `docs/02-baseline.md` |

Stretch (not required for done): camera, GPS, sensors, Waydroid, fingerprint.

## Scope

In scope:
- Kernel tree based on ACK `android17-6.18`, A50 device tree, A50 defconfig.
- Forward-port of Samsung drivers needed for S1–S9 (see `04-gap-matrix.md`).
- Compatibility shims needed by the stock vendor ABI (ION, Samsung ioctls).
- Reuse of mainline drivers wherever the IP block is supported (category A/B).
- Boot image packaging for S-Boot (`ANDROID!` header v1, ≤ 57,671,680 bytes).

Out of scope (non-goals):
- Changing or replacing vendor blobs (GPU, audio, camera, RIL libraries).
- Upstreaming to mainline (desirable later; not a gate).
- Samsung Knox/TrustZone/debug features (tzdev, mobicore, argos, abc, nad,
  debug-snapshot, sec_debug) unless a DoD item proves it needs them.
- Fingerprint, MST, FM radio, TV tuners, VIPX/NPU, HDCP.
- Pure-mainline (no Android blobs) operation. Panfrost is noted as a future
  path in `ADR-0002`, not a goal here.
- Android ROMs (the Evolution X experiment is finished).

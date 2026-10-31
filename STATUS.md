# STATUS

Updated: 2026-11-01

## Current milestone: **M1.1 + M1.2 (host-only)**, M0 deferred by owner (`docs/05-plan.md` exception)

Start here: M1.1 — reproduce the baseline kernel `Image` byte-identically from
`src/samsung-a50-4.14-aa17rf2` in a container (method: `sadatdaniel/a50-halium`
`build/`). Then M1.2 — clone ACK `android17-6.18`, build `gki_defconfig` arm64
with clang + Rust. Neither needs the phone.

## State of the phone
Baseline installed and booting Ubuntu Touch 26.04 (`docs/02-baseline.md`):
BOOT `aa17rf2` (`7d5855ef…`), `/data/ubuntu.img` (`0d33d65d…`), stock
VENDOR/SYSTEM/DTB/DTBO, TWRP 3.7.1, vbmeta flags=3. SSH as `phablet` over
Wi-Fi (last IP 192.168.0.171).

## Done
- Context created: goal, device facts, baseline, kernel contract, gap matrix,
  plan, workflow, risks, ADR-0001/0002 (`log/2026-11-01-context-setup.md`).

## Deferred (M0, when the owner is ready to use the phone for tests)
1. Owner: install root SSH key on the phone (one sudo command in Terminal).
2. Baseline checklist: speaker/mic, BT pairing, GPS fix, call + SMS, suspend.
3. Decide USB access method for the PD issue (USB-A cable or `-f` override).

## Open questions
- Does S-Boot boot `Image.gz`? (M1.4)
- Exact ioctl sets used by vendor HALs on mali/ion/decon/abox/scsc/modem (M1.3)

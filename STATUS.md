# STATUS

Updated: 2026-11-02

## Current milestone: **M1.1 + M1.2 (host-only)**, M0 deferred by owner (`docs/05-plan.md` exception)

M1.1 and M1.2 done. M2.1 and M2.3 done (fb pixel format accepted as a risk, resolve in M2.4). No host-only tickets remain; everything else needs the phone, starting with M0.1.

Summary: M2.1 DT is committed on branch `a50-dt` in `src/ack-6.18/common` (`4fd044c7c`). Open: fb format (resolve in M2.4), RAM bank count, ramoops (M1.5).

## State of the phone
Baseline installed and booting Ubuntu Touch 26.04 (`docs/02-baseline.md`):
BOOT `aa17rf2` (`7d5855ef…`), `/data/ubuntu.img` (`0d33d65d…`), stock
VENDOR/SYSTEM/DTB/DTBO, TWRP 3.7.1, vbmeta flags=3. SSH as `phablet` over
Wi-Fi (last IP 192.168.0.171).

## Done
- M2.3: `tools/dt_table.py` round-trips stock dt.img/dtbo.img byte-identically; our dt.img/dtbo.img built with stock selection fields (`log/2026-11-02-M2.3-dt-images.md`). Stock images carry a Samsung signature + AVB footer, carried over stale; S-Boot acceptance unverified.
- M2.1: `exynos9610-a50.dtb` builds + dt-validate clean (`log/2026-11-01-M2.1-dt.md`, `reference/dt-6.18/`).
- M1.2: ACK `d9a614fe` GKI built (Kleaf 435 s; plain make 288 s). Image 43,670,016 B = 75.7% of BOOT budget (`log/2026-11-01-M1.2-ack-build.md`, `reference/ack-build/`).
- M1.1: baseline `Image` (`6d000a98…`) and boot.img (`7d5855ef…`) reproduced byte-identically on the host (`log/2026-11-01-M1.1-reproduce-baseline.md`, `reference/baseline-build/`). Needed an `nproc`=4 shim; `-j16` untested.
- Tickets for M0–M2 created in `tasks/` (12 tickets, index `tasks/README.md`).
- Context created: goal, device facts, baseline, kernel contract, gap matrix,
  plan, workflow, risks, ADR-0001/0002 (`log/2026-11-01-context-setup.md`).

## Deferred (M0, when the owner is ready to use the phone for tests)
1. Owner: install root SSH key on the phone (one sudo command in Terminal).
2. Baseline checklist: speaker/mic, BT pairing, GPS fix, call + SMS, suspend.
3. Decide USB access method for the PD issue (USB-A cable or `-f` override).

## Open questions
- Does S-Boot boot `Image.gz`? (M1.4)
- Exact ioctl sets used by vendor HALs on mali/ion/decon/abox/scsc/modem (M1.3)

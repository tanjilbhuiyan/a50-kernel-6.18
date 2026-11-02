# STATUS

Updated: 2026-11-02

## Current milestone: **M0.4 (diagnose baseline audio)**, then M1.3-M1.5; M0.1-M0.3 done

M1.1 and M1.2 done. M2.1 and M2.3 done (fb pixel format accepted as a risk, resolve in M2.4). M0.1-M0.3 complete. Start here: **`tasks/M0.4-diagnose-baseline-audio.md`** (needs the phone, reboot with owner present). No host-only tickets remain.

Summary: M2.1 DT is committed on branch `a50-dt` in `src/ack-6.18/common` (`4fd044c7c`). Open: fb format (resolve in M2.4), RAM bank count, ramoops (M1.5).

## State of the phone
Baseline installed and booting Ubuntu Touch 26.04 (`docs/02-baseline.md`):
BOOT `aa17rf2` (`7d5855ef…`), `/data/ubuntu.img` (`0d33d65d…`), stock
VENDOR/SYSTEM/DTB/DTBO, TWRP 3.7.1, vbmeta flags=3. SSH as `phablet` over
Wi-Fi (last IP 192.168.0.171).

## Done
- M0.2: baseline checklist (`log/2026-11-02-M0-baseline-checklist.md`, `docs/02-baseline.md`): pass S3/S4/S5/S7/S8/battery; fail S6 audio, S9 suspend; GPS skipped.
- M0.3: RNDIS ssh to 10.15.19.82 works over USB-C<->USB-C with the usb-moded `-f` override; adb not exposed (`log/2026-11-02-M0.3-usb-access.md`, `docs/06-workflow.md`).
- M0.1: root SSH works (`ssh root@192.168.0.171 id -u` -> 0), `log/2026-11-02-M0.1-root-ssh.md`.
- M2.3: `tools/dt_table.py` round-trips stock dt.img/dtbo.img byte-identically; our dt.img/dtbo.img built with stock selection fields (`log/2026-11-02-M2.3-dt-images.md`). Stock images carry a Samsung signature + AVB footer, carried over stale; S-Boot acceptance unverified.
- M2.1: `exynos9610-a50.dtb` builds + dt-validate clean (`log/2026-11-01-M2.1-dt.md`, `reference/dt-6.18/`).
- M1.2: ACK `d9a614fe` GKI built (Kleaf 435 s; plain make 288 s). Image 43,670,016 B = 75.7% of BOOT budget (`log/2026-11-01-M1.2-ack-build.md`, `reference/ack-build/`).
- M1.1: baseline `Image` (`6d000a98…`) and boot.img (`7d5855ef…`) reproduced byte-identically on the host (`log/2026-11-01-M1.1-reproduce-baseline.md`, `reference/baseline-build/`). Needed an `nproc`=4 shim; `-j16` untested.
- Tickets for M0–M2 created in `tasks/` (12 tickets, index `tasks/README.md`).
- Context created: goal, device facts, baseline, kernel contract, gap matrix,
  plan, workflow, risks, ADR-0001/0002 (`log/2026-11-01-context-setup.md`).

## Open baseline defects (found in M0.2)
1. **Audio**: speaker/mic/call voice do nothing; BT audio works. Not yet diagnosed (userspace HAL vs kernel/ABOX firmware).
2. **Suspend**: never entered in a 12 min screen-off test.
3. GPS fix not tested.
Decision (owner, 2026-11-02): audio diagnosis is plan item M0.4 and runs before M1.3 (`tasks/M0.4-diagnose-baseline-audio.md`). Suspend defect stays recorded, no ticket yet.

## Open questions
- Does S-Boot boot `Image.gz`? (M1.4)
- Exact ioctl sets used by vendor HALs on mali/ion/decon/abox/scsc/modem (M1.3)

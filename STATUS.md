# STATUS

Updated: 2026-11-02 (evening)

## Current milestone: **M2.4 first light: attempt 1 FAILED (no output), baseline restored and verified**; diagnostic kernel proposed

M1.1 and M1.2 done. M2.1 and M2.3 done (fb pixel format accepted as a risk, resolve in M2.4). M0.1-M0.3 complete. M1.3 done (`reference/contract/`). NOTE: the M1.5 region choice was corrected on 2026-11-04 (last_kmsg = debug-snapshot log_kernel 0xf9010000; the baseline zeroes log_pstore), see the M1.5 log. M1.4: S-Boot does NOT boot a gzip kernel; use uncompressed `Image`, kernel <= 46,876,672 B. M1.5: after a panic the baseline keeps the log in `/proc/last_kmsg` (sec_debug region 0x91388000); pstore/ramoops at 0xf9d10000 stayed empty. M2.2 done: first-light `Image` 7,170,056 B (reproducible) and `boot-firstlight.img` (`src/m22/artifacts/`). M2.4 preparation done (DT ramoops moved to 0x91388000, new dt.img, `log/2026-11-04-M2.4-prep-dt-ramoops.md`). Start here: **`tasks/M2.4-first-light.md`** (needs the phone and the owner: DTB/DTBO via TWRP, BOOT via Heimdall, baseline fallback ready). Before M2.4: change the DT ramoops node to 0x91388000 (text in `log/2026-11-04-M1.5-ramoops.md`) and rebuild dt.img.

Summary: M2.1 DT is committed on branch `a50-dt` in `src/ack-6.18/common` (`4fd044c7c`). Open: fb format (resolve in M2.4), RAM bank count, ramoops (M1.5).

## State of the phone
Baseline installed and booting Ubuntu Touch 26.04 (`docs/02-baseline.md`):
BOOT `aa17rf2` (`7d5855ef…`), `/data/ubuntu.img` (`0d33d65d…`), stock
VENDOR/SYSTEM/DTB/DTBO, TWRP 3.7.1, vbmeta flags=3. SSH as `phablet` over
Wi-Fi (last IP 192.168.0.171).

## Done
- M2.4 attempt 1 (negative): flashed DTB+DTBO+BOOT with Heimdall (method A), phone sat on the Samsung warning screen, no text, no pstore; rolled back and verified (`log/2026-11-04-M2.4-first-light.md`). Lessons: do not run `heimdall print-pit` before a flash; S-Boot checks DT partition signatures; last_kmsg has no log of the attempt.
- M2.4 prep: DT ramoops moved to the proven sec_debug_next region (kernel commit 1a9a67e46), dt.img rebuilt (`reference/dt-6.18/images/`). Host-only.
- M2.2: `a50_firstlight_defconfig` (kernel commit f7accc40b), reproducible 7.2 MB Image, boot-firstlight.img 7,176,192 B, header equal to baseline except sizes (`log/2026-11-04-M2.2-firstlight-build.md`). Not tested on hardware.
- M1.5: controlled panic on the baseline; /proc/last_kmsg holds the crash log, pstore empty; 6.18 ramoops region proposed (`log/2026-11-04-M1.5-ramoops.md`).
- M1.4: gzip kernel bootloops S-Boot; baseline restored and verified (BOOT sha256 7d5855ef…). R1 budget in `docs/07-risks.md`.
- M1.3: vendor ioctl contract captured and decoded for mali, ion, display, audio, wifi/bt, modem (`reference/contract/README.md`). Notable: Samsung-only dma-buf TRACK/UNTRACK, ION ALLOC/HEAP_QUERY, S3CFB_WIN_CONFIG, IOCTL_MODEM_STATUS; audio HAL is 32-bit.
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
1. **Audio**: speaker FIXED by the UT-image session (userspace config, symlinks; restore step 5 in `docs/02-baseline.md`). **Microphone still captures no voice** (hiss/clicks); call uplink fails the same way (downlink works). First-playback hangs and a PulseAudio capture stall seen, cause unknown.
2. **Suspend**: works after the same fix; ~20% of attempts fail (214 ok / 52 fail).
3. GPS: HAL runs, no fix yet (open-sky test pending).
Decision (owner, 2026-11-02): M0.4 closed (playback = userspace config); microphone is tracked in `tasks/M0.5-mic-capture-defect.md` and handled by the UT-image session. Do not change mixer/PulseAudio state on the phone for mic work from this repo.

## Open questions
- Does S-Boot boot `Image.gz`? (M1.4)
- Exact ioctl sets used by vendor HALs on mali/ion/decon/abox/scsc/modem (M1.3)

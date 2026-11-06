# STATUS

Updated: 2026-11-02 (evening)

## Current milestone: **M3 Storage + USB: M3.1 + M3.2 done; next ticket = M3.3 (Exynos 9610 clock driver)**

M1.1 and M1.2 done. M2.1 and M2.3 done (fb pixel format accepted as a risk, resolve in M2.4). M0.1-M0.3 complete. M1.3 done (`reference/contract/`). NOTE: the M1.5 region choice was corrected on 2026-11-04 (last_kmsg = debug-snapshot log_kernel 0xf9010000; the baseline zeroes log_pstore), see the M1.5 log. M1.4: S-Boot does NOT boot a gzip kernel; use uncompressed `Image`, kernel <= 46,876,672 B. M1.5: after a panic the baseline keeps the log in `/proc/last_kmsg` (sec_debug region 0x91388000); pstore/ramoops at 0xf9d10000 stayed empty. M2.2 done: first-light `Image` 7,170,056 B (reproducible) and `boot-firstlight.img` (`src/m22/artifacts/`). M2.4 is in a diagnostic phase (see below). RESUME HERE: flash `src/m22/artifacts-diag4/boot-diag-D.img` (Test 5: diag v2 image A + the Samsung header magic 0xecefecef at Image offset 0x28; DT stays stock), wait 2 min, roll back BOOT with `heimdall flash --BOOT baseline/ut-26.04-2026-10-19-aa17rf2/boot.img`, boot UT, then `tools/m25_read_markers.sh <ip>`. Marker present = magic was the cause. Details: `log/2026-11-04-M2.4-diag-build.md`.

Summary: M2.1 DT is committed on branch `a50-dt` in `src/ack-6.18/common` (`4fd044c7c`). Open: fb format (resolve in M2.4), RAM bank count, ramoops (M1.5).

## State of the phone
Phone BOOT is the baseline (7d5855ef…), DTB/DTBO stock (verified by `tools/m24_preflight.sh <ip>`); last seen at 192.168.0.171. Kernel tree `src/ack-6.18/common` is on branch `a50-dt` (diag work is on branch `a50-diag`, do not merge).
Baseline installed and booting Ubuntu Touch 26.04 (`docs/02-baseline.md`):
BOOT `aa17rf2` (`7d5855ef…`), `/data/ubuntu.img` (`0d33d65d…`), stock
VENDOR/SYSTEM/DTB/DTBO, TWRP 3.7.1, vbmeta flags=3. SSH as `phablet` over
Wi-Fi (last IP 192.168.0.171).

## Done
- M2.4 Tests 1-4 (6.18 diagnostic images, various headers/sizes/ramdisk): all silent; control (baseline kernel + marker cave) booted and proved the marker channel and the S-Boot hand-off (0x80140000, EL1, MMU off, x0=DTB, x1-x3 non-zero). Leading hypothesis: S-Boot needs the Samsung Image header magic 0xecefecef at offset 0x28 (Test 5, built, not yet flashed).
- M2.4 control experiment (baseline Image + marker code cave): booted UT, marker found; S-Boot loads the Image at 0x80140000, EL1, MMU off, x0=DTB 0x8a000000, x1-x3 = 0x80000000/0x140000/0x80140000; the marker channel is validated, so the 6.18 diag negatives are real. Untested: diag v2 image B (`log/2026-11-04-M2.4-diag-build.md`).
- M2.4 Test 1 (diag v1, image B, stock DT): static screen and NO markers; v1 had a design flaw (marker after the framebuffer paint), fixed in v2 (built, not flashed; `log/2026-11-04-M2.4-diag-build.md`).
- M2.4 diagnostic kernel (branch a50-diag, boot-diag-A/B images, marker reader): built and verified on the host, test plan in `log/2026-11-04-M2.4-diag-build.md`. Not flashed yet; the phone is on the stock DT and baseline BOOT.
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


## RESUME HERE (2026-11-07)
6.18 runs on the phone and its boot log was read back: reference/m25-diag/2026-11-07-first-6.18-dmesg.txt.
How (all in log/2026-11-04-M2.4-diag-build.md, Tests 10-19):
- Tests 1-9 were blind: the marker channel was overwritten by the hard-reset recovery chain, not refusals by S-Boot.
- Visible channel: PMU SWRESET (0x11860000+0x400) = boot loop. Bisection found the hang: exynos_mct panics in time_init
  (stock DT MCT clocks have no 6.18 provider); with A50_DIAG_SKIP_MCT the kernel reaches late_initcall_sync.
- Readout: 6.18 appends its printk log at the DSS pointer 0xf9000200, writes PMU INFORM3 = 0x12345671, SWRESET ->
  Download mode by itself -> heimdall flash baseline WITH reboot -> /proc/last_kmsg. Button-free.
Kernel: branch a50-diag (diag v3-v6, patches in reference/m25-diag/), build `A50_DIAG=1 A50_DIAG_SKIP_MCT=1 A50_DIAG_DUMP_DSS=1
tools/m22_build.sh OUT`, pack `tools/m22_pack.sh`.
Owner decision 2026-11-07: M2.4 closed with the DSS-log readout; M2 DoD amended in docs/05-plan.md.
M3 planned 2026-11-07 (tickets M3.1-M3.7). M3.1 done 2026-11-07: S-Boot boots our DT despite "invalid" signature; log reference/m25-diag/2026-11-07-M3.1-ourdt-dmesg.txt. M3.2 done 2026-11-07: readout on panic and after N s (tools/m32_run_test.sh runs a whole button-free test). Next: tasks/M3.3-clock-driver-9610.md.
Phone: baseline BOOT 7d5855ef..., stock DTB/DTBO, UT up; IP 192.168.0.171.

## RESUME HERE (2026-11-05)
Tests 5 (header magic), 6 (chain loader) and 7 (control + 6.3 MB overwritten in place) were all negative; see
`log/2026-11-04-M2.4-diag-build.md`. Only the control (baseline Image, code0 edited, 60 bytes APPENDED) has ever run.
Next: Test 8. Flash `src/m22/artifacts-ctl3/boot-control-flip.img` (sha256 0c77f3f7..., control + one byte flipped at 0x1000000),
Download mode (wait for the "Downloading" screen, not the Warning screen), `heimdall flash --BOOT ... --no-reboot`, no print-pit.
Restart, wait 2 min, roll back with `heimdall flash --BOOT baseline/ut-26.04-2026-10-19-aa17rf2/boot.img --no-reboot`, boot UT,
then `tools/m25_read_control.sh <ip>`. Marker = small changes OK, bisect size; no marker = append the payload instead.
Phone: baseline BOOT 7d5855ef..., stock DTB/DTBO, verified after Test 7 rollback; IP 192.168.0.171 (asleep phones drop off Wi-Fi: press Power).

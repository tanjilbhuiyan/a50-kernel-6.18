# STATUS

Updated: 2026-11-10

## Current milestone: **M5 Ubuntu Touch userspace: M5.1 done (checker goal reworded, revisit later), M5.2 done (userdata-only writes); next = M5.3 (Halium init to systemd)**

M1.1 and M1.2 done. M2.1 and M2.3 done (fb pixel format accepted as a risk, resolve in M2.4). M0.1-M0.3 complete. M1.3 done (`reference/contract/`). NOTE: the M1.5 region choice was corrected on 2026-11-04 (last_kmsg = debug-snapshot log_kernel 0xf9010000; the baseline zeroes log_pstore), see the M1.5 log. M1.4: S-Boot does NOT boot a gzip kernel; use uncompressed `Image`, kernel <= 46,876,672 B. M1.5: after a panic the baseline keeps the log in `/proc/last_kmsg` (sec_debug region 0x91388000); pstore/ramoops at 0xf9d10000 stayed empty. M2.2 done: first-light `Image` 7,170,056 B (reproducible) and `boot-firstlight.img` (`src/m22/artifacts/`). M2.4 closed 2026-11-07 (log/2026-11-04-M2.4-diag-build.md).

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


## RESUME HERE (2026-11-10)
M3 done. On 6.18: the Halium ramdisk contents are embedded in the kernel (305 files verified), /userdata mounts read-only with the A50_UFS_SAFE write guard, and telnet at 192.168.2.15 gives a shell over USB (log/2026-11-10-M3.7-halium-initramfs.md).
CAVEAT (owner accepted): the mount and telnet were done by our diagnostic init (rdinit=/a50/init). Halium's own /init has not run; it runs e2fsck -y on userdata and may run resize2fs, so it needs deliberate write access. That is M5 work.
A ramdisk in boot.img does not reach 6.18, so the Halium ramdisk is embedded in the kernel (tools/m37/gen_embed_list.py). Why S-Boot does not deliver it, and other set-aside questions: docs/08-open-questions.md.
Next: tasks/M5.3-halium-init-systemd.md test 2 (CONFIG_UNIX/PACKET added; first cross-check systemd kernel requirements). Test 1: Halium init ran on 6.18 but udev failed without CONFIG_UNIX -> "Couldn't find data partition"; nothing written (log/2026-11-10-M5.3-halium-init.md). M5.2 done: ubuntu.img backed up and verified (../a50-ubuntu-img-backup/, sha256 22cb95a5…); 6.18 wrote a scratch file inside userdata (guard allow-list LUN 0 blocks 0x1c8700-0xee42ff), read back on the baseline, e2fsck -n clean before/after. M5 checker goal reworded by the owner, to revisit later. M5.1: Halium config via A50_HALIUM=1 (tools/m51/halium.flags), modern-first (nftables, CONFIG_LSM/AppArmor, cgroup v2); boots with all M3/M4 checks passing.
Owner rule 2026-11-10: prefer 6.18-native mechanisms over 4.14-era or legacy ones.
M4 done on the clean kernel branch a50-core (a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> PHY supply fix): all 8 CPUs, ACPM, 35 S2MPU09 regulators (read-only driver), read-only thermal (4 zones), no missing-supply warnings, M3 functions intact (log/2026-11-10-M4.8-integration.md). Owner decisions 2026-11-10: cpufreq out of M4 (DVFS needs a firmware plugin 6.18 does not set up); thermal read directly from the TMU registers; power domains read-only (control in M12).
Open from M4: real I2C controllers freeze 6.18 (a50-bus; do not boot it with I2C enabled), so S2MPB03, keys and PL330 are untested (docs/08-open-questions.md #8). Sending requests on ACPM channel 7 (thermal) stalls the firmware for the boot: do not.
To work again (owner, 2026-11-10): M4.4 real I2C (plan in the ticket; needed before M7/M8) and M4.7 CPU frequency (deferred, possible route without the firmware plugin in the ticket).
Kernel branches: a50-dt -> a50-clk -> a50-pinctrl -> a50-ufs -> a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> a50-core (clean, M4 done); a50-bus (on a50-pmic, has the I2C nodes that freeze the phone); a50-diag (readout, do not merge); a50-m36-clean (a50-usb + a50-diag, test merge); a50-m36-test, a50-m36-min, a50-m37-test (test only, do not merge).
Test loop: DT_IMG=src/m36/dt-clean.img tools/m32_run_test.sh IMG OUT IP WAIT. Build: tools/m22_build.sh with A50_INIT, A50_INITRAMFS_LIST=src/m37/embed.list.in, A50_CMDLINE_APPEND, A50_CONFIG (the M3.7 flags are in log/2026-11-10-M3.7-halium-initramfs.md and the test init tools/m37/init-telnet). Any UFS-enabled kernel must carry A50_UFS_SAFE.
Host: USB-C cable only. Laptop keeps udev rule 99-a50-acm.rules and NetworkManager profile a50-rndis (192.168.2.1) for the test gadget. Clients: tools/m36/acm_shell.py, tools/m37/telnet_test.py.
Phone: baseline BOOT 7d5855ef..., stock DTB/DTBO, verified 2026-11-10 13:10; DHCP, 192.168.0.171 at home (192.168.181.225 at the office).
A failed Heimdall handshake leaves Download mode stuck; a replug does not clear it, the key combo does (docs/06-workflow.md).

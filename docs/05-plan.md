# 05 — Plan: milestones, tasks, Definition of Done

Order is strict: a milestone starts only when the previous DoD is met and
logged. Tickets for the current and next milestone live in `tasks/` (index: `tasks/README.md`). Each task produces evidence in `log/` and, where relevant, a commit.

Exception (2026-11-01, owner): the phone is in daily use, so the host-only
tasks **M1.1** (reproduce baseline 4.14 build) and **M1.2** (ACK 6.18 GKI
build) may run before M0 is done. Every task that touches the phone still
waits for M0's DoD.

## M0 — Baseline locked and measured
Tasks
1. Complete the baseline function checklist (`02-baseline.md` gaps): audio
   playback/record, BT pairing, GPS fix, call + SMS, suspend counters.
2. Install a root SSH key on the phone (owner runs one sudo command).
3. Resolve or document the USB-C PD detection workaround as standard procedure.
4. (Added 2026-11-02, owner) Diagnose why baseline audio fails (kernel vs userspace)
   before M1.3, because M0.2 found speaker/mic/call voice dead on the baseline and
   M1.3 cannot capture the audio HAL's ioctls until we know why (`tasks/M0.4-…`).
   Baseline suspend failure is recorded but not diagnosed here.
   Outcome 2026-11-02: playback = userspace config (fixed upstream-side, see restore
   step 5 in `docs/02-baseline.md`); suspend started working with the same fix.
5. (Tracking only, added 2026-11-02, owner) Microphone captures no voice on the
   baseline: `tasks/M0.5-mic-capture-defect.md`, handled by the UT-image session, does
   not block M1.3.
DoD: `log/` has a dated baseline checklist with ✅/❌ per S3–S9 item; root SSH works;
the baseline audio failure is classified as kernel, firmware, HAL or config (done: userspace config).

## M1 — Reproducible build + contract capture
Tasks
1. Reproduce the baseline kernel from `src/samsung-a50-4.14-aa17rf2` in a
   container; produce an `Image` byte-identical to the one inside
   `baseline/…/boot.img` (the a50-halium author did this; method in that repo).
2. Clone ACK `android17-6.18` (https://android.googlesource.com/kernel/common,
   branch `android17-6.18`) into `src/ack-6.18`; build `gki_defconfig` for
   arm64 with clang + Rust in a container. Record toolchain versions.
3. Contract capture on the baseline (root): for each node in
   `03-kernel-contract.md` §2b, record opener process and ioctl numbers
   (ftrace `sys_enter_ioctl` filtered by fd/path, or bpftrace if available).
   Save to `reference/contract/`.
4. Verify on the phone: does S-Boot accept `Image.gz`? (flash a baseline
   boot.img repacked with Image.gz; one variable.)
5. Verify ramoops: add `ramoops` at 0xf9d10000/0x200000 to a baseline-kernel
   DT test or read `/sys/fs/pstore` as root after a forced panic.
DoD: byte-identical baseline Image; ACK 6.18 GKI builds; contract files exist
for mali, ion, fb/decon, abox, scsc, modem nodes; Image.gz answer logged;
pstore readable after reboot.

## M2 — First light on 6.18
Tasks (tickets in `tasks/`)
1. M2.1 A50 device tree for 6.18, first-light subset (cpus, psci, gic, timer,
   memory, reserved-memory incl. ramoops, simple-framebuffer @0xca000000).
2. M2.2 Minimal defconfig + tiny initramfs + boot.img (header v1, ≤ 57,671,680 B).
3. M2.3 DTB/DTBO partition images in the stock dt_table format (tool round-trips stock images).
4. M2.4 First light on the phone (flash BOOT, read the 6.18 log back after reboot, restore).
DoD (amended 2026-11-07, owner decision): a 6.18 kernel runs on the A50 and its
boot log (containing `Linux version 6.18`) is read back after a reboot from the
baseline (via the debug-snapshot log_kernel buffer / `/proc/last_kmsg`). Baseline
still restorable.
Why amended: the original DoD asked for pstore and framebuffer text. pstore was
replaced by the DSS buffer, the only readout that survives this phone's reboot
paths (log/2026-11-04-M2.4-diag-build.md, Tests 9-19). Framebuffer text is not
achievable before a display driver exists: the panel is command-mode and never
shows framebuffer writes (accepted M2.1 risk; moves to M7). M2.4 ran with the
STOCK DTB/DTBO and a diag kernel (MCT init skipped); booting with our own DT is
carried forward as open work.

## M3 — Storage + USB access
Tasks (tickets in `tasks/`; list changed 2026-11-07, see "Why" below)
1. M3.1 Boot with our own DTB/DTBO (reserve the debug-snapshot region, drop the unproven ramoops placement).
2. M3.2 Readout at any time (dump + reboot to Download mode on panic or after a delay).
3. M3.3 Exynos 9610 clock driver, only the CMUs that UFS and USB need.
4. M3.4 Exynos 9610 pinctrl data (backport).
5. M3.5 UFS storage, read-only (ufs-exynos 9610 data + PHY).
6. M3.6 USB device mode (DRD + PHY 9610 data, configfs gadget RNDIS + ACM; sm5713 role/VBUS minimal or bypassed; if the USB LDOs turn out to be the blocker, the minimum to read and then enable LDO12-14 through ACPM IPC, pulled forward from M4).
7. M3.7 Halium initramfs on 6.18: mount `/data`, telnet over USB (the M3 DoD).
Why changed (2026-11-07): M2 closed without our DT and without clocks/pinctrl
(the gap matrix had listed clocks and pinctrl under M2, but first light did not
need them). UFS and USB cannot work without them, and every later test needs a
readout that works after init. M3.1-M3.4 are those prerequisites.
Why changed (2026-11-08): M3.6 Test 3 (`log/2026-11-08-M3.6-usb.md`) put the USB switch on USB and left the controller running with no attach. The baseline powers USB from LDO12/13/14 (live `/sys/class/regulator`), and 6.18 has no PMIC access, so their state is unverified. On this phone PMIC access goes through the ACPM firmware (`s2mpu09_read_reg` -> `exynos_acpm_read_reg`, 4.14 `drivers/mfd/s2mpu09-core.c:53`), so the probe uses ACPM IPC and does not drive the SPEEDY bus. Read-only first; any PMIC write is a separate step with the owner's approval. The full PMIC/regulator work stays in M4.
Why changed (2026-11-09): M3.6 Tests 3-8 ruled out the suspects findable from source, and the D+ line never rises on 6.18 (`log/2026-11-08-M3.6-usb.md`). The baseline kernel has no `/dev/mem` and refuses all modules (`CONFIG_UH_LKM_BLOCK`), so M3.6 adds one diagnostic: a 4.14 test kernel (baseline source + a built-in read-only register dump), flashed to BOOT only with the usual rollback, to read the PHY and USB clock registers of a working phone. It is a measurement tool, never a replacement for the baseline.
DoD: Halium initramfs on 6.18 mounts `/data` and exposes telnet
`192.168.2.15` over USB from the laptop.
DoD evaluation (2026-11-10, owner accepted): met with a caveat. Halium's ramdisk contents are in the 6.18 kernel, `/userdata` is mounted read-only and telnet works over USB, set up by our diagnostic init. Halium's own `/init` has not run: it needs write access (`e2fsck -y`, `resize2fs`), so running it moves to M5.

## M4 — Core SoC
Tickets M4.1-M4.8 in `tasks/`. Tasks: all CPUs online, ACPM IPC, s2mpu09/s2mpb03
PMIC + regulators, power domains, TMU, PL330, I2C/PWM/keys, CPU frequency via ACPM DVFS.
Why changed (2026-11-10): "speedy bus" removed. PMIC access on this phone goes through the ACPM firmware (4.14 `drivers/mfd/s2mpu09-core.c:53`), proven read-only on 6.18 in M3.6 Test 4. All-CPUs bring-up made an explicit ticket; every 6.18 test so far ran with `maxcpus=1`.
DoD: all 8 CPUs online, thermal zones readable, regulators enumerated, no
warnings from missing supplies at boot. (cpufreq scaling removed 2026-11-10, see below.)
DoD evaluation (2026-11-10): met on the clean `a50-core` kernel (`log/2026-11-10-M4.8-integration.md`). Open, outside the DoD: real I2C freezes 6.18 (M4.4 blocked: S2MPB03, keys and PL330 untested); power domains are read-only.
Why changed (2026-11-10, owner decision): on this phone CPU frequency and voltage changes go through an ACPM firmware plugin that 4.14 sets up at boot and 6.18 does not (`log/2026-11-10-M4.6-thermal.md`). Without it there is no safe way to set CPU voltages, so cpufreq leaves the M4 DoD and the CPUs stay at the bootloader's frequency. M4.7 is deferred. Thermal is read directly from the TMU registers (read-only), not through ACPM. Power domains: read-only reporting in M4 (all 8 need secure-firmware calls to switch); control deferred to M12.

## M5 — Ubuntu Touch userspace boots (no hardware HALs yet)
Tasks: full Halium config (checker clean), AppArmor, loop, LXC; boot baseline
`ubuntu.img`.
DoD: systemd reaches multi-user; SSH over USB RNDIS; every `halium-check-kernel-config`
option that exists in 6.18 is set as wanted or replaced by its 6.18-native mechanism, the rest
listed with reasons; Android container may fail (expected until M6).
Why changed (2026-11-10, owner decision): the checker predates 6.18 (the working 4.14 baseline
scores 107 errors on it; `log/2026-11-10-M5.1-halium-config.md`), so "zero errors" cannot be
reached. The owner wants the checker goal revisited later.
Acceptance clarification (2026-11-10, owner approved following the test-4 review):
M5 may use per-boot `systemd.mask=` for rild, ofono, bluebinder and
a50-audio-route while hardware HALs are unavailable. Masks must be runtime-only,
recorded in the test evidence, with the rootfs unchanged. Systemd must actually
reach multi-user and running/degraded; remaining failed units still require review.
M5.3 result (2026-11-10): test 5 reached multi-user at 84.17 s and degraded
with zero jobs at 122/201 s; Android/device-helper failures reviewed and baseline
restored clean (`log/2026-11-10-M5.3-split-control-test5.md`). M5.4 SSH still pending.

## M6 — Android container + ION
Tasks: binder/binderfs, Rust ashmem, legacy ION ABI shim + Exynos heaps,
SysMMU, sync_file, wakelocks.
DoD: `sys.boot_completed=1` in container; `android.hardware.graphics.allocator@2.0-service`
running; ION allocations succeed (contract capture replay).

## M7 — Display + GPU (Lomiri UI)
Tasks: dpu20 DECON/DPP/DSIM + panel forward-port preserving ioctls; Mali kbase
r26p0 forward-port; G2D only if contract requires.
DoD: S2 (Lomiri visible, accelerated); 10-minute UI soak without GPU faults.

## M8 — Input: touch, keys, hall, vibrator
DoD: S3.

## M9 — Wi-Fi + Bluetooth (SCSC)
DoD: S4 + S8.

## M10 — Audio (ABOX + TFA9872)
DoD: S6.

## M11 — Modem (modem_v1, mcu_ipc, shm_ipc)
DoD: S7.

## M12 — Power: battery/charger, suspend, devfreq, USB modes
DoD: S5, S9; 10 suspend/resume cycles; charge state correct.

## M13 — Stretch: camera, MFC, sensors, GNSS, Waydroid
DoD per item, optional.

## Future candidates (not in project DoD; need an accepted ADR first)

| ID | Candidate | Earliest start | ADR |
|---|---|---|---|
| F1 | Newer Halium GSI (13 → 14 → 16) on the 6.18 kernel with the stock Android 11 vendor | after M7 DoD | `decisions/ADR-0003-newer-halium-future.md` (Proposed, deferred) |

## Project done
S1–S10 in `00-goal.md` met and logged; baseline vs. new checklist diff
shows no regression.

# 05 — Plan: milestones, tasks, Definition of Done

Order is strict: a milestone starts only when the previous DoD is met and
logged. Each task produces evidence in `log/` and, where relevant, a commit.

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
DoD: `log/` has a dated baseline checklist with ✅/❌ per S3–S9 item; root SSH works.

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
Tasks
1. New board DT `exynos9610-a50.dts` (6.18 bindings): cpus, psci, gic, timer,
   memory, reserved-memory (incl. ramoops), simple-framebuffer @0xca000000,
   fixed clocks, pinctrl (backported 9610 data), clocks (LKML series).
2. Minimal defconfig (no modules needed yet), built-in cmdline.
3. Pack boot.img (header v1, offsets from `01-device.md`) with a tiny
   initramfs that draws to fb / writes pstore then reboots.
4. Write DTB/DTBO from TWRP only after verifying stock DTB/DTBO backups.
DoD: a 6.18 kernel prints to pstore (readable after reboot from TWRP or
baseline) and shows text on the simple framebuffer. Baseline still restorable.

## M3 — Storage + USB access
Tasks: UFS (ufs-exynos 9610 data + PHY), USB DRD + PHY 9610 data, sm5713
VBUS/role detection minimal, configfs gadget RNDIS + ACM.
DoD: Halium initramfs on 6.18 mounts `/data` and exposes telnet
`192.168.2.15` over USB from the laptop.

## M4 — Core SoC
Tasks: speedy bus, s2mpu09/s2mpb03 PMIC + regulators, ACPM IPC, power
domains, TMU, PL330, I2C/PWM/keys, CPU frequency via ACPM DVFS.
DoD: all 8 CPUs online, cpufreq scaling between min/max, thermal zones
readable, regulators enumerated, no warnings from missing supplies at boot.

## M5 — Ubuntu Touch userspace boots (no hardware HALs yet)
Tasks: full Halium config (checker clean), AppArmor, loop, LXC; boot baseline
`ubuntu.img`.
DoD: systemd reaches multi-user; SSH over USB RNDIS; `halium-check-kernel-config`
zero errors; Android container may fail (expected until M6).

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

## Project done
S1–S10 in `00-goal.md` met and logged; baseline vs. new checklist diff
shows no regression.

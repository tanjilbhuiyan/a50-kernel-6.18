# STATUS

Updated: 2026-11-10 (cleanup: one current record; superseded history is in `log/`, `tasks/README.md` and git history of this file)

## How to use this file (Claude Code and Codex)
Both tools work on this project. Claude Code reads `CLAUDE.md`; Codex enters through `AGENTS.md`, which defers to `CLAUDE.md`.
Read this file, then the active ticket and its log. Before trusting anything here, check `git status` in the outer repo and the
branch in `src/ack-6.18/common`. One tool at a time on the kernel checkout and on the phone. At the end of a session, update
**RESUME HERE** with commits, branch, image hashes, last test and rollback result, and the next action.

## RESUME HERE (2026-11-10)
- **Milestone:** M5 Ubuntu Touch userspace. M5.1 done, M5.2 done, **M5.3 in progress**, M5.4 todo.
- **Active ticket:** `tasks/M5.3-halium-init-systemd.md`, log `log/2026-11-10-M5.3-halium-init.md`.
- **Last result:** test 1 (boot-m53-1.img `05a8b0b8…`, kernel branch `a50-m53-test` `fb341b651`): Halium's own `/init` ran on 6.18,
  but `systemd-udevd` failed ("Address family not supported by protocol": `CONFIG_UNIX` off), so there was no
  `/dev/disk/by-partlabel/userdata` and Halium stopped with "Couldn't find data partition". Nothing mounted, nothing written.
  Rollback and pre-flight passed (14:33).
- **Fix in place, untested:** `UNIX` and `PACKET` added to `tools/m51/gen_halium_flags.py` -> `tools/m51/halium.flags`.
- **Next action:** cross-check the config against systemd's own kernel requirements (the old Halium checker assumes basics such as
  `CONFIG_UNIX`), then build and run M5.3 test 2 (build line below, `A50_DIAG_DUMP_AFTER=240`, runner `WAIT` 340).
- **Expected in M5.3:** EFS (`sda3`) is mounted rw by the Android side on the 4.14 baseline; on 6.18 the guard refuses every write
  outside userdata, so expect ext4/IO errors for it, not changes. Userdata is mounted with `discard`; UNMAP stays blocked by the
  guard (the sd driver should switch discard off after the first refusal, unverified on 6.18).

## State of the phone (last verified 2026-11-10 14:33, after M5.3 test 1)
Baseline BOOT `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5`, stock DTB/DTBO (verified by the runner's
pre-flight). Ubuntu Touch 26.04 on 4.14, root SSH. DHCP: 192.168.0.171 at home, 192.168.181.225 at the office.
Userdata holds `/userdata/a50-m52-scratch.txt` (96 B, M5.2 evidence, left on purpose).
Backup of `ubuntu.img` (2026-11-10, before any 6.18 write): `../a50-ubuntu-img-backup/ubuntu.img-2026-11-10`, sha256
`22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896`, read-only. Full restore: `docs/02-baseline.md`.

## Kernel tree `src/ack-6.18/common` (not pushed; patches are exported to `reference/m*/`)
Checkout: `a50-usb` (clean). Check it before any build: builds check out a test branch and return to `a50-usb`.
- Clean driver stack: `a50-dt -> a50-clk -> a50-pinctrl -> a50-ufs -> a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> a50-core`
  (`364673845`, M4 done) `-> a50-userdata` (`44c3fffab`, M5.2 write allow-list).
- `a50-diag` (`88040ffc9`, v8: DSS readout, panic dump, sync before the timed dump): diagnostics, do not merge into clean branches.
- `a50-bus` (on `a50-pmic`): I2C/PWM/keys DT. **Do not boot with its I2C nodes enabled: it freezes the phone.**
- Test branches, do not merge: `a50-m36-*`, `a50-m37-test`, `a50-m42-test` to `a50-m46-test*`, `a50-m48-test`, `a50-m52-test` (m48 + userdata),
  `a50-m53-test` (m52 + diag v8).

## Build and test loop
- Build (M5.3 form), from the outer repo with the kernel on the test branch:
  `A50_HALIUM=1 A50_DIAG=1 A50_DIAG_DUMP_DSS=1 A50_DIAG_DUMP_AFTER=240 A50_INITRAMFS_LIST=$PWD/src/m37/embed.list.in
  A50_CMDLINE_APPEND="clk_ignore_unused printk.devkmsg=on systemd.log_target=kmsg systemd.journald.forward_to_kmsg=1 systemd.show_status=1"
  A50_CONFIG="<M3.7 base flags> $(tr '\n' ' ' < tools/m52/userdata.flags)" tools/m22_build.sh src/ack-6.18/out/<name>`;
  the base flags are in `log/2026-11-10-M3.7-halium-initramfs.md`. Pack: `tools/m22_pack.sh IMAGE OUT.img`.
- `A50_HALIUM=1` applies `tools/m51/halium.flags`; `rdinit=/a50/init` in `A50_CMDLINE_APPEND` runs our diagnostic init instead of
  Halium's (`A50_INIT=tools/m48/init`, `tools/m52/init-write`, ...). S-Boot drops the boot.img cmdline: `CONFIG_CMDLINE` is what counts.
- Test: `DT_IMG=src/m48/dt.img tools/m32_run_test.sh IMG OUT_DUMP PHONE_IP WAIT_S`: pre-flight, flash our DT+BOOT, 6.18 dumps its
  log and returns to Download mode, rollback to stock DT + baseline BOOT, read the dump, pre-flight again.
- Readout when a boot sticks: telnet `192.168.2.15` over USB RNDIS (our init, or Halium's panic handler); `tools/m37/telnet_test.py`.
- Guard: any UFS-enabled kernel must carry `A50_UFS_SAFE` (the build script refuses otherwise). Writes are allowed only inside
  userdata, LUN 0 blocks `0x1c8700-0xee42ff` (`tools/m52/userdata.flags`); host test `tools/m52/guard_unittest.py`.
- Host: USB-C cable only. udev rule `99-a50-acm.rules`, NetworkManager profile `a50-rndis` (192.168.2.1). Host sudo is run by
  the owner in a local terminal; verify its effect with a real conditional before flashing.
- A failed Heimdall handshake leaves Download mode stuck; a replug does not clear it, the key combo does (`docs/06-workflow.md`).

## Owner rules and decisions in force
- Prefer 6.18-native mechanisms over 4.14-era or legacy ones (nftables, `CONFIG_LSM`, cgroup v2, mainline drivers) (2026-11-10).
- Take the shortest route to the ticket's acceptance; record side questions in `docs/08-open-questions.md` instead of chasing them.
- Do not send requests on ACPM channel 7 (thermal): it stalls the firmware for the boot. Do not pursue loading ACPM firmware plugins.
- Do not change mixer or PulseAudio state on the phone. Never commit device identifiers (check `grep -c 'R28[M]'` (phone serial prefix) before commit and push).
- M5 checker goal reworded (2026-11-10): every checker option that exists in 6.18 is set or replaced by its 6.18-native mechanism,
  the rest listed with reasons. To revisit later.

## Done (details in each log; index `tasks/README.md`)
- **M0** baseline locked and measured; **M1** reproducible builds, vendor ABI captured; **M2** first light on 6.18.
- **M3** storage + USB: our DT, readout at any time, clocks, pinctrl, read-only UFS with the guard, USB gadget (ACM/RNDIS),
  Halium ramdisk embedded in the kernel (a boot.img ramdisk does not reach 6.18), telnet over USB. Caveat: our init, not Halium's.
- **M4** core SoC on `a50-core`: 8 CPUs, ACPM, 35 S2MPU09 regulators (read-only), power domains (read-only), thermal (4 zones).
- **M5.1** Halium/UT config via `A50_HALIUM=1`, modern-first. **M5.2** `ubuntu.img` backed up; 6.18 writes inside userdata only,
  scratch file read back on the baseline, `e2fsck -n` clean before and after.

## Deferred, to work again
- M4.4 real I2C (freezes 6.18; plan in the ticket; needed before M7/M8). Blocks M4.3 S2MPB03, keys, PL330.
- M4.7 CPU frequency (dropped from M4; route without the firmware plugin in the ticket).
- M5.1 checker goal (see above). M0.5 microphone (UT-image session).
- Open questions (ramdisk delivery, one-off hang, I2C freeze, ...): `docs/08-open-questions.md`.

## Open baseline defects (found in M0.2, still valid)
1. **Audio**: speaker fixed (userspace config, `docs/02-baseline.md` restore step 5). **Microphone captures no voice**; call uplink
   fails the same way. Tracked in `tasks/M0.5-mic-capture-defect.md`.
2. **Suspend**: ~20% of attempts fail (214 ok / 52 fail).
3. GPS: HAL runs, no fix yet (open-sky test pending).

# STATUS

Updated: 2026-11-10 (M5 complete, M5.4 USB SSH; superseded history is in `log/`, `tasks/README.md` and git history of this file)

## How to use this file (Claude Code and Codex)
Both tools work on this project. Claude Code reads `CLAUDE.md`; Codex enters through `AGENTS.md`, which defers to `CLAUDE.md`.
Read this file, then the active ticket and its log. Before trusting anything here, check `git status` in the outer repo and the
branch in `src/ack-6.18/common`. One tool at a time on the kernel checkout and on the phone. At the end of a session, update
**RESUME HERE** with commits, branch, image hashes, last test and rollback result, and the next action.

## RESUME HERE (2026-11-10)
- **Milestone:** **M5 complete** under the recorded M5.1 config interpretation, four runtime HAL masks and diagnostic USB
  fallback/rescue mode. Next M6 Android container + ION; **start tasks/M6.1-android-runtime-abi-audit.md**. No M6 code started.
- **Latest log:** `log/2026-11-10-M5.4-usb-ssh.md`. M5.4 root SSH verified twice over USB on 6.18.33-a50-diag+, with trusted
  baseline host key and route-to-phone explicitly using USB enp6s0f4u1. Final endpoint 10.15.19.82:22, host DHCP 10.15.19.5.
  lxc-info android STOPPED (expected until M6); systemd settled degraded with zero jobs and the seven known hardware failures.
- **Fix:** added NETDEVICES to tools/m51 Halium prerequisites. Without it, SO_BINDTODEVICE returns ENOPROTOOPT and packaged
  udhcpd fails even though USB RNDIS itself works. Test 2 verifies udhcpd active/running and DHCP OFFER/ACK, no new failed units.
  Full olddefconfig delta archived (new network menus and PPS/PTP defaults included); no UFS guard/cmdline/USB function changes.
- **USB method:** generated Halium /init creates only /run/usb-moded/99-a50-m54.conf with USB_MODED_ARGS="-f -r" before the
  original handoff. Packaged fallback/rescue selects RNDIS developer mode despite missing charger detection/charging functions.
  No persistent rootfs/vendor/auth changes. Main root SSH port 22 used; host needed no temporary profile from the watcher.
- **Operational limits:** automatic cable/role detection, other modes and legacy usb-tethering/dual DHCP ownership remain M12;
  evidence and follow-up in docs/08-open-questions.md. Both DHCP helpers run, but tested lease came from packaged Busybox udhcpd.
- **Config checkpoint:** current checker reports 89 differences, exactly the same red CONFIG diagnostics as accepted M5.1 modern
  config. Classification/replacements documented; broader checker/controller/BPF_JIT/KCMP review remains deferred by owner.
- **Source/artifacts:** M5.4 preparation 8434c1a; NETDEVICES fix/first SSH proof b18a792. Result evidence accompanies this update.
  Final image `src/m54/boot-m54-netdevices.img`, SHA eb86ac8c5228c5d0182590dc7bf74bf6e25f1598e12da4e952c660657a4ed9a4.
  Inputs/checks/SSH/DHCP/dumps under reference/m54-usb-ssh/. Kernel source is committed a50-m54-test/f0618ab59; no source edits.
- **Guard:** clean a50-userdata/c7bde3fe3, included in test source. WRITE(10/16) policy denials report DATA_PROTECT; other denied
  operations ILLEGAL_REQUEST. One UNMAP refusal, no WRITE(6)/FUA fallback or userdata errors; userdata rw at all snapshots.
- **Checkout:** kernel clean on a50-usb/4fbb731f5. To reproduce M5 USB access, use a50-m54-test and the M5.4 build recipe below.
- **Next action:** M6.1 saved-evidence audit of Android mount/runtime/ABI requirements before enabling binder/Rust ashmem/ION.
  M6.1-M6.4 tickets exist. Preserve working USB access and guard; do not start hardware HAL work ahead of its milestone.

## State of the phone (verified after M5.4 test 2, 2026-11-10)
Baseline BOOT `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5`, stock DTB/DTBO verified by post-flight.
Current connection **home IP 192.168.0.171**. Baseline 4.14, uptime since 20:14:39, battery 100% Full; root SSH works.
Baseline init's saved fsck output clean: 6309/3440640 files, 1971988/13745152 blocks, no repairs. Userdata rw,data=journal;
M5.4 runtime override absent. Raw proof reference/m54-usb-ssh/netdevices-baseline-fsck.txt. No mounted-filesystem checker run.
M5.3 masks also remain per-boot only. USB test host profiles were not created by the watcher, so no cleanup needed.
Userdata retains the M5.2 scratch file. Read-only backup (2026-11-10 before writes):
`../a50-ubuntu-img-backup/ubuntu.img-2026-11-10`, sha256
`22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896`; rechecked before M5.4. Restore: docs/02-baseline.md.

## Kernel tree `src/ack-6.18/common` (not pushed; patches are exported to `reference/m*/`)
Checkout: `a50-usb` (clean). Check it before any build: builds check out a test branch and return to `a50-usb`.
- Clean driver stack: `a50-dt -> a50-clk -> a50-pinctrl -> a50-ufs -> a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> a50-core`
  (`364673845`, M4 done) `-> a50-userdata` (`c7bde3fe3`, write allow-list + corrected denial sense split).
- `a50-diag` (`88040ffc9`, v8: DSS readout, panic dump, sync before the timed dump): diagnostics, do not merge into clean branches.
- `a50-bus` (on `a50-pmic`): I2C/PWM/keys DT. **Do not boot with its I2C nodes enabled: it freezes the phone.**
- Test branches, do not merge: `a50-m36-*`, `a50-m37-test`, `a50-m42-test` to `a50-m46-test*`, `a50-m48-test`, `a50-m52-test` (m48 + userdata),
  `a50-m53-test` (m52 + diag v8); a50-m53-3/4 historical broad sense; a50-m53-split/5 and a50-m54-test `f0618ab59` corrected split.

## Build and test loop
- For the working M5.4 USB access image, run `python3 -I tools/m54/make_force_init.py` to regenerate init/list.
- Build (M5.4 form), from the outer repo with the kernel on the test branch:
  `A50_HALIUM=1 A50_DIAG=1 A50_DIAG_DUMP_DSS=1 A50_DIAG_DUMP_AFTER=240 A50_INITRAMFS_LIST=$PWD/src/m54/embed-force.list.in
  A50_CMDLINE_APPEND="clk_ignore_unused printk.devkmsg=on systemd.log_target=kmsg systemd.journald.forward_to_kmsg=1 systemd.show_status=1 systemd.mask=rild.service systemd.mask=ofono.service systemd.mask=bluebinder.service systemd.mask=a50-audio-route.service"
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
- M5 runtime masks are temporary (2026-11-10): M6.4 boots once without them and records what still blocks; bluebinder is
  removed in M9, a50-audio-route in M10, rild/ofono in M11 (each milestone's DoD in `docs/05-plan.md`).

## Done (details in each log; index `tasks/README.md`)
- **M0** baseline locked and measured; **M1** reproducible builds, vendor ABI captured; **M2** first light on 6.18.
- **M3** storage + USB: our DT, readout at any time, clocks, pinctrl, read-only UFS with the guard, USB gadget (ACM/RNDIS),
  Halium ramdisk embedded in the kernel (a boot.img ramdisk does not reach 6.18), telnet over USB. Caveat: our init, not Halium's.
- **M4** core SoC on `a50-core`: 8 CPUs, ACPM, 35 S2MPU09 regulators (read-only), power domains (read-only), thermal (4 zones).
- **M5.1** Halium/UT config via `A50_HALIUM=1`, modern-first. **M5.2** `ubuntu.img` backed up; 6.18 writes inside userdata only,
  scratch file read back on the baseline, `e2fsck -n` clean before and after.
- **M5.3** Halium init boots ubuntu.img to multi-user/degraded with approved runtime HAL masks.
- **M5.4 / M5** USB RNDIS root SSH verified; packaged DHCP fixed by NETDEVICES, M5 DoD evaluated with accepted exceptions and clean restore.
- M6 tickets created; implementation not started.

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

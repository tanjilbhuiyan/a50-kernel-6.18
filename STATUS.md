# STATUS

Updated: 2026-11-14 (M6 checkpoint and portable build; stock restored; M7.1 next)

## How to use this file (Claude Code and Codex)
Both tools work on this project. Claude Code reads `CLAUDE.md`; Codex enters through `AGENTS.md`, which defers to `CLAUDE.md`.
Read this file, then the active ticket and its log. Before trusting anything here, check `git status` in the outer repo and the
branch in `src/ack-6.18/common`. One tool at a time on the kernel checkout and on the phone. At the end of a session, update
**RESUME HERE** with commits, branch, image hashes, last test and rollback result, and the next action.

## RESUME HERE (2026-11-14)
- **Connection:** home `192.168.0.171`. Final stock restore completed 2026-11-14 at 02:57:44, baseline boot time
  02:57:58, battery 100% Charging. DTB/DTBO/BOOT post-flight hashes passed; saved baseline fsck clean. No test active.
  Owner confirmed presence, USB connected and Claude Code idle for this completed session; reverify live state on resumption.
- **Milestone:** **M6.4 done; M6 startup/allocator DoD met with the limits below. M7.1 next**, not started.
  Active next ticket `tasks/M7.1-display-gpu-abi-audit.md`. M7.1–M7.5 tickets are written; deferred M4.4/M4.3 prerequisites
  remain relevant before display power changes. Session log `log/2026-11-14-M6.4-runtime.md`.
- **Final M6 result:** test 7 Android RUNNING, normal `sys.boot_completed=1`, real graphics allocator guest PID 133
  running and registered over HIDL. Both 64/32-bit ION replays passed as UID 1000/GID 1003, 64 captured allocations and
  boundary/lifetime checks, zero exported buffers afterward. All raw block open modes and mknod denied by the guest
  device policy, with baseline negative control. USB root SSH retained; vendor ro/norecovery; EFS/CPEFS unmounted;
  userdata rw and guard range intact. All seven stock restores and saved fsck checks passed.
- **Runtime fix:** stock TEEGRIS post-fs waits for an unported daemon before HAL startup. A hash-checked, read-only,
  per-boot RC bind defers that action. Vendor contents are unchanged; no TEE readiness or secure storage is fabricated.
  Tools `tools/m64/`; exact tested scripts/manifests and result summary under `reference/m64-runtime/`.
- **Masks:** all four M5 HAL masks are removed. Multi-user reached at 212.21 s; late systemd state degraded with zero jobs.
  Rild/ofono settled; bluebinder still retries, audio-route times out and LightDM fails, without blocking multi-user.
  Hardware Bluetooth/audio/modem/display are not established. Three diagnostic masks remain: repowerd.service,
  a50-enable-autosuspend.service, sleep.target. Their automatic-suspend paths are unvalidated; review before the existing
  M11 zero-mask gate (full power integration remains M12; see docs/08-open-questions.md).
- **Final test inputs:** source `a50-m63-sysmmu-test/bd3fe49b2d2c3b0b04be490b3440d38d806949a3`, unchanged during M6.4.
  BOOT `src/m64/runtime7/boot.img`, SHA `28fb0f6bdf887ea59d2d431465d5be8c721a7c3cf2274fa4a07ae1e92ad9c680`.
  Config/Image/cpio frozen under `src/m64/runtime7/as-built/`; workspace `out/m64-runtime2` was reused after archiving.
  DT `src/m63/dt-sysmmu.img`, SHA `8072be7a4f3f7e588b5c547599784d2d88499c46acbbcfdd2463c1d279baf36d`.
  Manifest `reference/m64-runtime/runtime7-inputs.json`. All overrides live in /run; timed diagnostic window 420 seconds.
- **Remaining limits:** six reserved/secure heaps and TEE/security HALs unsupported; legacy Android cgroup profiles still
  emit setup warnings despite native v2. Scheduling/QoS, real IOMMU translation/DMA, GPU and display remain unvalidated.
  Do not infer their success from the allocator process or CPU ION replay.
- **Git handoff:** this publication checkpoint includes M6.2 wakelock, M6.3, M6.4 and the next M7 tickets
  (outer starting HEAD `a829080`). Kernel checkout remains clean on `a50-usb/4fbb731f5`; production branches unchanged.
- **Build from a clone:** `python3 -I tools/reproduce_m6.py --jobs 16`; instructions in `reproduce/m6/README.md`.
  Complete diagnostic source/config exported separately from clean `patches/`. Pinned public donor/toolchains replace
  private workspace dependencies. Fresh isolated build passed, reproducing the tested source tree, cpio and raw DTB;
  Image/BOOT hashes depend on the embedded config's absolute initramfs path. Publication evidence:
  `log/2026-11-14-publish-m6.md`, `reference/m6-reproduce/`. No phone operations during publication.
- **M6.3 source history:** `log/2026-11-12-M6.3-ion-design.md` maps all seven baseline heaps. A live allocator payload capture
  found 32 successful heap-0 allocations. Source `a50-m63-ion-test/33c851162` adds a native DMA-heap-backed ION frontend
  for that measured subset. Native and AArch32 replay/boundary/lifetime tests passed over USB. All four boots restored stock
  and passed post-flight/fsck. The final native SysMMU provider bound and reported version 7.2. No DMA master is attached.
  Test log `log/2026-11-12-M6.3-ion-tests.md`, evidence `reference/m63-ion/`; included in this publication checkpoint.
- **M6.3 SysMMU history:** `log/2026-11-12-M6.3-sysmmu.md`. Config control with the old DT and provider candidate with the new DT
  passed; both used source `a50-m63-sysmmu-test/bd3fe49b2`, config `src/ack-6.18/out/m63-sysmmu/.config`.
  BOOT `src/m63/boot-sysmmu.img`, SHA `de28abe867bf95c65e89fc3fd5a7369ed64f899f31cf1d5a466af9fa12c92d90`;
  provider DT `src/m63/dt-sysmmu.img`, SHA `8072be7a4f3f7e588b5c547599784d2d88499c46acbbcfdd2463c1d279baf36d`.
  Full inputs in `reference/m63-sysmmu/inputs.json`. Seven replay-helper runs across four boots passed 224 captured allocations,
  with zero exported buffers afterward; same four expected failed units, guard intact and userdata rw throughout.
- **M6.3 limits:** only heap 0 is implemented and advertised. The six reserved/secure heaps remain unsupported. M6.4 verified
  the real service running/registered and the measured heap-0 replay in the guest. DPU provider probing is verified;
  IOVA/page tables, real DMA, other controllers, secure access and suspend/resume remain untested for consumer milestones.
- **Wakelock boot log:** `log/2026-11-12-M6.2-wakelock.md`. Control and PM candidate passed. The native wakelock interface
  passed acquire, release and timeout. Binder's Halium device paths, ashmem and sync also passed. All eight CPUs were online.
  Guard and userdata stayed healthy, and stock restore plus saved baseline fsck passed after both boots.
  Same kernel source `a50-m62-ashmem-test/078d5dbf1`. Final config `src/ack-6.18/out/m62-wakelock/.config`.
  Image `src/m62/boot-wakelock.img` SHA `2aa56e2dc70986d4c28b5c28f4047b1697dac9a5482362fe959ff3266cc94794`.
  Inputs/config deltas/evidence are in `reference/m62-wakelock/`. Recorded outer base `a829080`; results/tools checkpointed.
- **Diagnostic power setup:** both wakelock builds add runtime masks for `repowerd.service`, `a50-enable-autosuspend.service`
  and `sleep.target` to the existing M6.2 test masks. Kernel autosleep and hibernation are disabled. M6.4 reviewed and retained
  these three masks; reassess before M11's zero-mask gate. Suspend integration remains M12.
- **Sync boot log:** `log/2026-11-11-M6.2-sync.md`. Two software fences merged and became ready only after both signaled.
  Binder and ashmem passed again over USB root SSH. The guard passed, userdata stayed rw and baseline restore/fsck passed.
  Same kernel source as ashmem. Image `src/m62/boot-sync.img` SHA `4c77d2dc31979bf31d95f130af04589ccbc1426f9c033254ccc45c88cb9f6583`.
  Inputs, config delta and live evidence are in `reference/m62-sync/`.
- **Ashmem boot log:** `log/2026-11-11-M6.2-ashmem.md`. Native `/dev/ashmem` passed the AArch64 size ioctl and shared mmap
  test, and all three Binder contexts still returned protocol 8 over USB root SSH. Guard passed, userdata stayed rw, and
  post-flight and saved baseline fsck passed. Test source `a50-m62-ashmem-test/078d5dbf1` includes two ACK Rust config fixes.
  Image `src/m62/boot-ashmem.img` SHA `287f3ca0c02078a8891f9d24f462878ba1196105c7438d05873d867f1fe3b20a`.
  Exact config delta, input hashes, patches and live evidence are in `reference/m62-ashmem/`.
- **BinderFS boot log:** `log/2026-11-11-M6.2-binderfs.md`. Both boots reached USB root SSH on 6.18 with Android `STOPPED`
  and userdata rw. Control mount failed as expected. Candidate exposed all three contexts with `BINDER_VERSION=8` using
  a temporary executable tmpfs because `/run` is noexec. Both dumps show one UNMAP refusal and the same seven failed units.
  Stock restore, pre-flight and saved baseline fsck passed after both boots.
- **M6.2 artifacts:** BinderFS control and candidate built from `a50-m62-binder-test/e8a5a7fea`.
  The two-line tracepoint export guard fixes the Binder candidate build with PM sleep disabled. Guard/sense tests passed.
  Both images use the same partition-unit mask, M5.4 initramfs and build version. Full inputs in `reference/m62-binderfs/inputs.json`.
  Control `src/m62/boot-binder-control.img` SHA `bd23da74daedcadf12fbb351175870708c55fadf166a0e6bba3be9ab1e7c913f`.
  Candidate `src/m62/boot-binder.img` SHA `800d2b36756127f4c979030977ed506c85d3ae3a27e69a24bd6158a32503749b`.
  Outer test preparation started from `0ebaf48`. The checkpoint includes the M6.1 audit and M6.2 evidence through sync.
- **M6.1 audit:** `log/2026-11-11-M6.1-android-runtime-abi-audit.md`. Host audit of the tested config, archived Android 11
  rootfs and vendor traces. EFS write denial confirmed. Missing BinderFS likely accounts for the Android mount-unit exit;
  exact exit command still unverified. Legacy cgroup profiles are present and runtime compatibility is pending M6.4.
  Outer audit base `0ebaf48`. No M6 code, build or phone operations during M6.1.
- **M5.4 boot log:** `log/2026-11-10-M5.4-usb-ssh.md`. M5.4 root SSH verified twice over USB on 6.18.33-a50-diag+, with trusted
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
- **Next action:** M7.1 saved-evidence display/GPU ABI audit and implementation design. Start from the final M6 source,
  config and runtime setup above. Preserve USB/storage and the unmasked M5 HAL units; identify real power/I2C prerequisites
  before hardware enablement. Record new heap or DMA requirements when observed.

## State of the phone (verified after M6.4 test 7, 2026-11-14)
Baseline BOOT `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5`, stock DTB/DTBO verified by post-flight.
Home IP **192.168.0.171**, root SSH verified, kernel 4.14.194, baseline boot time 2026-11-14 02:57:58,
battery 100% Charging. Restore completed 02:57:44. Saved baseline init fsck clean: 6321/3440640 files,
1995384/13745152 blocks, no repairs. Evidence `reference/m64-runtime/runtime7-run.txt` and `runtime7-baseline-fsck.txt`.
No test active. M6.4 overrides/masks were runtime-only. Recheck the actual phone before future operations.
Userdata retains the M5.2 scratch file. Read-only backup (2026-11-10 before writes):
`../a50-ubuntu-img-backup/ubuntu.img-2026-11-10`, sha256
`22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896`; rechecked 2026-11-14. Restore: docs/02-baseline.md.

## Kernel tree `src/ack-6.18/common` (not pushed; patches are exported to `reference/m*/`)
Checkout: `a50-usb` (clean). Check it before any build: builds check out a test branch and return to `a50-usb`.
- Portable final M6 diagnostic snapshot: `reproduce/m6/`; exact base-to-test tree export, config, toolchain/input locks.
  Its independent build workspace does not switch this shared checkout. This is separate from the clean driver export.
- Clean driver stack: `a50-dt -> a50-clk -> a50-pinctrl -> a50-ufs -> a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> a50-core`
  (`364673845`, M4 done) `-> a50-userdata` (`c7bde3fe3`, write allow-list + corrected denial sense split).
- `patches/` is the public export of the clean stack (base `d9a614fed`, 35 patches, ends at `a50-userdata`). After any
  change to a clean branch, run `tools/export_patches.sh` (it checks the series reproduces the branch) and commit `patches/`.
- `a50-diag` (`88040ffc9`, v8: DSS readout, panic dump, sync before the timed dump): diagnostics, do not merge into clean branches.
- `a50-bus` (on `a50-pmic`): I2C/PWM/keys DT. **Do not boot with its I2C nodes enabled: it freezes the phone.**
- Test branches, do not merge: `a50-m36-*`, `a50-m37-test`, `a50-m42-test` to `a50-m46-test*`, `a50-m48-test`, `a50-m52-test` (m48 + userdata),
  `a50-m53-test` (m52 + diag v8); a50-m53-3/4 historical broad sense; a50-m53-split/5 and a50-m54-test `f0618ab59` corrected split.
- `a50-m62-binder-test` (`e8a5a7fea`) extends M5.4 with the PM tracepoint export guard. Patch under `reference/m62-binderfs/`.
- `a50-m62-ashmem-test` (`078d5dbf1`) extends the Binder test branch with Rust KABI-field and DMA-BUF config guards.
  Patches under `reference/m62-ashmem/`.
- `a50-m63-ion-test` (`33c851162603f15d9d01baa4b7fba27cf19b7126`) extends that source with the native DMA-heap-backed
  legacy ION frontend and Samsung tracking hints. Native/compat builds use `out/m63-ion` and `out/m63-ion-compat`.
- `a50-m63-sysmmu-test` (`bd3fe49b2d2c3b0b04be490b3440d38d806949a3`) adds the isolated DPU provider DTS.
  Final test config/image under `src/ack-6.18/out/m63-sysmmu`; BOOT `src/m63/boot-sysmmu.img`, DT `src/m63/dt-sysmmu.img`.
  Both M6.3 source changes are actual commits; patches and full input manifests are under `reference/m63-ion/` and
  `reference/m63-sysmmu/`. Clean production branches are unchanged; do not merge diagnostic test branches into them.

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
- **M6.1** Android runtime and ABI audit complete with BinderFS first-test plan.
- **M6.2** Native BinderFS, Rust ashmem, sync fences and userspace wakelocks verified with diagnostic power-service masks.
- **M6.3** Measured heap-0 legacy ION ABI on native DMA heaps, native/compat replay and lifetime checks; native DPU SysMMU
  v7.2 provider probe. Other six heaps and actual device DMA remain explicit limits; runtime validated in M6.4.

- **M6.4 / M6** Normal Android boot property 1, real allocator/HIDL registration and guest 64/32-bit ION replay verified.
  Protected storage and USB retained; all four M5 HAL masks removed; runtime TEEGRIS deferral and three PM masks explicit.
  Final stock restore/fsck clean. M7 tickets written; M7.1 next.

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

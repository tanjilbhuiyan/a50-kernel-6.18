# 2026-11-10 Codex / Claude Code onboarding

Scope: understand the existing project and establish shared handoff guidance.
No kernel changes, builds, phone access, or flashing.

## Project understanding

- Goal: Ubuntu Touch 26.04 / Halium 11 on SM-A505F with ACK android17-6.18,
  preserving the stock Android 11 vendor partition and its kernel ABI
  (`docs/00-goal.md`, ADR-0001/0002, `reference/contract/`).
- Latest completed integration: M4, clean branch `a50-core`. M3 storage/USB
  and all eight CPUs work; PMIC/regulators, thermal and power-domain reporting
  are read-only. Real I2C remains blocked and cpufreq deferred
  (`log/2026-11-10-M4.8-integration.md`, `docs/08-open-questions.md`).
- M5.2 proved writes restricted to userdata, with an ubuntu.img backup and
  guard self-tests. Preserve A50_UFS_SAFE; do not widen its allow-list
  (`log/2026-11-10-M5.2-userdata-writes.md`, `tools/m52/userdata.flags`).
- M5.3 test 1 ran Halium's embedded /init, then failed in udev because UNIX
  sockets were disabled. UNIX/PACKET are added to the flags but untested.
  Next: systemd requirements review before test 2
  (`tasks/M5.3-halium-init-systemd.md`, its test log, outer commit `0f15029`).
- Working readout is DSS dump/reboot/rollback, plus USB telnet where available.
  The boot.img ramdisk does not reach 6.18, so its Halium contents are embedded
  in the Image. Framebuffer writes did not display on the command-mode panel
  (`STATUS.md` resume section, M2.4 and M3.7 logs).

## Host observations

Commands: `git status --short`, `git log`, and independently
`git -C src/ack-6.18/common status --short --branch`, `branch -avv`,
`worktree list`, and branch diff against `aosp/android17-6.18`.

- Outer repository initially clean at `0f15029`.
- Kernel checkout clean on `a50-usb` at `4fbb731f5`; no checkout performed.
- Other relevant branch tips: `a50-core` = `364673845`, `a50-userdata` =
  `44c3fffab`, `a50-m53-test` = `fb341b651`, `a50-diag` = `88040ffc9`.
- `src/` is ignored by the outer repo (`.gitignore`). Kernel changes need
  independent Git inspection; evidence patches are also stored in `reference/`.
- `tools/m22_build.sh` uses pinned ACK clang, a fixed build identity, embedded
  initramfs/config inputs, and refuses UFS without the guard. It wipes its
  output argument: inspect paths before using it.
- `tools/m22_pack.sh` copies the baseline boot header and checks the BOOT size.
  `tools/m32_run_test.sh` flashes test DTB/DTBO/BOOT and restores the stock
  set; it is a phone operation, not a host-only inspection command.
- `sha256sum baseline/ut-26.04-2026-10-19-aa17rf2/boot.img` matches the full
  expected hash `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5`.

## Documentation changes

Added `AGENTS.md` pointing Codex to the existing shared `CLAUDE.md` rules and
handoff files. Added a current handoff note to `STATUS.md` and corrected the
M5.3 task index to match its in-progress ticket and logged first test.

Older documentation still contains superseded details: `STATUS.md` has early
M2 pending-test summaries and answered M1 questions; `docs/03-kernel-contract.md`
still has the old checker-zero-errors target and debug-region proposals;
`docs/06-workflow.md` has older flashing/logging guidance. Consult the latest
plan amendments and task evidence before acting on these. No broad rewrite
was attempted during orientation.

Phone status is not reverified this session. Last recorded: baseline restored
and pre-flight passed after M5.3 test 1. Resume that ticket when requested.

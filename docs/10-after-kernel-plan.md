# 10 — Plan after the kernel: our own Ubuntu Touch build on 6.18

Recorded 2026-11-19 (owner decision): we build our **own** Ubuntu Touch image
for the A50 with our 6.18 kernel. We do not depend on the upstream author
(`sadatdaniel`); our forks `tanjilbhuiyan/a50-ubuntu-touch` and
`tanjilbhuiyan/a50-halium` are the base. The official UBports route stays a
later option (P6), not a dependency.

Blocker IDs (UB*, UD*, UI*, UP*) refer to `09-ut-blockers.md`.

Rules from `CLAUDE.md` apply unchanged: evidence over assumption, one variable
per boot test, the known-good fallback before every flash, never touch
EFS/vendor, every flash with the owner present.

## When each phase may start

| Phase | Start condition | Session |
|---|---|---|
| P0 | **now**, host-only; never touches the kernel checkout or the phone | UT-image session |
| P1 | kernel "Project done" (`05-plan.md`), or earlier for a test image once M7 + M5 hold | either; one tool on the phone at a time |
| P2–P5 | after P1 DoD | — |
| P6 | after P5 DoD and an owner decision | — |

## P0 — Make the fork self-contained (now, host-only)

1. Fix UD1 in the fork: restore the four `.wants/` symlinks (mode 120000) and
   make `build-device-tarball.sh` fail when `scripts/experiments/test-startup-links.py` fails.
2. Mirror UI1 (release `inputs-20261017`, all assets + SHA256SUMS) and UI2
   (`boot-aa17rf2.img` `7d5855ef…`) to releases in our forks; repoint
   `fetch-release-inputs.sh`. Fork `android_kernel_samsung_exynos9610_mint` (UI3) as a frozen 4.14 reference.
3. Add an `upstream` remote (read-only) to track the author's future commits; we merge selectively.
4. Rebuild the **current** baseline image from the fork alone and compare
   against `baseline/…/ubuntu.img` contents (package list, overlay files).

DoD: a clean clone of our fork builds a bootable 4.14 image with no URL
pointing at `sadatdaniel`; UD1 fixed in the build; the rebuilt image installs
and passes the M0.2 checklist items that passed on 2026-11-02.

## P1 — Integrate the 6.18 kernel into our build

1. Package the final 6.18 artefacts: `boot.img` (header v1, ≤ 57,671,680 B),
   `dt.img`, `dtbo.img` (M2.3 format), and any modules/firmware the kernel needs.
2. Extend the fork's install path: `build-device-tarball.sh --boot` plus DTB/DTBO,
   and the flashing procedure for BOOT + DTB + DTBO (today only through the test
   runner, `CLAUDE.md` rule 3; a release needs a user-facing installer step).
3. Point `deviceinfo` at our 6.18 kernel source (UI3) and record the exact commits.
4. First image: **baseline userspace (same rootfs, same cohort) + 6.18 kernel**.
   One variable: the kernel.

DoD: our build produces one flashable 6.18 image; it boots to Lomiri; the
kernel project's S1–S10 checklist results are reproduced on it.

## P2 — Drop the 4.14 workarounds (one per test)

Each item is removed alone, tested, logged:
`tar +a50openat2` (UB2), polkit legacy helper (UB2), the ubuntu:22.04-only build
container (UP3), the Halium BPF fallback if present, the `/run/usb-moded` `-f`
override if M12 fixed USB detection (UD7).

DoD: none of the 4.14-only workarounds remain; checklist unchanged or better.

## P3 — Rebase on a current 26.04 daily rootfs

1. Pick a daily rootfs, record its URL + sha256 (UP1).
2. Re-validate every remaining cohort package against it (UP2): drop those
   already upstream (content-hub), re-test qtmir/settings/lomiri; rebuild the
   rest against current sources.
3. Build, clean install (Format Data), full checklist.

DoD: image on a pinned current daily; cohort reduced to what is still needed,
each with a recorded reason and an upstream route.

## P4 — Device gaps

In this order unless evidence changes it: UD2 mic + call voice → UD3 GPS fix
(open sky) → UD6 suspend failures → UD8 untested items (HFP, headset, earpiece,
VoLTE, factory reset, VPN, notifications) → UD4 camera (upstream) → UD5
fingerprint (last).

DoD per item: a log with the root cause class and either a fix in our build
or a documented "not supported".

## P5 — Release mechanism (our own)

1. Flashable release (zip/installer) built only from recorded inputs:
   kernel commit, rootfs URL+sha256, GSI build, cohort lock, overlay commit.
2. Update path: decide between reflash-only and an own system-image channel
   (signing keys, hosting). Data-preserving kernel-only updates first (BOOT/DTB/DTBO).
3. Clean install from the release on the phone, checklist from first boot,
   no manual repair scripts.

DoD: a tagged release in our fork that a clean phone installs and that passes
the checklist; restore-to-baseline procedure verified.

## P6 — Options after our release (owner decision each)

- Official UBports community port: UB1 is solved by 6.18 + Google clang;
  needs cohort = 0 (UB2), CI layout, installer config, contact with the porting team.
- Newer Halium (ADR-0003, F1).
- Contribute fixes upstream: the UD1 symlink fix (issue #1), cohort MRs, mic/GPS findings.

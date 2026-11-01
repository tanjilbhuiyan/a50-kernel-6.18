# ADR-0003 — Newer Halium (13/14/16) on the 6.18 kernel

Status: **Proposed — deferred** (2026-11-01). Not part of the project DoD.
Revisit only after M7 DoD (Lomiri on 6.18 with accelerated graphics).

## Context
- UBports CI builds generic arm64 Halium GSIs for 11.0, 12.0, 13.0, 14.0 and
  **16.0** (no 15.0). Latest builds on 2026-11-01: halium-11.0 #1591
  (2026-10-24), 12.0 #1330, 13.0 #1095, 14.0 #585, 16.0 #120 (job started
  2026-07-14). Source: `ci.ubports.com` job `generic_arm64/halium-<v>`.
- A UBports forum post (June 2026, forums.ubports.com/post/94549) still named
  Android 14 as the highest supported Halium; 16.0 is likely experimental.
- The A50 baseline uses Halium 11 (GSI 1585) because the stock vendor is
  Android 11 (VNDK 30). See ADR-0002.
- Evidence that a newer Android system can run on the A50's Android 11 vendor:
  Evolution X 11.11 (Android 16 GSI) booted and worked on 2026-10-31, but
  needed the "legacy-kernel BPF fallback" because kernel 4.14 lacks features
  newer Android expects.

## Proposal
Once the 6.18 kernel runs Halium 11 to M7 DoD, evaluate a newer Halium GSI
(13 → 14 → 16, in that order) on the same 6.18 kernel with the **unchanged
stock Android 11 vendor**.

## Expected benefit
- Newer Android hardware layer and GSI fixes inside the Halium container.
- The 6.18 kernel removes the kernel-feature blocker seen with 4.14.

## Open questions (must be answered by evidence before acceptance)
1. Does the UBports 26.04 rootfs + port overlay support Halium > 11 for this
   device (container config, lxc-android-config, hybris)?
2. VNDK 30 vendor with a newer system: which HALs break (graphics composer,
   audio, RIL)? Evolution X proves basic function, not the Halium path.
3. Does the A50 port's package cohort (Waydroid, Lomiri fixes) depend on Halium 11?
4. Is halium-16.0 stable enough (build count, known issues, devices using it)?

## Evaluation method (when started)
- One variable: swap only `/var/lib/lxc/android/android-rootfs.img`
  (the port has `scripts/experiments/swap-gsi-image.sh` for this) on a copy
  of the baseline `ubuntu.img`, kernel fixed at the M7 6.18 build.
- Measure S2–S9 checklist vs. Halium 11 on the same kernel.

## Decision rule
Accept only if the newer Halium is equal or better on every S2–S9 item.
Otherwise stay on Halium 11 and record why.

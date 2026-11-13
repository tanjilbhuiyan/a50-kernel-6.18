# ADR-0004 — Defer the unported TEEGRIS startup with a per-boot read-only RC overlay

Status: **Accepted** (2026-11-14, owner approval after the M6 review)

## Context
On 6.18 the stock vendor init file `/vendor/etc/init/teegris_v3.rc` starts Samsung's TrustZone daemon (`tz_service`) at
post-fs and waits for `vendor.tzdaemon=Ready`. The TEEGRIS/TZDEV kernel driver is not ported. TrustZone/Knox drivers are
non-goals unless a DoD item needs them (`docs/00-goal.md`). The daemon exits repeatedly, the wait never ends, and
Android's normal HAL start is never reached (M6.4 test 6, `log/2026-11-14-M6.4-runtime.md`).
ADR-0002 keeps the vendor partition unchanged.

## Decision
For every 6.18 boot until TEEGRIS is ported or this ADR is replaced, a per-boot LXC mount hook (M6.4 test 7,
`reference/m64-runtime/runtime7-scripts/defer_tee.sh`) does the following:
1. Checks the sha256 of the stock `teegris_v3.rc` and refuses to continue if it is different.
2. Bind-mounts a one-line comment file from `/run` over it, read-only, inside the container's view only.

The vendor partition stays mounted read-only (`ro,noload`), and no vendor file is changed. No TEE, `Ready` property,
identity data or secure storage is faked.

## Consequences
- Android reaches its normal HAL start and `sys.boot_completed=1` (M6.4 test 7).
- Everything that depends on TEEGRIS stays unsupported and must not be described as working: keymaster/gatekeeper and
  other security HALs, DRM, and the secure ION heaps.
- ADR-0002 still holds for vendor files. Any other vendor RC or file overlay needs its own ADR.
- If a later DoD item needs a security HAL, porting TEEGRIS/TZDEV becomes a plan change, and this ADR is superseded.

# ADR-0001 — Base kernel: Google ACK `android17-6.18`

Status: **Accepted** (2026-11-01, owner direction: "latest LTS, preserve interfaces")

## Context
- Latest LTS on kernel.org (2026-11-01): **6.18.60**; mainline 7.3.
- Google ACK branches exist: `android16-6.12`, `android17-6.18` (at 6.18.33),
  `android18-7.3`, `android-mainline`.
- Halium + stock Android 11 vendor need Android-specific kernel features:
  binder/binderfs (also in mainline), **ashmem** (removed from mainline 5.18,
  kept in ACK, now Rust), Android vendor hooks; ION is gone in both.

## Decision
Base the port on **ACK `android17-6.18`**, pinned to a specific commit per
milestone. Use `src/linux-6.18.60` (vanilla) only as reference for
gap analysis and upstream comparison.

## Consequences
- Rust toolchain required (ashmem).
- Some Samsung drivers may use ACK vendor hooks instead of core patches.
- Rebases follow ACK, not kernel.org; upstreaming later means splitting
  Android-only parts out.

## Rejected
- Vanilla 6.18: lacks ashmem and Android pieces → more shims.
- `android16-6.12`: older LTS, shorter remaining life, same porting effort.
- `android18-7.3`: not an LTS base.

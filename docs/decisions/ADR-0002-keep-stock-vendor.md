# ADR-0002 — Keep the stock Android 11 vendor partition unchanged

Status: **Accepted** (2026-11-01)

## Context
Ubuntu Touch on the A50 runs hardware through Halium using the closed stock
vendor binaries (`A505FDDS9CWA2`, VNDK 30). Replacing them would require open
drivers for GPU, display, audio, modem, Wi-Fi — the pure-mainline path.

## Decision
The new kernel must provide the same kernel ABI the stock vendor uses
(`docs/03-kernel-contract.md`). Vendor files are never modified.

## Consequences
- Samsung drivers are forward-ported with their ioctl/sysfs interfaces intact.
- Legacy ION and Mali kbase r26p0 must exist on 6.18.
- A future ADR may move single subsystems to open drivers (e.g. Panfrost for
  Mali-G72, already supported in 6.18) once the Halium path works.

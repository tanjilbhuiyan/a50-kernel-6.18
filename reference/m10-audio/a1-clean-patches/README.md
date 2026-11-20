# Clean ABOX A1 source patches

These seven patches follow the stable `patches/0001`-`0070` M9 series, based
on ACK `d9a614feddce2e8e68767df1d3421305d26a965b`. They reproduce clean
`a50-audio/c371ef348fb2a2c4f8a1131a2ab12afeb32c662e`, tree
`d3cf6e2ee82c5bc0e10c700112f41dff7eed8c70`.

They contain the ABOX import, 6.18 API port, corrected clock units,
DT/memory description, fixed boot clock without DVFS, scratch voice windows
without a modem, and the tested DISPAUD register-bus parent dependency.
Diagnostic panic checkpoints, firmware holds and breadcrumb sleeps are excluded.

Use [the experimental public build](../../../reproduce/m10-a1/README.md):
`python3 -I tools/reproduce_m10_a1.py --jobs 16`. The stable M9 lock remains
unchanged; this experimental profile has a separate config/source lock.

A1l proves normal DSP boot/IPC, not audio playback/capture. M10.2 A2 and
M10.3/M10.4 are still required. See the ticket/session log for limitations.

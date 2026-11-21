# B1 RT5665 source changes (phone-unverified)

These two patches follow the 14-patch M10.2 series in `../a2-clean-patches/`.
Base: clean `a50-audio/e548f4301`; result:
`a0a74861668643df7d5925bf4a161e60ac18ea31`.

They add the mainline RT5665 codec, UAIF0 machine hooks, board widgets and
routing, codec supplies and I2S pinctrl. `replay-check.json` verifies that
applying the exported patches reproduces all three affected source files.

B1/B1r failed in Heimdall transport; codec probing and controls have not been
verified on the phone. No playback was attempted. These patches are outside
the public A1 build profile and its lock. See `../b1r-results.json` and
`../../../log/2026-11-21-M10.3-codec-amplifier.md` for the handoff.

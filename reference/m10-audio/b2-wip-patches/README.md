# B2 TFA9872 candidate (probe tested; playback unverified)

The first five patches follow clean B1 `a0a748616`, producing `2ba9b7efa`.
B2a `95299e7f0` carries those same changes on B1's diagnostic base `a3f5bd537`;
source equality is checked in `replay-check.json`. B2a probes the chip, loads
the container and exposes all four stock TFA control names, with sound disabled.

Patch six produces `bedf87ffc`: it retains the ID already read in probe for
the status attribute (B2a printed an unset field as zero). This fix compiles
but is not in the phone-tested image. Clean `a50-audio` still remains at B1.

Import is verbatim from baseline Halium `4f37ef397`, including its firmware
retry adaptation; not pristine upstream Samsung source. Subsequent patches
port the API/probe-only path, block calibration programming, bound/serialize
ABOX transport, add a CMGP HSI2C variant and wire UAIF2.

`tools/m10/build_b2.py b2a` uses the existing local M9 seed/I5 runtime.
The public reproducible profile remains A1 only; no public B2 validation
build is claimed. B2C measured clocks in `../b2c-results.json`. Temporary
CMGP fixed providers need native integration or explicit disposition.

Owner policy: preserve existing amplifier calibration, stop if invalid;
no EFS or recalibration. Post-restore calibration reading matched stock's
pre-test value privately. No playback/capture or hardware DSP RPC exercised.
See `../b2a-results.json` and the current log/STATUS before the next boot.

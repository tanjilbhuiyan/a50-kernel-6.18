# B2 TFA9872 candidate (probe tested; playback unverified)

The first five patches follow clean B1 `a0a748616`, producing `2ba9b7efa`.
B2a `95299e7f0` carries those same changes on B1's diagnostic base `a3f5bd537`;
source equality is checked in `replay-check.json`. B2a probes the chip, loads
the container and exposes all four stock TFA control names, with sound disabled.

Patch six produces `bedf87ffc`: it retains the ID already read in probe for
the status attribute (B2a printed an unset field as zero). This fix compiles
but is not in the phone-tested image.

Patch seven produces `8af341da3`: the B2h2 RT5665 slot fix (MX-7D = 0x0101
at UAIF0 link init), the same change as clean `a50-audio` `31e5ef26e`
(`../b2h2-clean-patches/`). B2h2 tested it on the B2a image and the owner heard
the earpiece tone; the WIP card file is byte-identical to that test.

Patch eight produces `4b59459bd`: the B2h3 audio divider rounding
(CLK_DIVIDER_ROUND_CLOSEST on AUDIF/UAIF0-2/DSIF), the same change as clean
`cd4991938` (`../b2h3-clean-patches/`). Tested on the B2h2 image in B2h3; the
WIP clock file is byte-identical to that test.

Patch nine produces `f1e420c5b`: the calibration gate (playback only with
MTPOTC/MTPEX set and Re25 4-12 ohm; calibration control read-only; raw/debug
endpoints and per-unit value prints removed). B2b tested it: the gate passed and
the calibration stayed unchanged, but the ABOX firmware crashed on the first TFA
DSP message, so no speaker sound yet (`../b2b-results.json`).

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
pre-test value privately. Earpiece playback verified in B2h2 (RT5665 only); no amplifier playback, capture or hardware DSP RPC exercised.
See `../b2a-results.json` and the current log/STATUS before the next boot.

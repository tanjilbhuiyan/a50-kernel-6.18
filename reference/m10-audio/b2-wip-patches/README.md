# B2 TFA9872 candidate (not phone-validated)

Apply these five patches after clean B1 `a0a748616`; result
`2ba9b7efa` on isolated `a50-m10-b2-wip`. Clean `a50-audio` remains at B1.
Import is verbatim from baseline Halium source `4f37ef397`, including its
firmware retry adaptation, followed by 6.18 API/probe-only conversion,
bounded ABOX external DSP transport, HSI2C CMGP variant and board wiring.

B2a test branch `95299e7f0` applies the same changes on the B1 diagnostic base
`a3f5bd537`. `tools/m10/build_b2.py b2a` uses the existing local M9 seed and
I5 runtime. The full public reproducible profile still covers A1 only;
these exports are not a claim of a validated public B2 reproduction.

B2C measured clocks in `../b2c-results.json`. Temporary CMGP fixed providers
are a prototype; native clock integration/disposition remains open.
Driver defaults to probe-only, with MTP programming blocked. Owner policy:
preserve existing amplifier calibration, stop if invalid; no EFS access.
No speaker playback/capture accepted yet. See the current log and STATUS.

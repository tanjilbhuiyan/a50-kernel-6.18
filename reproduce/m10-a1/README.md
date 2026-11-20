# Build the experimental ABOX DSP core (M10.2 A1)

This profile adds the seven clean ABOX/clock commits to the stable 70-patch
M9 stack. **It does not provide speaker/microphone audio yet.** The DSP boots
and IPC works; PCM/card registration (A2), codec/amplifier and PulseAudio
integration remain pending. The ADR-0005 audio-HAL deferral stays enabled.

From a new clone, with the [same host prerequisites as the stable build](../m8/README.md):

```sh
python3 -I tools/reproduce_m10_a1.py --jobs 16
```

No private kernel worktree, backup, `ubuntu.img` or phone is needed. This
uses the stable public builder with a separate 77-patch/config/runtime lock.
It verifies the clean tree `d3cf6e2ee82c5bc0e10c700112f41dff7eed8c70`, runs
the storage guard/sense tests and builds Image, raw DTB and BOOT. The I5
runtime and its accepted deferrals are unchanged. It never flashes.

Outputs are under `src/reproduce-m10-a1/`: `out/arch/arm64/boot/Image`,
`out/arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb`, `boot.img`, and
`build-results.json`. `--work`, `--cache`, `--assets` and `--prepare-only`
have the same meanings as in the stable builder.

The new source patches are in [a1-clean-patches](../../reference/m10-audio/a1-clean-patches/).
The important boot fix is DISPAUD's register-bus parent clock: a temporary
DPU SysMMU clock reference could be released before the ABOX SysMMU probe,
leaving later register accesses without their bus clock. The standard CMU
`.clk_name` helper now holds that parent; no frequency/DVFS change or delay.

Phone evidence is [A1k and normal boot A1l](../../log/2026-11-20-M10.2-abox-core.md).
The exact clean Image from this profile has not been flashed: the phone
tests include diagnostic log/reset code. Audio faults, GIC supplier-readiness
robustness and the intermittent USB link still have recorded follow-ups.
The full public build passed, including the 77-patch replay, 103 input hashes,
config resolution and guard/sense checks. Raw DTB and I5 cpio match the A1l
test; see [publication-a1-validation.json](../../reference/m10-audio/publication-a1-validation.json).

A raw DTB is not a partition image. Any device test still requires the
owner, compatible Ubuntu Touch/vendor contents and verified stock rollback
templates; follow [the project workflow](../../docs/06-workflow.md).

# B2h2 RT5665 slot fix

This patch follows the two B1 patches in `../b1-clean-patches/`.
Base: clean `a50-audio/a0a748616`; result:
`31e5ef26e117cc7e8e816edf69429f4c61b12e1d`.

The UAIF0 link init writes RT5665 MX-7D (TDM_CTRL_6) = 0x0101, as Samsung's
4.14 init list does, so IF1 DAC2 (the stock handset path) takes I2S slots
0/1. Mainline keeps the chip default 0x0123 (slots 2/3), which two-channel
UAIF0 leaves empty, so B2h was silent. B2h2 (owner present, 2026-11-22) heard
the earpiece tone with this patch. `replay-check.json` confirms that applying
the patch reproduces the affected file. See `../b2h2-results.json` and
`../../../log/2026-11-22-M10.3-tfa9872.md`.

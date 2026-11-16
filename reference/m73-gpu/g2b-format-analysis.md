# Observed display format and stock translation

G2b reports 1,800 single-buffer WIN_CONFIG updates, all sampled worker
formats 2. Both the DMA eligibility check and CPU bridge reject this format;
the final counters are 1,800 skipped, zero copied and zero scanned. No
rendered pixels are established by this test.

Primary source: local stock kernel `src/samsung-a50-4.14-aa17rf2`, commit
`4f37ef3970e95faa8713191b3aac32b432277e82`:

| Source | Finding |
|---|---|
| `drivers/video/fbdev/exynos/dpu20/cal_9610/decon_cal.h`, enum at line 147 | ABI format 2 is `DECON_PIXEL_FORMAT_RGBA_8888` |
| `drivers/video/fbdev/exynos/dpu20/decon_core.c:2574` | The stock display path translates the submitted format before DPP programming |
| `drivers/video/fbdev/exynos/dpu20/helper.c:82`, `dpu_translate_fmt_to_dpp()` | Submitted RGBA_8888 maps to ABGR_8888 (value 1) |
| `drivers/video/fbdev/exynos/dpu20/cal_9610/dpp_reg.c:748` onward | DPP enums select the corresponding IDMA image format |
| `drivers/video/fbdev/exynos/dpu20/cal_9610/regs-dpp.h:139` onward | IDMA encodings: ARGB=0, ABGR=1, RGBA=2, BGRA=3, XRGB=4, XBGR=5, RGBX=6, BGRX=7 |

The 6.18 handover driver currently admits only 0/1/4/5 and writes the
admitted value directly into the IDMA format field. Simply admitting 2
without reviewing the stock translation would risk incorrect byte/channel
ordering. A follow-up needs known-color checks and correct ABI-to-DMA/CPU
mapping. Also verify geometry/stride: rejection on format happens before
the existing CPU geometry checks, so this run does not prove the submitted
buffers meet the current direct-scanout geometry restrictions.

This is an evidenced presentation blocker. It rules out slow pixel copying
as the explanation for this run: no CPU pixel copies occurred. It does not
establish GPU render correctness or resolve the separate userspace
`test_egl` segmentation fault.

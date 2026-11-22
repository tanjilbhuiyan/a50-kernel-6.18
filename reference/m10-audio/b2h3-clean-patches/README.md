# B2h3 audio interface divider rounding

This patch follows `../b2h2-clean-patches/`. Base: clean `a50-audio/31e5ef26e`;
result: `cd4991938e880d5220fb6beec044d5acb6eb6ef5`.

It sets CLK_DIVIDER_ROUND_CLOSEST on the Exynos9610 AUDIF divider and its
interface children (UAIF0-2, DSIF). The AUD PLL runs 40 Hz above nominal, so
the default divider rounding dropped one step: AUDIF 69391062 Hz (/17) and UAIF0
BCLK 1508502 Hz (/46), 1.8% slow. With the patch the dividers are /16 and /48,
the same as the stock 4.14 kernel (which reports 73728002/1536000 Hz; 6.18
reports 73728003/1536001 because its recalc rounds up). B2h3 (owner present,
2026-11-22) heard the earpiece tone. `replay-check.json` confirms that applying
the patch reproduces the affected file. See `../b2h3-results.json`.

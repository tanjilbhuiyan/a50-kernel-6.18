# M10.2 clean ABOX patches (A2)

14 patches on top of the M9 clean branch `a50-wlbt` e7a5bee84 (stable 70-patch export in `patches/`). `git am` replays
them to clean `a50-audio` e548f4301, tree **ca8b6631f4bc21df0797cda9de1f3319ad16366f**.

- 0001-0007: A1 (ABOX core, see `../a1-clean-patches/`), unchanged.
- 0008: UAIF/DSIF clock role from the CPU side (6.18 flips it for the CPU DAI).
- 0009: PCM buffers by physical address, mapped per stream.
- 0010: Galaxy A50 ABOX sound card (stock link layout, dummy codecs).
- 0011: DT: ABOX DMA/interface/effect children and the sound node.
- 0012: the ABOX component no longer frees the ABOX regmap.
- 0013: IOMMU fault worker only touches a powered ABOX.
- 0014: require a bound ABOX GIC before probing.

Kernel config on top of the M9 config: `SOUND`, `SND`, `SND_SOC`, `SND_SOC_SAMSUNG`, `SND_SOC_SAMSUNG_ABOX`,
`SND_SOC_SAMSUNG_EXYNOS9610_A50`, `SND_DYNAMIC_MINORS` (see `tools/m10/build_a2c.py`). Phone-tested as A2c
(`../a2c-results.json`) on the test branch, whose sound/DT/clock sources are identical to this tree. The public
reproducible build (`reproduce/m10-a1/`) still covers A1; refreshing it to A2 is pending.

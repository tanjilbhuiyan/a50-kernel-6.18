# 2026-11-01 setup — project context created

Variable changed: none on the phone (analysis only).

Inputs
- Phone: baseline (`docs/02-baseline.md`), live DT dumped over SSH.
- Trees: `src/samsung-a50-4.14-aa17rf2` (`4f37ef39`), `src/linux-4.14.194`, `src/linux-6.18.60`.
- Stock vendor extracts from `A505FDDS9CWA2` vendor.img → `reference/stock-vendor/`.
- Stock `dt.img` `59209aa5…`, `dtbo.img` `40e47ed1…` → `reference/stock-images/`.

Findings
- Samsung delta vs 4.14.194: 8,761 files, +3.16 M / −58 k lines; 123 k lines
  inside modified upstream files (core changes).
- Live DT: 318 nodes, 271 enabled → A 40, B 18, C 150 (90 driver files), D 63.
- ACK branches: android16-6.12, **android17-6.18 (6.18.33)**, android18-7.3.
- ACK 6.18: binder ✅, ashmem ✅ (Rust), ION ❌ (dma-buf heaps only).
- Mainline (master): exynos9610 pinctrl + chipid merged; clocks/DT not yet.
- Panfrost in 6.18 lists Mali G72 (`GPU_MODEL(g72, 0x6001)`).
- pstore region: `log_pstore` 0xf9d10000 / 0x200000; simplefb candidate 0xca000000.
- Boot image: header v1, kernel 42.8 MB + ramdisk 10.8 MB of 57.67 MB BOOT.

Result: context complete; plan starts at M0.
Next: M0 task 1 (root SSH key).

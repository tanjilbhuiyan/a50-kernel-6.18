# A50 kernel patch series

The Galaxy A50 changes as one ordered series on top of the Android Common Kernel.

For the **latest phone-tested M6 diagnostic build**, use
[reproduce/m6/](../reproduce/m6/README.md). It includes the complete test source,
final config, pinned toolchains and public ramdisk bootstrap. This directory
continues to hold the separate clean driver series.

- **Base:** https://android.googlesource.com/kernel/common, branch `android17-6.18`,
  commit `d9a614feddce2e8e68767df1d3421305d26a965b` (2026-10-31, Linux 6.18.33).
- **Series:** `0001` to `0048`. It is the project's clean driver stack:
  - `0001`-`0035` (M2-M5): device tree and defconfig, Exynos 9610 clocks, pinctrl, UFS with the `A50_UFS_SAFE` write
    guard, USB PHY, ACPM, S2MPU09 regulators (read-only), thermal (read-only), and the userdata write allow-list;
  - `0036`-`0040` (M6): tracepoint and Rust build fixes, and the Exynos ION system-heap ABI on native DMA-BUF heaps;
  - `0041`-`0045` (M7): the pinctrl GPIO-interrupt fix, display clocks and DPU SysMMU in the DT, the `a50-decon` fbdev
    driver on the bootloader's display pipeline, and Samsung's Mali r26p0 kbase ported to 6.18 at a fixed GPU clock;
  - `0046`-`0048` (M8): the I2C controllers (buses 0/1/3/4/6) on a fixed PERI clock with CMU_PERI left to the
    bootloader ([ADR-0007](../docs/decisions/ADR-0007-cmu-peri-bootloader-clocks.md)), and I2C in the defconfig.
- **Not included:** diagnostic patches and one-off test patches. They stay with their test evidence under `reference/`.
  The Halium/Ubuntu Touch config flags are in `tools/m51/halium.flags`.

## Apply and build

```sh
git clone https://android.googlesource.com/kernel/common ack-common
cd ack-common
git checkout -b a50 d9a614feddce2e8e68767df1d3421305d26a965b
git am /path/to/this/repo/patches/*.patch
make ARCH=arm64 LLVM=1 O=out a50_firstlight_defconfig
make ARCH=arm64 LLVM=1 O=out -j"$(nproc)" Image
```

The defconfig covers the M2-M5 drivers. The full config of the M7 stack is
[reference/m75-integration/clean.config](../reference/m75-integration/clean.config) (it covers `0001`-`0045`; for
`0046`-`0048` also set `CONFIG_I2C=y`, `CONFIG_I2C_CHARDEV=y` and `CONFIG_I2C_S3C2410=y`, as the defconfig does);
`tools/m75/build_clean.py` builds the series with it and the pinned toolchain and runtime from
[reproduce/m6/](../reproduce/m6/README.md), and checks that the resolved config is unchanged.

The project builds with ACK's clang prebuilt (`clang-r584948c`) through `tools/m22_build.sh`, which also embeds the
initramfs and applies the Halium flags. Packing for S-Boot is `tools/m22_pack.sh`. Read `docs/06-workflow.md` before
flashing anything.

## Regenerating

`tools/export_patches.sh` rewrites this series from the local kernel branch `a50-input` and checks that the series
applied to the base reproduces that branch's tree exactly. Re-run it whenever the clean branch changes.

## License

These patches modify the Linux kernel and are licensed GPL-2.0-only, like the kernel itself
([../LICENSES/GPL-2.0-only.txt](../LICENSES/GPL-2.0-only.txt)). Authorship is kept in each patch: several come from
upstream contributors (Linaro, Alexandru Chimac) and keep their original author lines.

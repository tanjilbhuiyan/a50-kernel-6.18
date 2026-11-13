# Build the tested M6 kernel

This snapshot reconstructs the source and runtime payload used by M6.4 test 7.
It includes BinderFS, ashmem, sync, wakelocks, the measured ION heap-0 ABI,
the isolated DPU SysMMU provider, USB access, and the userdata write guard.
The [test log](../../log/2026-11-14-M6.4-runtime.md) records what actually worked
and the remaining hardware/runtime limits. M7 has not started.

## From a new clone

Use an x86-64 Linux host with several GB of download space and at least 30 GB
free for source, pinned tools and build output. On Ubuntu/Debian, install:

```sh
sudo apt-get install build-essential git curl python3 patch cpio zstd \
    libssl-dev libelf-dev zlib1g-dev flex bison rsync
git clone https://github.com/tanjilbhuiyan/a50-kernel-6.18.git
cd a50-kernel-6.18
python3 -I tools/reproduce_m6.py --jobs 16
```

The script downloads pinned public ACK/toolchain revisions, the public Halium
boot donor and an arm64 BusyBox package. It verifies SHA-256 for downloads and
tracked inputs, applies the complete kernel patch, and checks that the resulting
Git tree exactly matches the tested source. No local kernel branch, private
backup, `ubuntu.img`, NDK or pre-existing `src/` files are needed to compile.
Public downloads retain their upstream licenses; they are not redistributed here.

All generated files stay under ignored `src/reproduce-m6/`. `--work PATH`
selects another workspace; paths must not contain whitespace. `--prepare-only`
fetches and validates inputs without compiling. Re-running uses the pinned
checkouts and rebuilds without deleting the workspace. Modified pinned
checkouts or config drift stop the build.

For an existing local ACK workspace, optional `--cache src/ack-6.18` reuses
its Git objects at the locked public revisions, and `--assets PATH` can supply
the two hash-verified downloads (`boot-public.img`, `busybox.deb`). These options
are bandwidth optimizations, not additional build inputs.

## Outputs and verification

| Output under `src/reproduce-m6/` | Meaning |
|---|---|
| `out/arch/arm64/boot/Image` | Uncompressed arm64 kernel with embedded Halium/runtime initramfs |
| `out/arch/arm64/boot/dts/exynos/exynos9610-a50-sysmmu.dtb` | Raw device tree for the tested provider setup |
| `boot.img` | Android v1 BOOT image using the public donor's verified header |
| `out/.config` | Resolved build configuration |
| `out/usr/initramfs_data.cpio` | Generated embedded runtime payload |
| `build-results.json` | Output sizes, hashes and reconstructed source tree |

The build runs the real UFS guard and denial-sense host tests, including their
deliberately broken variants. It requires the generated initramfs and raw DTB
hashes to match test 7. The script also checks the generated `/init` against
the tested input before compiling.

`CONFIG_IKCONFIG=y` embeds the config, including its absolute initramfs list
path, in the kernel. Consequently `Image` and BOOT hashes differ across build
paths; the original phone-tested hashes in `sources.lock.json` are provenance,
not an expected match for every clone. The source tree, config except that
path, embedded cpio and raw DTB are checked independently. See the
[publication/build log](../../log/2026-11-14-publish-m6.md) for validation.

The script only builds. A raw DTB is not a flashable DTB/DTBO partition image;
existing partition packing tools require the owner's stock templates. Booting
also requires a compatible Halium/Ubuntu Touch installation, stock vendor,
and a verified rollback. The built-in diagnostic timer dumps/reboots after
420 seconds; three power-service masks and the per-boot TEEGRIS deferral remain
as recorded in the M6.4 log. Read the [workflow](../../docs/06-workflow.md)
before planning a device test.

## Source provenance

- Base: public ACK `d9a614feddce2e8e68767df1d3421305d26a965b` (6.18.33).
- Tested source commit: `bd3fe49b2d2c3b0b04be490b3440d38d806949a3`.
- Reconstructed tree: `711bc53eba04061c8892c77f52c473818ec174e3`.
- `kernel.patch`: complete base-to-test diff, **GPL-2.0-only**. Original
  authors and commit messages are retained in `source-history.txt`.
- `config`: full final configuration; only `CONFIG_INITRAMFS_SOURCE` uses a
  relocation token. No defaults are inferred from the clean defconfig.
- `sources.lock.json`: public URLs/revisions, input hashes and tested hashes.
- Runtime: original donor ramdisk plus the recorded M5.4 and test-7 init
  patches, and the immutable test-7 script snapshots under `reference/`.

This diagnostic snapshot is separate from the [35 clean driver patches](../../patches/README.md).
It does not change production branch history or merge diagnostic code into it.

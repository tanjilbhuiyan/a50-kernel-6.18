# Build the current M8 kernel

This profile builds the clean driver stack through **M8.3**: display/GPU,
real I2C, the Melfas touchscreen, and volume/power GPIO keys. It applies all
56 numbered patches and verifies the resulting Git tree. The embedded
Halium runtime includes the accepted TEEGRIS, audio-HAL and GStreamer codec
deferrals (ADR-0004/0005/0006).

## From a new clone

Use an x86-64 Linux host with at least 30 GB free for source, pinned tools
and output. On Ubuntu/Debian:

```sh
sudo apt-get install build-essential git curl python3 patch cpio zstd \
    libssl-dev libelf-dev zlib1g-dev flex bison rsync
git clone https://github.com/tanjilbhuiyan/a50-kernel-6.18.git
cd a50-kernel-6.18
python3 -I tools/reproduce_m8.py --jobs 16
```

No local kernel branch, private backup, `ubuntu.img`, phone connection or
existing `src/` directory is needed. Public ACK/toolchains, the public Halium
boot donor and arm64 BusyBox are pinned by revision and SHA-256 in
`sources.lock.json`. Downloads retain their upstream licenses.

The build checks tracked inputs, replays the patches to tree
`a92a29f0bfc9e99b91ab8184c8b9a781e7b0d8ad`, reconstructs the runtime, verifies
the resolved config, runs the storage-guard/sense tests, then compiles and
links the kernel. The raw DTB and embedded cpio must match locked hashes.
It never flashes or contacts the phone.

## Outputs

All generated files are under ignored `src/reproduce-m8/` by default:

| Path | Contents |
|---|---|
| `out/arch/arm64/boot/Image` | arm64 kernel with the embedded Halium runtime |
| `out/arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb` | Raw A50 device tree including I2C, touch and keys |
| `out/.config` | Resolved M8 configuration |
| `out/usr/initramfs_data.cpio` | Embedded runtime, including ADR-0005/0006 hooks |
| `boot.img` | Android v1 BOOT image packed using the verified public donor header |
| `build-results.json` | Source tree, output sizes/hashes and validation limits |

`--work PATH` selects another workspace; paths cannot contain whitespace.
`--prepare-only` fetches and verifies inputs without compiling. Re-running
uses the locked checkouts and rebuilds without deleting the workspace;
modified checkouts, unexpected revisions or config drift stop the build.

Optional `--cache /path/to/ack` reuses Git objects for the pinned public
revisions. `--assets /path/to/downloads` reuses verified `boot-public.img`
and `busybox.deb`. They reduce downloads but supply no extra build inputs.

Image/config/BOOT hashes include the absolute initramfs-list path through
the embedded kernel config, so those hashes can differ between directories.
The source tree, normalized config, raw DTB and cpio are checked separately.

The [publication log](../../log/2026-11-19-publish-m8.md) records two full
builds, including an isolated clone with no pre-existing `src/`. Their raw
DTB/cpio and normalized configs match; build results and refusal checks are
under [reference/m83-publication/](../../reference/m83-publication/).

## What this build establishes

This is the **clean source build**, not an exact reconstruction of the timed
phone-test images. It excludes the diagnostic reset code and test-only
touch READY_STATUS probe. The individual drivers were tested on the phone;
this exact clean image has not been flashed. The older exact M6 diagnostic
snapshot remains available under [../m6/](../m6/README.md).

The phone's intermittent USB re-enumeration is unresolved: it reproduced
without keys on two host paths, while later trace runs did not reproduce it.
Power-key events work, but screen blanking is deferred while repowerd is
masked until M12. GPU frequency, touch power behavior, audio, hardware video
codecs, Wi-Fi/modem and other unported hardware retain their recorded limits.

A raw DTB is not a flashable DTB/DTBO partition image. Partition packing
requires the owner's stock templates; booting requires compatible Ubuntu
Touch/vendor contents and verified rollback images. See the
[workflow](../../docs/06-workflow.md) before any device test.

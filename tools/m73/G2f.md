# G2f metadata handler

This diagnostic adds only EXYNOS_DISP_INFO to G2e. The required ABI and
stock vendor early-return path are described in
[the trace](../../reference/m73-gpu/g2f-hwc-mode-trace.md). Boot results and
restore verification belong in
[the test log](../../log/2026-11-17-M7.3-g2f-metadata-boot.md).

## Source and build

Apply `reference/m73-gpu/g2f-display-info.patch` to G2e commit
`dce5cdc6e9d1c3cd64f063d5f29e1344e5724756` (or its exported tree).
Resulting tree must be `7253f8a58c52a3aa9c77b6458bd4ce81c28589b4`.
The local candidate is dirty on `a50-m73-g2f-wip`, in the isolated
`src/m73/g2b-kernel` worktree; the shared checkout remains on a50-usb.

```sh
python3 -I tools/m73/metadata_unittest.py src/m73/g2b-kernel
python3 -I tools/m73/build_metadata_probes.py src/m73/g2b-kernel src/m73/g2f-session
bash tools/m73/build_g2f.sh /absolute/path/to/fresh/output
```

The actual office build used a separate output seeded by copying G2e's
objects, then `build_g2f.sh --resume src/ack-6.18/out/m73-g2f`. The locked
config is verified on resume. Affected source is compiled and the full
Image linked. No compiler-error override is used. Config, raw DTB and
runtime cpio must match G2e exactly. All final artifacts are frozen in
`src/m73/g2f-as-built/`.

Package the resulting Image with `tools/m22_pack.sh`. Tested inputs are
recorded in `reference/m73-gpu/g2f-boot-inputs.json`; the as-prepared BOOT
is `src/m73/boot-g2f.img`, SHA256
`0c60496fdb454f4a84a472d9245184d5bcdc390f8818eac51fa5eddd2f429b2a`.
The DT partition remains `src/m73/dt-g1.img`.

## Validation and boot procedure

The host test extracts the actual ABI, metadata helper and full ioctl
dispatcher. It checks layout, metadata, caller preservation, canaries,
copy failures and unsupported commands. Four broken variants must fail:
missing handler, reserved bytes lost, copyout failure ignored and pixel
dimensions incorrectly placed into mres fields.

The live native/compat probes use ABI declarations extracted from the same
driver. They check preserved version/reserved bytes, measured panel data,
NULL/partial input, read-only output and optional-mode ENOTTY.
`read_display_info.py` records the metadata/fbdev response too.

With owner present/exclusive phone access confirmed, fresh pre-flight and
input hashes checked, the prepared invocation is:

```sh
bash tools/m73/run_g2f.sh 192.168.181.225
```

The wrapper uses the established DTB/DTBO/BOOT runner and stock restore.
Kernel and display counters stream independently. Helpers live only in
/run tmpfs. Natural Mir/Lomiri snapshots are taken at 100/200/300 seconds;
no competing standalone composer, GLES or EGL clients are launched.
The normal timer dumps and restores, followed by partition verification
and saved baseline fsck. Existing output is never overwritten by a repeat
run; another test needs separate paths/manifests and owner confirmation.
Published text is redacted; raw logs stay ignored.

## Limits to keep explicit

A correct mode does not by itself prove rendered pixels. Record the owner
observation alongside live GL renderer/job/display evidence. A 1088-pixel
source stride is still ineligible for the existing 1080-pitch DMA path,
and therefore uses CPU copying. This test does not add padded DMA support,
fix the separate standalone EGL failure, or complete M7's 10-minute soak.

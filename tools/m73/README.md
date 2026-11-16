# M7.3 G1 host preparation

G1 tests driver initialization and the stock native/compat metadata ABI.
It does not establish GPU memory import, job execution, synchronization,
rendering or accelerated Lomiri. G1b passed the native/compat metadata tests;
see [the test log](../../log/2026-11-17-M7.3-g1-kbase.md).

The complete `reference/m73-gpu/g1-kernel.patch` applies to the exact M6
source tree (`bd3fe49b2d2c3b0b04be490b3440d38d806949a3`). It includes the
M7.2 display work, Samsung's GPL kbase r26p0 import and the current port.
It preserves existing copyright/license headers. The final tree and input
hashes are recorded in `reference/m73-gpu/g1-inputs.json` and `g1b-inputs.json`.
Apply `g1b-irq.patch` after the full patch to include the tested IRQ API fix.

## Reconstruct in a separate workspace

After installing the [M6 build prerequisites](../../reproduce/m6/README.md):

```sh
python3 -I tools/reproduce_m6.py --prepare-only
git -C src/reproduce-m6/ack/common switch -c a50-m73-g1-wip
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g1-kernel.patch"
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g1b-irq.patch"
A50_ACK_WORKSPACE="$PWD/src/reproduce-m6/ack" \
    bash tools/m73/build_g1.sh src/m73/g1-rebuild
```

The current shared WIP checkout already contains these changes: do not reapply there.
The host build defaults to a fresh output directory. `--resume OUTPUT_DIR`
rebuilds incrementally only if its existing config matches the lock exactly.
It does not remove old builds or switch branches. Its full config is `reference/m73-gpu/g1.config`,
with only the initramfs path relocated. Pinned ACK clang/Rust/bindgen and
fixed Kbuild identity match the M6 recipe. The script checks config drift,
runs the real UFS guard/sense tests, and verifies the exact M6 runtime cpio.
It also tests the real ported address search and its regression controls.
Image/BOOT hashes depend on the initramfs path embedded through IKCONFIG;
source tree, cpio and raw DTB can be compared separately.

The local checkout can instead use default `src/ack-6.18`, with optional
`A50_INITRAMFS_LIST` pointing at the preserved test-7 ramdisk list.

## Probe and first boot

`bash tools/m73/build_probe.sh` builds static AArch64 and AArch32 probes
using the local pinned NDK r27. `A50_NDK_BIN` selects another NDK bin
directory if needed. The tool includes the actual port's ioctl header;
size and numeric ioctl assertions compile for both architectures.

The probe negotiates ABI 11.27, creates a context with submission disabled,
reads and parses the packed GPU property buffer, and checks it against G0b:
Mali-G72 r0p1, shader mask 7, L2 mask 1, 8 address spaces, fixed 260 MHz.
Short-buffer, bad-flags and invalid-pointer checks exercise errors.

The built-in `mali_kbase.a50_g1_probe_only=1` diagnostic parameter rejects
all ioctls except VERSION_CHECK, SET_FLAGS and GET_GPUPROPS. This prevents
background vendor clients submitting GPU work during G1. The probes also
verify allocation and job requests are refused. The gate defaults off in
source; removing it is a separate later boot before rendering validation.

First live sequence, only after owner presence and exclusive access:

1. Recheck baseline, backup and all candidate/rollback input hashes.
2. Use the established runner with the G1 DTB/BOOT and unchanged DTBO.
3. While 6.18 runs, verify USB root SSH, driver probe, `/dev/mali0`, the
   diagnostic parameter, expected clock and GPU IRQs; run both helpers
   from an executable temporary tmpfs, as in M6.2/M6.3.
4. Review init/GPU/reset/IRQ/MMU faults and runtime/storage health. Let
   the 420-second diagnostic timer finish; do not key-recover early.
5. Require stock restore/post-flight and save baseline `/run/e2fsck.out`.

The usual warning/logo screen alone does not mean a test is hung.
No rootfs/vendor contents, service masks, storage range, mixer state,
PMIC voltage, PLL/DVFS or protected-mode state is changed by this recipe.

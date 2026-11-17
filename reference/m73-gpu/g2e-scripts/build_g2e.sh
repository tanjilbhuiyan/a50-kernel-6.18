#!/bin/bash
# M7.3 G2e: G2d plus the stock gralloc ION hint flags (0x2, 0x8). Never flashes or changes the kernel branch.
# Usage: tools/m73/build_g2e.sh [--resume] OUTPUT_DIR
# Prepare the public M6 ramdisk first with tools/reproduce_m6.py --prepare-only,
# or set A50_INITRAMFS_LIST to the preserved test-7 initramfs list.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
resume=0
if [ "${1:-}" = --resume ]; then resume=1; shift; fi
out=$(realpath -m "${1:?usage: build_g2e.sh [--resume] OUTPUT_DIR}")
ack=$(realpath "${A50_ACK_WORKSPACE:-$repo/src/ack-6.18}")
kernel=$(realpath "${A50_KERNEL_TREE:-$repo/src/m73/g2b-kernel}")
list=$(realpath "${A50_INITRAMFS_LIST:-$repo/src/reproduce-m6/payload/initramfs.list}")
if [ -e "$out" ] && [ "$resume" = 0 ]; then
    echo "Refusing existing output: $out; choose a fresh directory" >&2
    exit 1
fi
test -f "$list"
test "$(git -C "$kernel" branch --show-current)" = a50-m73-g2e-wip
mkdir -p "$out" "$repo/src/m73/shim"
ln -sf "$ack/prebuilts/build-tools/linux-x86/bin/gavinhoward-bc" "$repo/src/m73/shim/bc"
export PATH=$repo/src/m73/shim:$ack/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ack/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ack/prebuilts/build-tools/linux-x86/bin:$PATH
export LIBCLANG_PATH=$ack/prebuilts/clang/host/linux-x86/clang-r584948c/lib
export KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026'
export KBUILD_BUILD_USER=a50 KBUILD_BUILD_HOST=firstlight KBUILD_BUILD_VERSION=1 SOURCE_DATE_EPOCH=1793750400
unset KCFLAGS KCPPFLAGS KRUSTFLAGS LOCALVERSION KCONFIG_CONFIG KBUILD_OUTPUT
python3 - "$list" "$out/.config" "$resume" <<'PY'
from pathlib import Path
import sys
config=Path(sys.argv[2])
expected=Path('reference/m73-gpu/g2.config').read_text().replace('@INITRAMFS@', sys.argv[1])
if sys.argv[3] == '1':
    assert config.read_text() == expected, 'Existing config differs from the locked G2 config'
else:
    config.write_text(expected)
PY
make_args=(-C "$kernel" -j16 ARCH=arm64 LLVM=1 "O=$out"
    "RUSTC=$ack/prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"
    "BINDGEN=$ack/prebuilts/clang-tools/linux-x86/bin/bindgen")
cp "$out/.config" "$out/.config.expected"
make "${make_args[@]}" olddefconfig
cmp "$out/.config" "$out/.config.expected"
python3 -I tools/m52/guard_unittest.py "$kernel" 0x1c8700 0xee42ff
python3 -I tools/m53/sense_unittest.py "$kernel"
python3 -I tools/m73/mmap_unittest.py "$kernel"
python3 -I tools/m73/cancel_unittest.py "$kernel"
python3 -I tools/m73/format_unittest.py "$kernel"
make "${make_args[@]}" Image exynos/exynos9610-a50-g1.dtb
python3 - "$out" <<'PY'
import hashlib
from pathlib import Path
import sys
p=Path(sys.argv[1])/'usr/initramfs_data.cpio'
assert hashlib.sha256(p.read_bytes()).hexdigest() == 'c855bb6eee66af35fc8ae2f21f2c85407d6cd46b9bf648b80e9a81672dd192a2', 'M6 runtime payload changed'
PY
sha256sum "$out/.config" "$out/arch/arm64/boot/Image" \
    "$out/arch/arm64/boot/dts/exynos/exynos9610-a50-g1.dtb" "$out/usr/initramfs_data.cpio"

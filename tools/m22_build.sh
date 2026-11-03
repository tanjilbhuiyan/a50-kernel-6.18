#!/bin/bash
# M2.2: build the A50 first-light kernel Image reproducibly.
#   tools/m22_build.sh OUT_DIR        (OUT_DIR is wiped; use the SAME path for the reproducibility check)
# Needs: src/ack-6.18 (repo sync, branch a50-dt with a50_firstlight_defconfig), the ACK clang prebuilt,
#        src/m22/busybox (static arm64 busybox-static 1.37.0-7ubuntu1, sha256 in the M2.2 log).
set -euo pipefail
OUT=$(realpath -m "${1:?usage: m22_build.sh OUT_DIR}")
REPO=$(cd "$(dirname "$0")/.." && pwd)
ACK=$REPO/src/ack-6.18
SHIM=$REPO/src/m22/shim; mkdir -p "$SHIM"
ln -sf "$ACK/prebuilts/build-tools/linux-x86/bin/gavinhoward-bc" "$SHIM/bc"   # host has no bc; Kbuild needs it
export PATH=$SHIM:$ACK/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ACK/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ACK/prebuilts/build-tools/linux-x86/bin:$PATH
# fixed identity so two builds are byte-identical
export KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026' KBUILD_BUILD_USER=a50 KBUILD_BUILD_HOST=firstlight SOURCE_DATE_EPOCH=1793750400
LIST=$REPO/src/m22/initramfs.list
sed "s#@REPO@#$REPO#g" "$REPO/tools/m22/initramfs.list.in" > "$LIST"
touch -d @1793750400 "$REPO/src/m22/busybox" "$REPO/tools/m22/init" "$LIST"
rm -rf "$OUT"; cd "$ACK/common"
M="make -j16 ARCH=arm64 LLVM=1 O=$OUT"
$M a50_firstlight_defconfig >/dev/null
./scripts/config --file "$OUT/.config" --set-str INITRAMFS_SOURCE "$LIST"
$M olddefconfig >/dev/null
$M Image 2>&1 | tail -3
sha256sum "$OUT/arch/arm64/boot/Image"; stat -c '%s bytes' "$OUT/arch/arm64/boot/Image"

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
# A50_INIT=path: use another init in the initramfs (default tools/m22/init; M3.2 uses tools/m32/init)
INIT=$(realpath "${A50_INIT:-$REPO/tools/m22/init}")
sed -e "s#@REPO@#$REPO#g" -e "s#$REPO/tools/m22/init#$INIT#" "$REPO/tools/m22/initramfs.list.in" > "$LIST"
touch -d @1793750400 "$REPO/src/m22/busybox" "$INIT" "$LIST"
rm -rf "$OUT"; cd "$ACK/common"
M="make -j16 ARCH=arm64 LLVM=1 O=$OUT"
$M a50_firstlight_defconfig >/dev/null
./scripts/config --file "$OUT/.config" --set-str INITRAMFS_SOURCE "$LIST"
# A50_DIAG=1 (branch a50-diag only): enable the first-light diagnostic stages and tag the version string
if [ "${A50_DIAG:-0}" = 1 ]; then ./scripts/config --file "$OUT/.config" -e A50_DIAG --set-str LOCALVERSION "-a50-diag"; fi
# A50_DIAG_RESET_STAGE=N (with A50_DIAG=1): the diag kernel resets the SoC (PMU SWRESET) at the start of stage N
if [ -n "${A50_DIAG_RESET_STAGE:-}" ]; then ./scripts/config --file "$OUT/.config" --set-val A50_DIAG_RESET_STAGE "$A50_DIAG_RESET_STAGE"; fi
# A50_DIAG_SKIP_MCT=1 (with A50_DIAG=1): skip the Exynos MCT init (stock DT clocks have no 6.18 provider)
if [ "${A50_DIAG_SKIP_MCT:-0}" = 1 ]; then ./scripts/config --file "$OUT/.config" -e A50_DIAG_SKIP_MCT; fi
# A50_DIAG_DUMP_DSS=1 (with A50_DIAG=1): at late_initcall dump printk to the DSS log buffer and reboot to Download mode
if [ "${A50_DIAG_DUMP_DSS:-0}" = 1 ]; then ./scripts/config --file "$OUT/.config" -e A50_DIAG_DUMP_DSS; fi
# A50_DIAG_DUMP_AFTER=N (with A50_DIAG_DUMP_DSS=1): 0 = late_initcall, N = after N s, -1 = only on panic
if [ -n "${A50_DIAG_DUMP_AFTER:-}" ]; then ./scripts/config --file "$OUT/.config" --set-val A50_DIAG_DUMP_AFTER "$A50_DIAG_DUMP_AFTER"; fi
# A50_CMDLINE_APPEND="..." : append to CONFIG_CMDLINE (S-Boot drops the boot.img cmdline; CONFIG_CMDLINE_EXTEND=y)
if [ -n "${A50_CMDLINE_APPEND:-}" ]; then ./scripts/config --file "$OUT/.config" --set-str CMDLINE "$(sed -n 's/^CONFIG_CMDLINE="\(.*\)"$/\1/p' "$OUT/.config") $A50_CMDLINE_APPEND"; fi
# A50_CONFIG="-e FOO -d BAR ..." : extra scripts/config arguments (diagnostic builds)
if [ -n "${A50_CONFIG:-}" ]; then ./scripts/config --file "$OUT/.config" $A50_CONFIG; fi
$M olddefconfig >/dev/null
$M Image 2>&1 | tail -3
sha256sum "$OUT/arch/arm64/boot/Image"; stat -c '%s bytes' "$OUT/arch/arm64/boot/Image"

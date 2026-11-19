#!/bin/bash
# M9.2: compile-only check of the SCSC core in a kernel tree (default: clean a50-wlbt worktree), using the S1 config
# (no initramfs) plus the SCSC options. Never flashes. Usage: tools/m92/compile_scsc.sh OUT_DIR [KERNEL_TREE]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
out=$(realpath -m "${1:?usage: compile_scsc.sh OUT_DIR [KERNEL_TREE]}")
kernel=$(realpath "${2:-$repo/src/m92/clean-kernel}")
ack=$(realpath "$repo/src/ack-6.18")
mkdir -p "$out" "$repo/src/m75/shim"
ln -sf "$ack/prebuilts/build-tools/linux-x86/bin/gavinhoward-bc" "$repo/src/m75/shim/bc"
export PATH=$repo/src/m75/shim:$ack/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ack/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ack/prebuilts/build-tools/linux-x86/bin:$PATH
unset KCFLAGS KCPPFLAGS LOCALVERSION KCONFIG_CONFIG KBUILD_OUTPUT
if [ ! -f "$out/.config" ]; then
    sed 's|^CONFIG_INITRAMFS_SOURCE=.*|CONFIG_INITRAMFS_SOURCE=""|' "$repo/reference/m85-integration/s1.config" > "$out/.config"
    printf 'CONFIG_SCSC_CORE=y\nCONFIG_SCSC_PLATFORM_EXYNOS9610=y\nCONFIG_SCSC_CM_MX_CLIENT_TEST=y\nCONFIG_SCSC_MX_ALWAYS_ON=y\n' >> "$out/.config"
fi
args=(-C "$kernel" -j16 ARCH=arm64 LLVM=1 "O=$out")
make "${args[@]}" olddefconfig >/dev/null
grep -E '^CONFIG_SCSC' "$out/.config"
make "${args[@]}" -k drivers/misc/samsung/ 2>&1 | tee "$out/scsc-build.log" | grep -E 'error|warning: (unused|implicit)|Error' | head -${SHOW:-60} || true
echo "errors: $(grep -c ' error: ' "$out/scsc-build.log" || true)"

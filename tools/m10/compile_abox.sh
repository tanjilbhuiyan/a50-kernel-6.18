#!/bin/bash
# M10.2: compile-only check of the ABOX driver in a kernel tree (default: clean a50-audio worktree), using the S1
# config (no initramfs) plus ALSA/ASoC and ABOX. Never flashes. Usage: tools/m10/compile_abox.sh OUT_DIR [KERNEL_TREE]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
out=$(realpath -m "${1:?usage: compile_abox.sh OUT_DIR [KERNEL_TREE]}")
kernel=$(realpath "${2:-$repo/src/m10/clean-kernel}")
ack=$(realpath "$repo/src/ack-6.18")
mkdir -p "$out" "$repo/src/m75/shim"
ln -sf "$ack/prebuilts/build-tools/linux-x86/bin/gavinhoward-bc" "$repo/src/m75/shim/bc"
export PATH=$repo/src/m75/shim:$ack/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ack/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ack/prebuilts/build-tools/linux-x86/bin:$PATH
unset KCFLAGS KCPPFLAGS LOCALVERSION KCONFIG_CONFIG KBUILD_OUTPUT
if [ ! -f "$out/.config" ]; then
    sed 's|^CONFIG_INITRAMFS_SOURCE=.*|CONFIG_INITRAMFS_SOURCE=""|' "$repo/reference/m85-integration/s1.config" > "$out/.config"
    printf 'CONFIG_SOUND=y\nCONFIG_SND=y\nCONFIG_SND_SOC=y\nCONFIG_SND_SOC_SAMSUNG=y\nCONFIG_SND_SOC_SAMSUNG_ABOX=y\n' >> "$out/.config"
fi
args=(-C "$kernel" -j16 ARCH=arm64 LLVM=1 "O=$out")
make "${args[@]}" olddefconfig >/dev/null
grep -E '^CONFIG_(SND_SOC_SAMSUNG|SND_SOC_SAMSUNG_ABOX|SEC_SND)' "$out/.config"
make "${args[@]}" -k sound/soc/samsung/abox/ 2>&1 | tee "$out/abox-build.log" | grep -E ' error: |Error' | head -${SHOW:-60} || true
echo "errors: $(grep -c ' error: ' "$out/abox-build.log" || true)"

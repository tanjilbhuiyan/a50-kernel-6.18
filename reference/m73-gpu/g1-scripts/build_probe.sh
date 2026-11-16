#!/bin/bash
# Compile the exact stock-ABI property probe for native and compat userspace.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=${1:-src/m73/probe}
mkdir -p "$out"
ack=${A50_ACK_WORKSPACE:-$repo/src/ack-6.18}
headers=$ack/common/drivers/gpu/arm/midgard
ndk_bin=${A50_NDK_BIN:-$repo/src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin}
for bits in 64 32; do
    compiler=aarch64-linux-android30-clang
    if [ "$bits" = 32 ]; then compiler=armv7a-linux-androideabi30-clang; fi
    "$ndk_bin/$compiler" -std=gnu11 -static -O2 -Wall -Wextra -Werror \
        -I "$headers" tools/m73/gpuprops_smoke.c -o "$out/gpuprops$bits"
done
sha256sum "$out/gpuprops64" "$out/gpuprops32"

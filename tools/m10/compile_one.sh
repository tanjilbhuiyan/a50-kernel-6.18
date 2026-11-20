#!/bin/bash
# M10.2: compile one object of the ABOX tree serially (readable diagnostics). Usage: compile_one.sh OUT_DIR OBJ [TREE]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
out=$(realpath "$1"); obj=$2; kernel=$(realpath "${3:-$repo/src/m10/clean-kernel}"); ack=$(realpath "$repo/src/ack-6.18")
export PATH=$repo/src/m75/shim:$ack/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ack/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ack/prebuilts/build-tools/linux-x86/bin:$PATH
unset KCFLAGS KCPPFLAGS LOCALVERSION KCONFIG_CONFIG KBUILD_OUTPUT
make -C "$kernel" -j1 ARCH=arm64 LLVM=1 "O=$out" KCFLAGS=-ferror-limit=0 "$obj" 2>&1

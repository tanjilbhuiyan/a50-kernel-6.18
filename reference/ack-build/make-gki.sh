#!/bin/bash
set -e
export PATH=/tmp/claude-1001/-home-bs01808-Development-RnD-ubuntu-touch-a50-kernel-6-18/bbb26474-9bd9-4e43-a9a1-95b882edf494/scratchpad/shim:/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin:/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin:/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/kernel-build-tools/linux_musl-x86/bin:/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/build-tools/linux-x86/bin:$PATH
export KBUILD_BUILD_USER=kleaf KBUILD_BUILD_HOST=build-host
cd /home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/common
M="make -j16 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/out/make-gki RUSTC=/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc BINDGEN=/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/clang-tools/linux-x86/bin/bindgen RUSTFMT=/home/bs01808/Development/RnD/ubuntu-touch/a50-kernel-6.18/src/ack-6.18/prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustfmt"
$M gki_defconfig
$M Image Image.gz

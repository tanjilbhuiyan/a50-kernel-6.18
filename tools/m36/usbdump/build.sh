#!/bin/bash
# Build a50_usbdump.ko against the saved baseline kernel build (docker volume a50-ksrc, mounted read-only).
#   tools/m36/usbdump/build.sh WORK_DIR OUT_KO
# -fno-lto: the baseline uses ThinLTO, whose link cache needs a writable tree; the tree stays read-only.
set -euo pipefail
W=${1:?}; OUT=${2:?}; U=$(cd "$(dirname "$0")" && pwd)
rm -rf "$W"; mkdir -p "$W"; cp "$U/a50_usbdump.c" "$U/regs.h" "$U/Makefile" "$W/"
docker run --rm --user "$(id -u):$(id -g)" -v a50-ksrc:/k:ro -v "$W:/m" -w /m a50-halium-build sh -c \
 'export PATH=/k/toolchain/bin:$PATH LD_LIBRARY_PATH=/k/toolchain/lib ANDROID_MAJOR_VERSION=r PLATFORM_VERSION=11.0.0 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  make -C /k M=/m ARCH=arm64 CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CFLAGS_MODULE=-fno-lto modules'
cp "$W/a50_usbdump.ko" "$OUT"

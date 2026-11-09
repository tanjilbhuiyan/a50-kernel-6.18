#!/bin/bash
# Build the 4.14 diagnostic kernel: the saved baseline tree (volume a50-ksrc, never modified) copied to
# a50-ksrc-diag, plus a50_usbdump_builtin.c. Not byte-identical to the baseline by design.
#   tools/m36/usbdump/build_kernel.sh OUT_IMAGE
set -euo pipefail
OUT=$(realpath -m "${1:?}"); U=$(cd "$(dirname "$0")" && pwd); D=$(dirname "$OUT"); B=$(basename "$OUT")
docker volume inspect a50-ksrc >/dev/null
if ! docker volume inspect a50-ksrc-diag >/dev/null 2>&1; then
  docker volume create a50-ksrc-diag >/dev/null
  docker run --rm -v a50-ksrc:/from:ro -v a50-ksrc-diag:/to a50-halium-build sh -c 'cp -a /from/. /to/'
fi
docker run --rm -v a50-ksrc-diag:/k -v "$U:/u:ro" -v "$D:/out" -e HOST_ID="$(id -u):$(id -g)" -e B="$B" -w /k a50-halium-build sh -c '
  set -e
  cp /u/a50_usbdump_builtin.c drivers/soc/samsung/
  cp /u/regs.h drivers/soc/samsung/a50_usbdump_regs.h
  grep -q a50_usbdump_builtin drivers/soc/samsung/Makefile || echo "obj-y += a50_usbdump_builtin.o" >> drivers/soc/samsung/Makefile
  export PATH=/k/toolchain/bin:$PATH LD_LIBRARY_PATH=/k/toolchain/lib ANDROID_MAJOR_VERSION=r PLATFORM_VERSION=11.0.0 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  make -C /k ARCH=arm64 CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j12 LOCALVERSION=" - Mint-user 1763150940"
  cp arch/arm64/boot/Image /out/$B; chown $HOST_ID /out/$B
  echo "RELEASE: $(cat include/config/kernel.release)"
  grep -c a50_usbdump_show System.map
'

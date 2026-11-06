#!/bin/bash
# M2.4 VISIBLE channel validation: baseline 4.14 Image + appended cave that writes a marker and then resets the SoC through
# the Exynos PMU SWRESET register (0x11860000+0x400 = 1, as drivers/soc/samsung/exynos-reboot.c:320 does). If the cave runs,
# the phone BOOT-LOOPS (visible) instead of freezing on the logo. No log buffer is needed to read the result.
#   log_kernel = phys 0xf9010000, 2 MiB.  marker at +0x1c0000 = 0xf91d0000:  "A50RST00", nonce, PC, x0, CurrentEL
#   magic SEC_LKMSG_MAGICKEY 0x0a6c6c7546 at +0x1ffff8 = 0xf920fff8 (drivers/samsung/debug/sec_debug_last_kmsg.c:40)
#   tools/m25_reset_cave.sh OUT_DIR
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); OUT=${1:?usage: m25_reset_cave.sh OUT_DIR}; mkdir -p "$OUT"
CL=$REPO/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin
NONCE=$(od -An -N2 -tx2 /dev/urandom | tr -d ' ')
cat > "$OUT/rst.S" <<ASM
	.text
	movz	x9, #0xf91d, lsl #16		// marker base 0xf91d0000
	movz	x12, #0x3541			// "A50RST00" little endian
	movk	x12, #0x5230, lsl #16
	movk	x12, #0x5453, lsl #32
	movk	x12, #0x3030, lsl #48
	str	x12, [x9]
	movz	x12, #0x$NONCE			// per-image nonce (fresh marker, not stale)
	movk	x12, #0xa50a, lsl #16
	str	x12, [x9, #8]
	adr	x13, .				// cave offset 0x24
	str	x13, [x9, #16]
	str	x0, [x9, #24]
	mrs	x14, CurrentEL
	str	x14, [x9, #32]
	movz	x10, #0xf920, lsl #16		// 0xf920fff8: last 8 bytes of log_kernel
	movk	x10, #0xfff8
	movz	x11, #0x7546			// 0x0000000a6c6c7546 = "Full\n"
	movk	x11, #0x6c6c, lsl #16
	movk	x11, #0x000a, lsl #32
	str	x11, [x10]
	dsb	sy
	movz	x10, #0x1186, lsl #16		// Exynos9610 PMU base 0x11860000 (stock DT reboot/pmu_base)
	movk	x10, #0x0400			// + SWRESET (0x400)
	mov	w11, #1
	str	w11, [x10]			// software reset of the SoC
	dsb	sy
1:	wfe
	b	1b
ASM
"$CL/clang" --target=aarch64-linux-gnu -c "$OUT/rst.S" -o "$OUT/rst.o"
"$CL/llvm-objcopy" -O binary --only-section=.text "$OUT/rst.o" "$OUT/rst.bin"
python3 -I - "$REPO/src/a50-halium/out/Image" "$OUT" <<'PY'
import struct,sys
base,out=sys.argv[1:3]
img=bytearray(open(base,'rb').read()); cave=open(out+'/rst.bin','rb').read()
C=len(img); assert C%4==0 and len(cave)%4==0
assert struct.unpack('<I',img[:4])[0]>>26==5
img[:4]=struct.pack('<I',0x14000000|((C//4)&0x3ffffff))      # b cave (appended, like the control)
open(out+'/Image.rst','wb').write(bytes(img)+cave)
w=struct.unpack('<I',img[:4])[0]; print("code0 -> %#x (cave start %#x): %s ; cave %d bytes"%((w&0x3ffffff)*4,C,(w&0x3ffffff)*4==C,len(cave)))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.rst" - "$OUT/boot-reset.img" | grep -E "kernel_size|out "
echo "NONCE=a50a$NONCE" > "$OUT/nonce.env"; cat "$OUT/nonce.env"
"$CL/llvm-objdump" -d --no-show-raw-insn "$OUT/rst.o" | grep -E "^\s+[0-9a-f]+:" 

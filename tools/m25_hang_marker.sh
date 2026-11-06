#!/bin/bash
# M2.4 channel validation: baseline 4.14 Image + appended cave that writes a marker HIGH in log_kernel and the
# sec_debug "Full\n" magic, then HANGS on purpose (mimics a failed test image). After the normal recovery chain the next
# baseline boot must show the marker in /proc/last_kmsg if the channel survives hard resets.
#   log_kernel = phys 0xf9010000, 2 MiB.  marker at +0x1c0000 = 0xf91d0000:  "A50HANG0", nonce, PC, x0, CurrentEL
#   magic SEC_LKMSG_MAGICKEY 0x0a6c6c7546 at +0x1ffff8 = 0xf920fff8 (drivers/samsung/debug/sec_debug_last_kmsg.c:40)
#   tools/m25_hang_marker.sh OUT_DIR
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); OUT=${1:?usage: m25_hang_marker.sh OUT_DIR}; mkdir -p "$OUT"
CL=$REPO/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin
NONCE=$(od -An -N2 -tx2 /dev/urandom | tr -d ' ')
cat > "$OUT/hang.S" <<ASM
	.text
	movz	x9, #0xf91d, lsl #16		// marker base 0xf91d0000
	movz	x12, #0x3541			// "A50HANG0" little endian
	movk	x12, #0x4830, lsl #16
	movk	x12, #0x4e41, lsl #32
	movk	x12, #0x3047, lsl #48
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
1:	wfe
	b	1b
ASM
"$CL/clang" --target=aarch64-linux-gnu -c "$OUT/hang.S" -o "$OUT/hang.o"
"$CL/llvm-objcopy" -O binary --only-section=.text "$OUT/hang.o" "$OUT/hang.bin"
python3 -I - "$REPO/src/a50-halium/out/Image" "$OUT" <<'PY'
import struct,sys
base,out=sys.argv[1:3]
img=bytearray(open(base,'rb').read()); cave=open(out+'/hang.bin','rb').read()
C=len(img); assert C%4==0 and len(cave)%4==0
assert struct.unpack('<I',img[:4])[0]>>26==5
img[:4]=struct.pack('<I',0x14000000|((C//4)&0x3ffffff))      # b cave (appended, like the control)
open(out+'/Image.hang','wb').write(bytes(img)+cave)
w=struct.unpack('<I',img[:4])[0]; print("code0 -> %#x (cave start %#x): %s ; cave %d bytes"%((w&0x3ffffff)*4,C,(w&0x3ffffff)*4==C,len(cave)))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.hang" - "$OUT/boot-hang.img" | grep -E "kernel_size|out "
echo "NONCE=a50a$NONCE" > "$OUT/nonce.env"; cat "$OUT/nonce.env"
"$CL/llvm-objdump" -d --no-show-raw-insn "$OUT/hang.o" | grep -E "^\s+[0-9a-f]+:" 

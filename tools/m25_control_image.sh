#!/bin/bash
# M2.4 control experiment: the KNOWN-BOOTABLE baseline 4.14 Image plus a tiny "code cave" appended at the end.
# code0 (the first instruction, `b stext`) is replaced by `b cave`; the cave stores a marker and the boot state at
# physical 0xf9030000 (same place and format as the 6.18 diagnostic stage 0) and then branches to the original target.
# If this image boots Ubuntu Touch AND the marker shows up in /proc/last_kmsg, then S-Boot enters a modified image,
# the marker channel works with a foreign writer, and the marker tells where S-Boot really runs the kernel.
#   tools/m25_control_image.sh OUT_DIR
set -euo pipefail
OUT=${1:?usage: m25_control_image.sh OUT_DIR}; REPO=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
CL=$REPO/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin
BASE=$REPO/src/a50-halium/out/Image            # sha256 6d000a98…, 42,827,792 B (M1.1)
cat > "$OUT/cave.S" <<'ASM'
	.text
	movz	x9, #0xf903, lsl #16
	movz	x12, #0x3541
	movk	x12, #0x4430, lsl #16
	movk	x12, #0x4149, lsl #32
	movk	x12, #0x3047, lsl #48
	str	x12, [x9]			// "A50DIAG0"
	adr	x13, .				// physical address of THIS instruction (cave offset 0x18)
	str	x13, [x9, #8]
	str	x0,  [x9, #16]			// DTB pointer
	mrs	x14, CurrentEL
	str	x14, [x9, #24]
	str	x1,  [x9, #32]
	str	x2,  [x9, #40]
	str	x3,  [x9, #48]
	nop					// replaced by `b <original code0 target>`
ASM
"$CL/clang" --target=aarch64-linux-gnu -c "$OUT/cave.S" -o "$OUT/cave.o"
"$CL/llvm-objcopy" -O binary --only-section=.text "$OUT/cave.o" "$OUT/cave.bin"
python3 -I - "$BASE" "$OUT" <<'PY'
import struct,sys
base,out=sys.argv[1],sys.argv[2]
img=bytearray(open(base,'rb').read()); cave=bytearray(open(out+'/cave.bin','rb').read())
C=len(img); assert C%4==0 and len(cave)%4==0
code0=struct.unpack('<I',img[:4])[0]
assert code0>>26==5, "code0 is not a B instruction"
imm=code0&0x3ffffff; imm-= (1<<26) if imm&(1<<25) else 0
target=imm*4                                   # original branch target, relative to image start
last=len(cave)-4                               # offset of the final nop inside the cave
delta=(target-(C+last))//4
cave[last:last+4]=struct.pack('<I',0x14000000|(delta&0x3ffffff))
img[:4]=struct.pack('<I',0x14000000|((C//4)&0x3ffffff))   # b cave
open(out+'/Image.ctl','wb').write(bytes(img)+bytes(cave))
print("original code0 target %#x; cave at image offset %#x (%d bytes), adr instruction at offset %#x"%(target,C,len(cave),C+0x18))
PY
"$CL/llvm-objdump" -d --no-show-raw-insn "$OUT/cave.o" | tail -17 || true
python3 -I - "$OUT/Image.ctl" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read(); n=len(d); C=n-60
def br(w,pos):
    assert w>>26==5; i=w&0x3ffffff; i-= (1<<26) if i&(1<<25) else 0; return pos+i*4
w0=struct.unpack('<I',d[:4])[0]; wl=struct.unpack('<I',d[n-4:])[0]
print("verify: code0 -> cave at %#x (cave starts at %#x: %s)"%(br(w0,0),C,br(w0,0)==C))
print("verify: cave's last instruction -> %#x (original stext target 0x1bd0000: %s)"%(br(wl,n-4),br(wl,n-4)==0x1bd0000))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.ctl" - "$OUT/boot-control.img" | grep -E "kernel_size|ramdisk_size|out "

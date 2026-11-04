#!/bin/bash
# M2.4 chain-loader image: the KNOWN-ACCEPTED baseline 4.14 Image (same size, header and ramdisk as the control that S-Boot ran)
# with its last bytes replaced by [shim][payload]. code0 (`b stext`) becomes `b shim`. The shim writes a marker
# ("A50SHIM0" + PC, x0-x3, CurrentEL at physical 0xf9030600), copies the payload (a 6.18 Image) to the 2 MiB-aligned
# address 0x80A00000, marks completion ("A50SHIM1"), clears x1-x3 (arm64 boot protocol), invalidates the I-cache and jumps
# there with x0 (the DTB pointer S-Boot gave us) untouched. The 4.14 code is never executed.
#   tools/m25_chain_image.sh PAYLOAD_IMAGE OUT_DIR
set -euo pipefail
PAY=${1:?usage: m25_chain_image.sh PAYLOAD_IMAGE OUT_DIR}; OUT=${2:?}; REPO=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
CL=$REPO/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin
BASE=$REPO/src/a50-halium/out/Image
python3 -I - "$BASE" "$PAY" "$OUT" "$CL" <<'PY'
import struct,subprocess,sys
base,pay,out,cl=sys.argv[1:5]
img=bytearray(open(base,'rb').read()); payload=open(pay,'rb').read()
n=len(img); assert len(payload)%8==0
asm=f"""	.text
	movz	x9, #0xf903, lsl #16
	add	x9, x9, #0x600
	movz	x12, #0x3541			// "A50SHIM0" little endian
	movk	x12, #0x5330, lsl #16
	movk	x12, #0x4948, lsl #32
	movk	x12, #0x304d, lsl #48
	str	x12, [x9]
	adr	x13, .				// physical address of this instruction (shim offset 0x1c)
	str	x13, [x9, #8]
	str	x0, [x9, #16]
	str	x1, [x9, #24]
	str	x2, [x9, #32]
	str	x3, [x9, #40]
	mrs	x14, CurrentEL
	str	x14, [x9, #48]
	adr	x4, payload			// source: the appended 6.18 Image
	movz	x5, #0x80a0, lsl #16		// destination, 2 MiB aligned
	mov	x7, x5
	movz	x6, #{(len(payload)//8)&0xffff:#x}
	movk	x6, #{(len(payload)//8)>>16:#x}, lsl #16	// number of 8-byte words
1:	ldr	x8, [x4], #8
	str	x8, [x5], #8
	subs	x6, x6, #1
	b.ne	1b
	movz	x12, #0x3541			// "A50SHIM1" = copy finished
	movk	x12, #0x5330, lsl #16
	movk	x12, #0x4948, lsl #32
	movk	x12, #0x314d, lsl #48
	str	x12, [x9, #64]
	dsb	sy
	ic	iallu
	dsb	sy
	isb
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x7				// x0 = DTB pointer, unchanged
	.balign	8
payload:
"""
open(out+'/shim.S','w').write(asm)
subprocess.check_call([cl+'/clang','--target=aarch64-linux-gnu','-c',out+'/shim.S','-o',out+'/shim.o'])
subprocess.check_call([cl+'/llvm-objcopy','-O','binary','--only-section=.text',out+'/shim.o',out+'/shim.bin'])
shim=open(out+'/shim.bin','rb').read(); assert len(shim)%4==0
tail_keep=8192                                    # keep the baseline's last 8 KiB untouched
pay_off=((n-tail_keep-len(payload))//8)*8
shim_off=pay_off-len(shim)
assert shim_off>0x1c00000
img[shim_off:shim_off+len(shim)]=shim
img[pay_off:pay_off+len(payload)]=payload
orig=struct.unpack('<I',img[:4])[0]; assert orig>>26==5
img[:4]=struct.pack('<I',0x14000000|((shim_off//4)&0x3ffffff))     # b shim
open(out+'/Image.chain','wb').write(bytes(img))
adr_off=shim_off+0x1c
print("size %d (unchanged) ; shim at image offset %#x (%d bytes), its `adr` at %#x ; payload at %#x (%d bytes) ends %#x"%(n,shim_off,len(shim),adr_off,pay_off,len(payload),pay_off+len(payload)))
open(out+'/chain.env','w').write("SHIM_ADR_OFF=%#x\nPAYLOAD_OFF=%#x\nPAYLOAD_LEN=%d\n"%(adr_off,pay_off,len(payload)))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.chain" - "$OUT/boot-chain.img" | grep -E "kernel_size|ramdisk_size|out "
"$CL/llvm-objdump" -d --no-show-raw-insn "$OUT/shim.o" | tail -44 | head -48

#!/bin/bash
# M2.4 Test 11: the 6.18 diagnostic Image (diag v2, packed exactly like image A of Test 2: honest header, tiny ramdisk)
# with ONE change: the first 5 instructions of primary_entry (the diag marker stores) replaced by the Exynos PMU SWRESET
# sequence proven in Test 10 (0x11860000 + 0x400 = 1). Phone boot-loops => S-Boot entered the 6.18 Image and its
# primary_entry ran. Static logo => it did not get that far.
#   tools/m25_diag_reset.sh DIAG_BUILD_DIR OUT_DIR
set -euo pipefail
B=${1:?usage: m25_diag_reset.sh DIAG_BUILD_DIR OUT_DIR}; OUT=${2:?}; REPO=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
CL=$REPO/src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin
T=$(awk '$3=="_text"{print $1}' "$B/System.map"); P=$(awk '$3=="primary_entry"{print $1}' "$B/System.map")
OFF=$((0x$P - 0x$T)); printf 'primary_entry at Image offset %#x\n' $OFF
printf '\tmovz x9, #0xf903, lsl #16\n' > "$OUT/orig.S"
printf '\tmovz x10, #0x1186, lsl #16\n\tmovk x10, #0x0400\n\tmov w11, #1\n\tstr w11, [x10]\n\tdsb sy\n' > "$OUT/rst.S"
for s in orig rst; do "$CL/clang" --target=aarch64-linux-gnu -c "$OUT/$s.S" -o "$OUT/$s.o"; "$CL/llvm-objcopy" -O binary --only-section=.text "$OUT/$s.o" "$OUT/$s.bin"; done
python3 -I - "$B/arch/arm64/boot/Image" "$OUT" $OFF <<'PY'
import sys,struct
img,out,off=sys.argv[1],sys.argv[2],int(sys.argv[3])
d=bytearray(open(img,'rb').read()); orig=open(out+'/orig.bin','rb').read(); rst=open(out+'/rst.bin','rb').read()
assert d[off:off+4]==orig, "primary_entry does not start with the diag marker store; refusing to patch"
code1=struct.unpack('<I',d[4:8])[0]; tgt=4+((code1&0x3ffffff)*4)
print("code0 %#010x (nop=0xd503201f) ; code1 branches to %#x (primary_entry %#x): %s"%(struct.unpack('<I',d[:4])[0],tgt,off,tgt==off))
assert tgt==off
d[off:off+len(rst)]=rst
open(out+'/Image.R','wb').write(bytes(d)); print("patched %d bytes at %#x"%(len(rst),off))
PY
cmp -l "$B/arch/arm64/boot/Image" "$OUT/Image.R" | wc -l | sed 's/^/bytes changed vs diag v2 Image: /'
"$REPO/tools/m22_pack.sh" "$OUT/Image.R" "$OUT/boot-diag-R.img" | tail -1
"$CL/llvm-objdump" -d --no-show-raw-insn "$OUT/rst.o" | grep -E "^\s+[0-9a-f]+:"

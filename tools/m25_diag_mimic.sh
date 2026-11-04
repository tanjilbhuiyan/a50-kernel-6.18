#!/bin/bash
# M2.4 diagnostics, image C: the 6.18 diagnostic Image dressed up as the baseline wherever S-Boot could look:
#  - kernel file zero-padded to the baseline Image's exact size (42,827,792 B),
#  - header text_offset = 0x80000 and image_size = 53,616,640 (the baseline's values),
#  - code0 = a direct `b primary_entry` (the baseline's code0 is `b stext`),
#  - the baseline's own ramdisk (10,792,361 B) instead of the tiny one.
#   [MAGIC=1] [CODE1ZERO=1] tools/m25_diag_mimic.sh DIAG_BUILD_DIR OUT_IMG     (DIAG_BUILD_DIR = src/ack-6.18/out/m25-diag2)
set -euo pipefail
B=${1:?usage: m25_diag_mimic.sh DIAG_BUILD_DIR OUT_IMG}; OUT=${2:?}
REPO=$(cd "$(dirname "$0")/.." && pwd)
python3 -I - "$B" "$OUT.Image" "$REPO/src/a50-halium/out/Image" <<'PY'
import struct,sys,re
b,out,base=sys.argv[1:4]
img=bytearray(open(b+'/arch/arm64/boot/Image','rb').read())
ref=open(base,'rb').read(64); rsz=len(open(base,'rb').read())
sm=open(b+'/System.map').read()
sym=lambda n:int(re.search(r'^([0-9a-f]+) \w '+n+r'$',sm,re.M).group(1),16)
entry=sym('primary_entry')-sym('_text')
assert entry%4==0 and entry<(1<<27)
b_prim=0x14000000|((entry//4)&0x3ffffff)
base_isz=struct.unpack('<Q',ref[16:24])[0]; base_toff=struct.unpack('<Q',ref[8:16])[0]
assert len(img)<=rsz
img[0:4]=struct.pack('<I',b_prim)
import os
if os.environ.get('MAGIC')=='1':
    img[0x28:0x30]=struct.pack('<Q',0xecefecef)      # Samsung "proca ta" header magic (res3)
if os.environ.get('CODE1ZERO')=='1':
    img[4:8]=bytes(4)                                  # the baseline's code1 is 0
img[8:16]=struct.pack('<Q',base_toff)
img[16:24]=struct.pack('<Q',base_isz)
img+=bytes(rsz-len(img))
open(out,'wb').write(img)
print("code0 = b primary_entry (offset %#x), text_offset %#x, image_size %d, padded to %d B"%(entry,base_toff,base_isz,len(img)))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT.Image" - "$OUT" | grep -E "kernel_size|ramdisk_size|out "

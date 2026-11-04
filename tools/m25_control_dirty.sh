#!/bin/bash
# M2.4 Test 7: the control image (baseline Image + appended 60-byte cave, KNOWN to run) with ONE added change:
# the same 7,170,056-byte region that the chain image overwrote (offset 0x21ff808) is overwritten in place with the
# 6.18 payload bytes. Nothing else differs from the control. If the cave marker still appears, S-Boot does not check
# the Image contents and the chain image failed for another reason; if not, S-Boot checks contents.
#   tools/m25_control_dirty.sh OUT_DIR
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); OUT=${1:?usage: m25_control_dirty.sh OUT_DIR}; mkdir -p "$OUT"
python3 -I - "$REPO" "$OUT" <<'PY'
import sys
repo,out=sys.argv[1:3]
img=bytearray(open(repo+'/src/m22/artifacts-ctl/Image.ctl','rb').read())
pay=open(repo+'/src/m22/artifacts-chain/Image.chain','rb').read()[0x21ff808:0x21ff808+7170056]
assert pay[:0x40]==open(repo+'/src/ack-6.18/out/m25-diag2/arch/arm64/boot/Image','rb').read(0x40)
assert len(img)==42827792+60
img[0x21ff808:0x21ff808+7170056]=pay
open(out+'/Image.dirty','wb').write(bytes(img))
print("control size",len(img),"; overwrote 7170056 bytes at 0x21ff808 with 6.18 payload; code0 + appended cave unchanged")
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.dirty" - "$OUT/boot-control-dirty.img" | grep -E "kernel_size|out "

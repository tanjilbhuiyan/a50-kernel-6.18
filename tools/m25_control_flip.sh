#!/bin/bash
# M2.4 Test 8: the control (baseline Image + appended cave, KNOWN to run) with ONE byte changed in place.
#   tools/m25_control_flip.sh OUT_DIR [OFFSET_HEX] [XOR_HEX]      default: offset 0x1000000, xor 0x01
# Bisects Test 7 (6.3 MB overwritten in place -> rejected). The byte is inside the 4.14 text; the cave runs first
# and writes its marker, so a later 4.14 crash does not matter.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); OUT=${1:?usage: m25_control_flip.sh OUT_DIR [OFFSET_HEX] [XOR_HEX]}; OFF=${2:-0x1000000}; X=${3:-0x01}; mkdir -p "$OUT"
python3 -I - "$REPO" "$OUT" "$OFF" "$X" <<'PY'
import sys
repo,out,off,x=sys.argv[1],sys.argv[2],int(sys.argv[3],16),int(sys.argv[4],16)
img=bytearray(open(repo+'/src/m22/artifacts-ctl/Image.ctl','rb').read())
print("byte at %#x: %#04x -> %#04x"%(off,img[off],img[off]^x)); img[off]^=x
open(out+'/Image.flip','wb').write(bytes(img))
PY
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img" "$OUT/Image.flip" - "$OUT/boot-control-flip.img" | grep -E "kernel_size|out "

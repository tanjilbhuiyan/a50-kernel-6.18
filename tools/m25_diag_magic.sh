#!/bin/bash
# M2.4 Test 5: the 6.18 diagnostic Image (image A of diag v2: honest header, text_offset 0, tiny ramdisk) with ONE change:
# the Samsung header magic 0xecefecef at Image offset 0x28 (the reserved field `res3`), as the 4.14 head.S writes it
# ("Magic number for proca ta"). Everything else is identical to Test 2.
#   tools/m25_diag_magic.sh DIAG_IMAGE OUT_DIR
set -euo pipefail
IMG=${1:?usage: m25_diag_magic.sh DIAG_IMAGE OUT_DIR}; OUT=${2:?}; REPO=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
cp "$IMG" "$OUT/Image.D"
printf '\xef\xec\xef\xec\x00\x00\x00\x00' | dd of="$OUT/Image.D" bs=1 seek=40 conv=notrunc status=none
cmp -l "$IMG" "$OUT/Image.D" | awk '{printf "Image byte %d: %d -> %d (decimal)\n",$1-1,strtonum("0"$2),strtonum("0"$3)}'
"$REPO/tools/m22_pack.sh" "$OUT/Image.D" "$OUT/boot-diag-D.img" | tail -1

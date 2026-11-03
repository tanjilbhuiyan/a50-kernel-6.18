#!/bin/bash
# M2.4 diagnostics: pack the A50 diagnostic kernel into two boot images that differ ONLY in the
# arm64 Image header's text_offset (bytes 8..15, little endian):
#   A = as built (0), B = 0x80000 (what the 4.14 baseline header says).
#   tools/m25_diag_images.sh DIAG_IMAGE OUT_DIR
set -euo pipefail
IMG=${1:?usage: m25_diag_images.sh DIAG_IMAGE OUT_DIR}; OUT=${2:?}
REPO=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
cp "$IMG" "$OUT/Image.A"
cp "$IMG" "$OUT/Image.B"
printf '\x00\x00\x08\x00\x00\x00\x00\x00' | dd of="$OUT/Image.B" bs=1 seek=8 conv=notrunc status=none
for v in A B; do
  "$REPO/tools/m22_pack.sh" "$OUT/Image.$v" "$OUT/boot-diag-$v.img" | tail -1
done
cmp -l "$OUT/Image.A" "$OUT/Image.B" | awk '{printf "Image byte %d: %o -> %o\n",$1-1,$2,$3}'

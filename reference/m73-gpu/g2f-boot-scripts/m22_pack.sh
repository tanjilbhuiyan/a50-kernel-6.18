#!/bin/bash
# M2.2: pack the first-light boot.img from the built Image.
#   tools/m22_pack.sh IMAGE OUT_IMG
# Header + addresses are copied from the baseline boot.img (donor); kernel = IMAGE (uncompressed, see M1.4);
# ramdisk = a 119-byte cpio.gz holding only /a50-marker (so the init can show whether S-Boot passed a ramdisk).
set -euo pipefail
IMAGE=${1:?usage: m22_pack.sh IMAGE OUT_IMG}; OUT=${2:?}
REPO=$(cd "$(dirname "$0")/.." && pwd)
DONOR="$REPO/baseline/ut-26.04-2026-10-19-aa17rf2/boot.img"   # pinned: baseline/ also holds the pre-flash snapshot
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
echo "a50-firstlight ramdisk marker" > "$T/a50-marker"; touch -d @1793750400 "$T/a50-marker"
(cd "$T" && echo a50-marker | cpio -o -H newc --reproducible --quiet | gzip -9 -n > ramdisk.cpio.gz)
python3 -I "$REPO/src/a50-halium/build/pack-boot-image.py" "$DONOR" "$IMAGE" "$T/ramdisk.cpio.gz" "$OUT"
SZ=$(stat -c %s "$OUT"); [ "$SZ" -le 57671680 ] || { echo "E: $OUT is $SZ B, over the 57671680 B BOOT limit" >&2; exit 1; }
echo "size $SZ B (limit 57671680), sha256 $(sha256sum "$OUT" | cut -c1-64)"

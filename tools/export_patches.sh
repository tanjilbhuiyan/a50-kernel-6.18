#!/bin/bash
# Export the clean A50 kernel branch as one ordered patch series in patches/, then prove that the series applied to the
# ACK base reproduces the branch tree exactly. Uses a temporary index; the kernel checkout and working tree are untouched.
#   tools/export_patches.sh [BRANCH]      (default a50-userdata, the head of the clean driver stack)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
K=$REPO/src/ack-6.18/common
BR=${1:-a50-userdata}
BASE=$(git -C "$K" merge-base "$BR" aosp/android17-6.18)
OUT=$REPO/patches
rm -f "$OUT"/[0-9][0-9][0-9][0-9]-*.patch
git -C "$K" format-patch -q --no-signature --zero-commit -o "$OUT" "$BASE..$BR"
IDX=$(mktemp); trap 'rm -f "$IDX"' EXIT
export GIT_INDEX_FILE=$IDX
git -C "$K" read-tree "$BASE"
for p in "$OUT"/[0-9][0-9][0-9][0-9]-*.patch; do git -C "$K" apply --cached --whitespace=nowarn "$p"; done
got=$(git -C "$K" write-tree); want=$(git -C "$K" rev-parse "$BR^{tree}")
echo "base $BASE, $(ls "$OUT"/[0-9][0-9][0-9][0-9]-*.patch | wc -l) patches from $BR"
if [ "$got" = "$want" ]; then echo "series reproduces $BR tree $want: OK"; else echo "MISMATCH: $got != $want"; exit 1; fi

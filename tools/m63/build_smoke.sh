#!/bin/bash
# Rebuild both replay helpers without changing the shared kernel checkout.
# Usage: tools/m63/build_smoke.sh [fresh-output-directory]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=${1:-src/m63-replay-rebuild}
kernel=src/ack-6.18/common
source_commit=33c851162603f15d9d01baa4b7fba27cf19b7126
ndk_bin=${A50_NDK_BIN:-$repo/src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin}
if [ -e "$out" ]; then
    echo "Output already exists: $out; choose a fresh directory" >&2
    exit 1
fi
mkdir -p "$out/include/linux"
git -C "$kernel" show "$source_commit:drivers/staging/android/uapi/ion.h" > "$out/include/ion.h"
git -C "$kernel" show "$source_commit:include/uapi/linux/dma-buf.h" > "$out/include/linux/dma-buf.h"
python3 - "$out/include/replay.h" <<'PY'
import json
import pathlib
import sys

requests = json.loads(pathlib.Path('reference/m63-ion/replay.json').read_text())
lines = [
    'struct captured_allocation { unsigned long long length; unsigned int mask, flags; };',
    'static const struct captured_allocation replay[] = {',
]
for request in requests:
    lines.append('    { %dULL, %dU, %dU },' %
                 (request['length'], request['mask'], request['flags']))
lines.append('};')
pathlib.Path(sys.argv[1]).write_text('\n'.join(lines) + '\n')
PY
for architecture in aarch64 armv7a; do
    bits=64
    compiler=aarch64-linux-android30-clang
    if [ "$architecture" = armv7a ]; then
        bits=32
        compiler=armv7a-linux-androideabi30-clang
    fi
    "$ndk_bin/$compiler" -std=gnu11 -static -O2 -Wall -Wextra -Werror \
        -I "$out/include" tools/m63/ion_smoke.c -o "$out/ion-smoke$bits"
done
sha256sum "$out"/ion-smoke64 "$out"/ion-smoke32

#!/bin/bash
# Build M7.5 S1 (ten-minute soak): I4 with the test-only timed dump moved from 420 s to 900 s; never flashes.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=$(realpath -m "${1:?usage: tools/m75/build_s1.sh FRESH_OUTPUT_DIR}")
ack=$(realpath "$repo/src/ack-6.18")
kernel=$(realpath "$repo/src/m75/runtime-kernel")
python3 -I "$repo/tools/m75/make_i4_runtime.py" >/dev/null
list=$(realpath "$repo/src/m75/i4-runtime/initramfs.list")
test ! -e "$out" || { echo "Refusing existing output: $out" >&2; exit 1; }
test "$(git -C "$kernel" branch --show-current)" = a50-m75-i0-test
test -z "$(git -C "$kernel" status --porcelain)"
mkdir -p "$out" "$repo/src/m75/shim"
ln -sf "$ack/prebuilts/build-tools/linux-x86/bin/gavinhoward-bc" "$repo/src/m75/shim/bc"
export PATH=$repo/src/m75/shim:$ack/prebuilts/clang/host/linux-x86/clang-r584948c/bin:$ack/prebuilts/kernel-build-tools/linux_musl-x86/bin:$ack/prebuilts/build-tools/linux-x86/bin:$PATH
export LIBCLANG_PATH=$ack/prebuilts/clang/host/linux-x86/clang-r584948c/lib
export KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026'
export KBUILD_BUILD_USER=a50 KBUILD_BUILD_HOST=firstlight KBUILD_BUILD_VERSION=1 SOURCE_DATE_EPOCH=1793750400
unset KCFLAGS KCPPFLAGS KRUSTFLAGS LOCALVERSION KCONFIG_CONFIG KBUILD_OUTPUT
python3 - "$out/.config" "$list" <<'PY'
from pathlib import Path
import sys
s=Path('reference/m73-gpu/g2.config').read_text().replace('@INITRAMFS@', sys.argv[2])
assert s.count('CONFIG_A50_DIAG_DUMP_AFTER=420\n')==1
s=s.replace('CONFIG_A50_DIAG_DUMP_AFTER=420\n','CONFIG_A50_DIAG_DUMP_AFTER=900\n')
Path(sys.argv[1]).write_text(s+'\nCONFIG_FB_A50_HANDOVER=y\nCONFIG_FB_A50_DIAGNOSTICS=y\n')
PY
args=(-C "$kernel" -j16 ARCH=arm64 LLVM=1 "O=$out"
    "RUSTC=$ack/prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"
    "BINDGEN=$ack/prebuilts/clang-tools/linux-x86/bin/bindgen")
make "${args[@]}" olddefconfig
python3 - "$out/.config" "$list" <<'PY'
from pathlib import Path
import re,sys
def values(text):
    pairs={}
    for line in text.splitlines():
        if line.startswith('CONFIG_'):
            name,value=line.split('=',1);pairs[name]=value
        elif re.fullmatch(r'# CONFIG_\w+ is not set',line):
            pairs[line.split()[1]]='n'
    return pairs
old=values(Path('reference/m73-gpu/g2.config').read_text().replace('@INITRAMFS@',sys.argv[2]))
new=values(Path(sys.argv[1]).read_text())
delta={k:[old.get(k),new.get(k)] for k in old.keys()|new.keys() if old.get(k)!=new.get(k)}
assert delta=={'CONFIG_FB_A50_HANDOVER':[None,'y'],'CONFIG_FB_A50_DIAGNOSTICS':[None,'y'],'CONFIG_A50_DIAG_DUMP_AFTER':['420','900']},delta
print('Config vs G2g: display selectors and the soak timer only:',delta)
PY
make "${args[@]}" Image exynos/exynos9610-a50-gpu.dtb
python3 - "$out" <<'PY'
from pathlib import Path
import hashlib,subprocess,sys
p=Path(sys.argv[1])
dtb='arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
got=hashlib.sha256((p/dtb).read_bytes()).hexdigest()
assert got=='c30e8fb32689b12726ac56581432de2ad9bde55e4017b2afc168b299ccd2ef1a',got
print('Unchanged G2g/I0 DTB:',got)
def listing(cpio):
    return set(subprocess.run(['cpio','-it','--quiet'],input=Path(cpio).read_bytes(),capture_output=True,check=True).stdout.decode().split())
i0=listing('src/m75/i0-as-built/initramfs_data.cpio'); i2=listing(p/'usr/initramfs_data.cpio')
assert i2-i0=={'a50/m75','a50/m75/defer_audio.sh','a50/m75/touch.pa','a50/m75/defer_gsthybris.sh','a50/m75/libgsthybris.placeholder'} and not i0-i2,(sorted(i2-i0),sorted(i0-i2))
print('Runtime cpio entries: I0 plus',sorted(i2-i0))
PY
sha256sum "$out/.config" "$out/arch/arm64/boot/Image" \
    "$out/arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb" "$out/usr/initramfs_data.cpio"

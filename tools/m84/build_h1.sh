#!/bin/bash
# Build M8.4 H1: K1 config + GPIO LEDs/transient trigger on branch a50-m84-h1-test (K1 test kernel + a50-input hall/vibrator).
# patches: melfas_mip4 event format 8, touchscreen@48 on bus 4). Never flashes.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=$(realpath -m "${1:?usage: tools/m84/build_h1.sh FRESH_OUTPUT_DIR}")
ack=$(realpath "$repo/src/ack-6.18")
kernel=$(realpath "$repo/src/m75/runtime-kernel")
python3 -I "$repo/tools/m75/make_i4_runtime.py" >/dev/null
list=$(realpath "$repo/src/m75/i4-runtime/initramfs.list")
test ! -e "$out" || { echo "Refusing existing output: $out" >&2; exit 1; }
test "$(git -C "$kernel" branch --show-current)" = a50-m84-h1-test
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
assert s.count('# CONFIG_I2C is not set\n')==1
s=s.replace('# CONFIG_I2C is not set\n','')
Path(sys.argv[1]).write_text(s+'\nCONFIG_FB_A50_HANDOVER=y\nCONFIG_FB_A50_DIAGNOSTICS=y\n'
  'CONFIG_I2C=y\nCONFIG_I2C_CHARDEV=y\nCONFIG_I2C_S3C2410=y\n# CONFIG_I2C_EXYNOS5 is not set\n# CONFIG_I2C_HID is not set\n'
  'CONFIG_INPUT_EVDEV=y\nCONFIG_INPUT_TOUCHSCREEN=y\nCONFIG_TOUCHSCREEN_MELFAS_MIP4=y\nCONFIG_INPUT_KEYBOARD=y\nCONFIG_KEYBOARD_GPIO=y\n# CONFIG_KEYBOARD_ATKBD is not set\nCONFIG_LEDS_GPIO=y\nCONFIG_LEDS_TRIGGER_TRANSIENT=y\n'
  'CONFIG_DEBUG_KERNEL=y\nCONFIG_SOFTLOCKUP_DETECTOR=y\nCONFIG_BOOTPARAM_SOFTLOCKUP_PANIC=y\nCONFIG_HARDLOCKUP_DETECTOR=y\nCONFIG_BOOTPARAM_HARDLOCKUP_PANIC=y\n')
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
need={'CONFIG_LEDS_GPIO':'y','CONFIG_LEDS_TRIGGER_TRANSIENT':'y','CONFIG_INPUT_KEYBOARD':'y','CONFIG_KEYBOARD_GPIO':'y','CONFIG_INPUT_EVDEV':'y','CONFIG_INPUT_TOUCHSCREEN':'y','CONFIG_TOUCHSCREEN_MELFAS_MIP4':'y','CONFIG_FB_A50_HANDOVER':'y','CONFIG_FB_A50_DIAGNOSTICS':'y','CONFIG_I2C':'y','CONFIG_I2C_CHARDEV':'y','CONFIG_I2C_S3C2410':'y',
      'CONFIG_SOFTLOCKUP_DETECTOR':'y','CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC':'y','CONFIG_HARDLOCKUP_DETECTOR':'y','CONFIG_BOOTPARAM_HARDLOCKUP_PANIC':'y'}
for k,v in need.items(): assert new.get(k)==v,(k,new.get(k))
allowed_on={'CONFIG_FB_A50_HANDOVER','CONFIG_FB_A50_DIAGNOSTICS','CONFIG_I2C','CONFIG_I2C_CHARDEV','CONFIG_I2C_S3C2410',
  'CONFIG_I2C_BOARDINFO','CONFIG_I2C_COMPAT','CONFIG_I2C_HELPER_AUTO','CONFIG_I2C_ALGOBIT',
  'CONFIG_DEBUG_KERNEL','CONFIG_SOFTLOCKUP_DETECTOR','CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC','CONFIG_HARDLOCKUP_DETECTOR',
  'CONFIG_BOOTPARAM_HARDLOCKUP_PANIC','CONFIG_HARDLOCKUP_DETECTOR_BUDDY','CONFIG_HARDLOCKUP_DETECTOR_COUNTS_HRTIMER',
  'CONFIG_LOCKUP_DETECTOR','CONFIG_DETECT_HUNG_TASK','CONFIG_DETECT_HUNG_TASK_BLOCKER','CONFIG_DEFAULT_HUNG_TASK_TIMEOUT',
  'CONFIG_DEBUG_MISC','CONFIG_RCU_TRACE','CONFIG_DEBUG_INFO_NONE','CONFIG_NET_VENDOR_MELLANOX','CONFIG_RTC_I2C_AND_SPI','CONFIG_INPUT_EVDEV','CONFIG_INPUT_TOUCHSCREEN','CONFIG_TOUCHSCREEN_MELFAS_MIP4','CONFIG_INPUT_KEYBOARD','CONFIG_KEYBOARD_GPIO','CONFIG_LEDS_GPIO','CONFIG_LEDS_TRIGGER_TRANSIENT'}
bad={k:v for k,v in delta.items() if v[1] not in ('n',None) and k not in allowed_on}
print('Config delta vs G2g: %d symbols; enabled:'%len(delta), sorted(k for k,v in delta.items() if v[1] not in ('n',None)))
print('Unexpected enabled symbols:',bad)
assert not bad,bad
PY
make "${args[@]}" Image exynos/exynos9610-a50-gpu.dtb
python3 - "$out" <<'PY'
from pathlib import Path
import hashlib,subprocess,sys
p=Path(sys.argv[1])
dtb='arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
got=hashlib.sha256((p/dtb).read_bytes()).hexdigest()
print('GPU DTB (now with I2C):',got)
img=hashlib.sha256((p/'arch/arm64/boot/Image').read_bytes()).hexdigest(); t1=hashlib.sha256(Path('src/m81/t1-as-built/Image').read_bytes()).hexdigest()
print('Image identical to T1:',img==t1,'(expected False: driver and evdev added)')
def listing(cpio):
    return set(subprocess.run(['cpio','-it','--quiet'],input=Path(cpio).read_bytes(),capture_output=True,check=True).stdout.decode().split())
i0=listing('src/m75/i0-as-built/initramfs_data.cpio'); i2=listing(p/'usr/initramfs_data.cpio')
assert i2-i0=={'a50/m75','a50/m75/defer_audio.sh','a50/m75/touch.pa','a50/m75/defer_gsthybris.sh','a50/m75/libgsthybris.placeholder'} and not i0-i2,(sorted(i2-i0),sorted(i0-i2))
print('Runtime cpio entries: I0 plus',sorted(i2-i0))
assert (p/'usr/initramfs_data.cpio').read_bytes()==Path('src/m75/i4-as-built/initramfs_data.cpio').read_bytes(),'runtime cpio differs from I4'
print('Runtime cpio identical to I4')
PY
sha256sum "$out/.config" "$out/arch/arm64/boot/Image" \
    "$out/arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb" "$out/usr/initramfs_data.cpio"

#!/usr/bin/env python3
"""Build native/compat probes using ABI declarations extracted from the driver."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
kernel = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
source = (kernel/'drivers/video/fbdev/a50-decon.c').read_text()
abi = source[source.index('/* G2f metadata ABI:'):source.index('/* HWC power modes')]
(out/'metadata_abi.h').write_text(
    '#include <stdint.h>\n#include <stddef.h>\n#include <sys/ioctl.h>\n'
    'typedef uint32_t u32; typedef uint8_t u8;\n'
    '#define static_assert(x) _Static_assert((x), #x)\n' + abi)
ndk = root/'src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin'
for bits, compiler in [(64,'aarch64-linux-android30-clang'),
                       (32,'armv7a-linux-androideabi30-clang')]:
    subprocess.run([str(ndk/compiler),'-std=gnu11','-static','-O2',
                    '-Wall','-Wextra','-Werror','-I',str(out),
                    str(root/'tools/m73/metadata_probe.c'),'-o',str(out/f'metadata{bits}')],check=True)
    print(f'Built {bits}-bit metadata ABI probe')

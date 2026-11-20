#!/usr/bin/env python3
"""Build M10.2 A1: the M9E2 kernel configuration (phone-tested) plus ALSA/ASoC and the ABOX core.

Seed: src/m94/m9e2-out/.config as built (I5 runtime, firmware_class.path, Wi-Fi/Bluetooth). Config delta:
CONFIG_SOUND/SND/SND_SOC/SND_SOC_SAMSUNG/SND_SOC_SAMSUNG_ABOX plus derived ALSA symbols. Kernel: a50-m10-a1-test
(a50-m92-w1-test + the a50-audio commits). DTB = M9E2 DTB plus the ABOX SysMMU, GIC, core and firmware memory.
The runtime cpio must stay byte-identical to M9E2. Never flashes.
"""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
import sys

TAG = sys.argv[1] if len(sys.argv) > 1 else 'a1'
ROOT = Path(__file__).resolve().parents[2]
KERNEL = ROOT / os.environ.get('A50_KERNEL', 'src/m10/test-kernel')
OUT = ROOT / f'src/m10/{TAG}-out'
SEED = ROOT / 'src/m94/m9e2-out/.config'
SEED_CPIO = ROOT / 'src/m94/m9e2-out/usr/initramfs_data.cpio'
AUDIO = {'CONFIG_SOUND': 'y', 'CONFIG_SND': 'y', 'CONFIG_SND_SOC': 'y', 'CONFIG_SND_SOC_SAMSUNG': 'y',
         'CONFIG_SND_SOC_SAMSUNG_ABOX': 'y'}
DERIVED = ('CONFIG_SND_', 'CONFIG_SOUND_', 'CONFIG_AC97_BUS', 'CONFIG_REGMAP_MMIO', 'CONFIG_REGMAP_I2C', 'CONFIG_XARRAY_MULTI')


def run(*args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def values(text):
    result = {}
    for line in text.splitlines():
        if line.startswith('CONFIG_'):
            key, _, value = line.partition('=')
            result[key] = value
        elif re.fullmatch(r'# CONFIG_\w+ is not set', line):
            result[line.split()[1]] = 'n'
    return result


def main():
    assert not OUT.exists(), 'Choose a fresh output; refusing overwrite'
    assert subprocess.check_output(['git', '-C', KERNEL, 'branch', '--show-current'], text=True).strip() == os.environ.get('A50_BRANCH', 'a50-m10-a1-test')
    assert not subprocess.check_output(['git', '-C', KERNEL, 'status', '--porcelain'], text=True)
    source = subprocess.check_output(['git', '-C', KERNEL, 'rev-parse', 'HEAD'], text=True).strip()
    run('python3', '-I', ROOT / 'tools/m94/make_i5_runtime.py', stdout=subprocess.DEVNULL)
    base = SEED.read_text()
    seed = base + ''.join(('# %s is not set\n' % k) if v == 'n' else ('%s=%s\n' % (k, v)) for k, v in AUDIO.items())
    OUT.mkdir(parents=True)
    (OUT / '.config').write_text(seed)
    ack = ROOT / 'src/ack-6.18'
    clang = ack / 'prebuilts/clang/host/linux-x86/clang-r584948c'
    shim = OUT / 'shim'
    shim.mkdir()
    (shim / 'bc').symlink_to(ack / 'prebuilts/build-tools/linux-x86/bin/gavinhoward-bc')
    env = os.environ.copy()
    for key in ('LOCALVERSION', 'KCONFIG_CONFIG', 'KCONFIG_ALLCONFIG', 'KBUILD_OUTPUT',
                'KCFLAGS', 'KCPPFLAGS', 'KRUSTFLAGS', 'KBUILD_EXTRA_SYMBOLS'):
        env.pop(key, None)
    env.update(PATH=os.pathsep.join(map(str, (shim, clang / 'bin',
        ack / 'prebuilts/kernel-build-tools/linux_musl-x86/bin',
        ack / 'prebuilts/build-tools/linux-x86/bin'))) + os.pathsep + env['PATH'],
        LIBCLANG_PATH=str(clang / 'lib'), KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026',
        KBUILD_BUILD_USER='a50', KBUILD_BUILD_HOST='firstlight',
        KBUILD_BUILD_VERSION='1', SOURCE_DATE_EPOCH='1793750400')
    make = ['make', '-C', KERNEL, '-j16', 'ARCH=arm64', 'LLVM=1', f'O={OUT}',
            f'RUSTC={ack / "prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(*make, 'olddefconfig', env=env)
    old, new = values(base), values((OUT / '.config').read_text())
    delta = {k: [old.get(k), new.get(k)] for k in old.keys() | new.keys() if old.get(k) != new.get(k)}
    derived = {k for k in set(delta) - set(AUDIO) if k.startswith(DERIVED)}
    newly_visible_off = {k for k, (a, b) in delta.items() if a is None and b == 'n'}
    unexpected = set(delta) - derived - set(AUDIO) - newly_visible_off
    assert not unexpected, sorted(unexpected)
    for k, v in AUDIO.items():
        assert new.get(k, 'n') == v, (k, new.get(k))
    run('python3', '-I', ROOT / 'tools/m52/guard_unittest.py', KERNEL, '0x1c8700', '0xee42ff')
    run('python3', '-I', ROOT / 'tools/m53/sense_unittest.py', KERNEL)
    run(*make, 'Image', 'exynos/exynos9610-a50-gpu.dtb', env=env)
    dtb = OUT / 'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
    cpio = OUT / 'usr/initramfs_data.cpio'
    assert cpio.read_bytes() == SEED_CPIO.read_bytes(), 'runtime cpio differs from M9E2'
    boot = ROOT / f'src/m10/boot-{TAG}.img'
    dtimg = ROOT / f'src/m10/dt-{TAG}.img'
    run('bash', ROOT / 'tools/m22_pack.sh', OUT / 'arch/arm64/boot/Image', boot)
    run('python3', '-I', ROOT / 'tools/dt_table.py', 'build', ROOT / 'reference/stock-images/dt.img', dtimg,
        '--set', f'0={dtb}')
    files = [OUT / '.config', OUT / 'arch/arm64/boot/Image', dtb, cpio, boot, dtimg]
    result = {'source_commit': source, 'config_delta_from_M9E2': delta,
              'files': {str(p.relative_to(ROOT)): {'size': p.stat().st_size,
                        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}}
    (ROOT / 'reference/m10-audio').mkdir(parents=True, exist_ok=True)
    (ROOT / f'reference/m10-audio/{TAG}-build-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

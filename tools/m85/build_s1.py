#!/usr/bin/env python3
"""Build M8.5 S1 from the exact H1 source/config; only extend the dump timer to 900 s."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
KERNEL = ROOT / 'src/m75/runtime-kernel'
OUT = ROOT / 'src/m85/s1-out'


def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    assert not OUT.exists(), 'Choose a fresh output; refusing overwrite'
    source = subprocess.check_output(['git', '-C', str(KERNEL), 'rev-parse', 'HEAD'], text=True).strip()
    assert source.startswith('3c651aa2d'), source
    assert not subprocess.check_output(['git', '-C', str(KERNEL), 'status', '--porcelain'], text=True)
    run('python3', '-I', ROOT / 'tools/m75/make_i4_runtime.py', stdout=subprocess.DEVNULL)
    expected = (ROOT / 'src/m84/h1-as-built/.config').read_text()
    assert expected.count('CONFIG_A50_DIAG_DUMP_AFTER=420\n') == 1
    expected = expected.replace('CONFIG_A50_DIAG_DUMP_AFTER=420\n', 'CONFIG_A50_DIAG_DUMP_AFTER=900\n')
    OUT.mkdir(parents=True)
    (OUT / '.config').write_text(expected)
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
    assert (OUT / '.config').read_text() == expected, 'Unexpected config delta'
    run('python3', '-I', ROOT / 'tools/m52/guard_unittest.py', KERNEL, '0x1c8700', '0xee42ff')
    run('python3', '-I', ROOT / 'tools/m53/sense_unittest.py', KERNEL)
    run(*make, 'Image', 'exynos/exynos9610-a50-gpu.dtb', env=env)
    dtb = OUT / 'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
    assert dtb.read_bytes() == (ROOT / 'src/m84/h1-as-built/exynos9610-a50-gpu.dtb').read_bytes()
    assert hashlib.sha256((OUT / 'usr/initramfs_data.cpio').read_bytes()).hexdigest() == \
        '2970e1aa2366a1ede69fb22a83a66c3d59361e53a05fbebe095a6f9ab25484ae'
    boot = ROOT / 'src/m85/boot-s1.img'
    run('bash', ROOT / 'tools/m22_pack.sh', OUT / 'arch/arm64/boot/Image', boot)
    files = [OUT / '.config', OUT / 'arch/arm64/boot/Image', dtb, OUT / 'usr/initramfs_data.cpio', boot]
    result = {'source_commit': source, 'config_delta_from_H1': {'CONFIG_A50_DIAG_DUMP_AFTER': [420, 900]},
              'dtb_matches_H1': True, 'runtime_matches_H1': True,
              'files': {str(p.relative_to(ROOT)): {'size': p.stat().st_size,
                       'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}}
    (ROOT / 'reference/m85-integration/s1-build-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

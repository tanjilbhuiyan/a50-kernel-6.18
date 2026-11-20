#!/usr/bin/env python3
"""Build a later M10.2 checkpoint in the A1i workspace, preserving each test's outputs.

Usage: build_checkpoint_incremental.py TAG
The source worktree must be clean and on the intended a50-m10-*-test branch.
Config, raw DTB and embedded runtime must stay byte-identical to frozen A1i.
Never flashes; output records point to immutable per-test copies.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
KERNEL = ROOT / 'src/m10/a1i-kernel'
OUT = ROOT / 'src/m10/a1i-out'
ANCHOR = ROOT / 'src/m10/a1i-as-built'


def run(*args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def git(*args):
    return subprocess.check_output(['git', '-C', str(KERNEL), *args], text=True).strip()


def record(path):
    data = path.read_bytes()
    return {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def main():
    assert len(sys.argv) == 2 and re.fullmatch(r'a1[a-z][0-9]*', sys.argv[1]), 'Provide a checkpoint TAG'
    tag = sys.argv[1]
    archive = ROOT / f'src/m10/{tag}-as-built'
    boot, dt = (ROOT / f'src/m10/{kind}-{tag}.img' for kind in ('boot', 'dt'))
    report = ROOT / f'reference/m10-audio/{tag}-build-results.json'
    assert not archive.exists() and not boot.exists() and not dt.exists() and not report.exists(), 'Refusing overwrite'
    assert git('branch', '--show-current') == f'a50-m10-{tag}-test'
    assert not git('status', '--porcelain'), 'Source worktree is modified'
    source = git('rev-parse', 'HEAD')
    run('git', '-C', KERNEL, 'merge-base', '--is-ancestor',
        '747ad18c1c5f86eec7cc2e1be0c2edfb1b546baf', source)
    expected = (ANCHOR / '.config').read_bytes()
    assert (OUT / '.config').read_bytes() == expected, 'Config differs from frozen A1i'
    ack = ROOT / 'src/ack-6.18'
    clang = ack / 'prebuilts/clang/host/linux-x86/clang-r584948c'
    env = os.environ.copy()
    for key in ('LOCALVERSION', 'KCONFIG_CONFIG', 'KCONFIG_ALLCONFIG', 'KBUILD_OUTPUT',
                'KCFLAGS', 'KCPPFLAGS', 'KRUSTFLAGS', 'KBUILD_EXTRA_SYMBOLS'):
        env.pop(key, None)
    env.update(PATH=os.pathsep.join(map(str, (OUT / 'shim', clang / 'bin',
        ack / 'prebuilts/kernel-build-tools/linux_musl-x86/bin',
        ack / 'prebuilts/build-tools/linux-x86/bin'))) + os.pathsep + env['PATH'],
        LIBCLANG_PATH=str(clang / 'lib'), KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026',
        KBUILD_BUILD_USER='a50', KBUILD_BUILD_HOST='firstlight',
        KBUILD_BUILD_VERSION='1', SOURCE_DATE_EPOCH='1793750400')
    make = ['make', '-C', KERNEL, '-j16', 'ARCH=arm64', 'LLVM=1', f'O={OUT}',
            f'RUSTC={ack / "prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(*make, 'olddefconfig', env=env)
    assert (OUT / '.config').read_bytes() == expected, 'olddefconfig changed the frozen config'
    run('python3', '-I', ROOT / 'tools/m52/guard_unittest.py', KERNEL, '0x1c8700', '0xee42ff')
    run('python3', '-I', ROOT / 'tools/m53/sense_unittest.py', KERNEL)
    run(*make, 'Image', 'exynos/exynos9610-a50-gpu.dtb', env=env)
    image = OUT / 'arch/arm64/boot/Image'
    dtb = OUT / 'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
    cpio = OUT / 'usr/initramfs_data.cpio'
    assert dtb.read_bytes() == (ANCHOR / dtb.name).read_bytes(), 'Unexpected DTB change'
    assert cpio.read_bytes() == (ANCHOR / cpio.name).read_bytes(), 'Unexpected runtime change'
    assert not git('status', '--porcelain') and git('rev-parse', 'HEAD') == source
    run('bash', ROOT / 'tools/m22_pack.sh', image, boot)
    run('python3', '-I', ROOT / 'tools/dt_table.py', 'build', ROOT / 'reference/stock-images/dt.img', dt,
        '--set', f'0={dtb}')
    assert dt.read_bytes() == (ROOT / 'src/m10/dt-a1i.img').read_bytes()
    archive.mkdir()
    outputs = [boot, dt]
    for p in (OUT / '.config', image, dtb, cpio, OUT / 'System.map', OUT / 'drivers/iommu/exynos-iommu.o'):
        target = archive / p.name
        shutil.copy2(p, target)
        outputs.append(target)
    result = {'source_commit': source, 'source_branch': git('branch', '--show-current'),
              'incremental_workspace': 'src/m10/a1i-out', 'same_config_DTB_runtime_as_A1i': True,
              'guard_and_sense_checks': 'passed',
              'files': {str(p.relative_to(ROOT)): record(p) for p in outputs}}
    report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    main()

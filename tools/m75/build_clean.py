#!/usr/bin/env python3
"""Compile the exported clean M7 driver stack using pinned public M6 tools/runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TREE = '81fe4953be31a74851875040fe045b648ec18064'
LOCK = json.loads((ROOT / 'reproduce/m6/sources.lock.json').read_text())


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel', type=Path, required=True)
    parser.add_argument('--ack', type=Path, required=True)
    parser.add_argument('--list', type=Path, required=True, dest='listing')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=16)
    args = parser.parse_args()
    kernel, ack, listing, out = [p.resolve() for p in (args.kernel, args.ack, args.listing, args.out)]
    assert args.jobs > 0 and listing.is_file()
    assert not any(c.isspace() for p in (kernel, ack, listing, out) for c in str(p))
    assert git(kernel, 'rev-parse', 'HEAD^{tree}') == TREE, 'Not the exported clean graphics tree'
    assert not git(kernel, 'status', '--porcelain'), 'Source worktree is dirty'
    assert not out.exists(), 'Choose a fresh build output'
    for project in LOCK['projects']:
        if project['path'] != 'common':
            assert git(ack / project['path'], 'rev-parse', 'HEAD') == project['revision'], project['path']
    out.mkdir(parents=True)
    shim = out / 'shim'
    shim.mkdir()
    (shim / 'bc').symlink_to(ack / 'prebuilts/build-tools/linux-x86/bin/gavinhoward-bc')
    clang = ack / 'prebuilts/clang/host/linux-x86/clang-r584948c'
    env = os.environ.copy()
    for key in ('LOCALVERSION', 'KCONFIG_ALLCONFIG', 'KCONFIG_CONFIG', 'KBUILD_OUTPUT',
                'KCFLAGS', 'KCPPFLAGS', 'KRUSTFLAGS', 'KBUILD_EXTRA_SYMBOLS'):
        env.pop(key, None)
    env.update(PATH=os.pathsep.join(map(str, (shim, clang / 'bin',
        ack / 'prebuilts/kernel-build-tools/linux_musl-x86/bin',
        ack / 'prebuilts/build-tools/linux-x86/bin'))) + os.pathsep + env['PATH'],
        LIBCLANG_PATH=str(clang / 'lib'), KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026',
        KBUILD_BUILD_USER='a50', KBUILD_BUILD_HOST='firstlight',
        KBUILD_BUILD_VERSION='1', SOURCE_DATE_EPOCH='1793750400')
    expected = (ROOT / 'reference/m75-integration/clean.config').read_text().replace('@INITRAMFS@', str(listing))
    (out / '.config').write_text(expected)
    make = ['make', '-C', kernel, f'-j{args.jobs}', 'ARCH=arm64', 'LLVM=1', f'O={out}',
            f'RUSTC={ack / "prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(make + ['olddefconfig'], env=env)
    if (out / '.config').read_text() != expected:
        raise RuntimeError('Resolved config differs; inspect out/.config.old')
    run(make + ['Image', 'exynos/exynos9610-a50-gpu.dtb'], env=env)
    outputs = {}
    for name, locked in {
        'usr/initramfs_data.cpio': 'c855bb6eee66af35fc8ae2f21f2c85407d6cd46b9bf648b80e9a81672dd192a2',
        'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb': 'c30e8fb32689b12726ac56581432de2ad9bde55e4017b2afc168b299ccd2ef1a',
        '.config': None, 'arch/arm64/boot/Image': None,
    }.items():
        data = (out / name).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if locked:
            assert digest == locked, (name, digest, locked)
        outputs[name] = {'size': len(data), 'sha256': digest}
    result = {'source_tree': TREE, 'diagnostic_reset_code': False, 'phone_tested_as_this_clean_image': False,
              'outputs': outputs, 'note': 'Image/config hashes include the absolute embedded initramfs-list path.'}
    (out / 'build-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

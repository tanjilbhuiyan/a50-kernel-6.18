#!/usr/bin/env python3
"""Build the current clean A50 M8 stack using pinned public source and runtime inputs.

No phone operations. The historical M6 bootstrap supplies pinned tools and the
base Halium runtime; the M8 lock supplies the current patches, config and hooks.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[1]
SNAPSHOT = REPO / 'reproduce/m8'
LOCK = json.loads((SNAPSHOT / 'sources.lock.json').read_text())
spec = importlib.util.spec_from_file_location('a50_public_bootstrap', REPO / 'tools/reproduce_m6.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)
run, git, verify, sha = bootstrap.run, bootstrap.git, bootstrap.verify, bootstrap.sha


def prepare_kernel(work, cache):
    project = LOCK['projects'][0]
    kernel = work / 'ack/common'
    if not kernel.exists():
        kernel.mkdir(parents=True)
        run('git', 'init', kernel)
        run('git', '-C', kernel, 'remote', 'add', 'origin', project['url'])
        cached = cache / 'common' if cache else None
        source = str(cached) if cached and cached.exists() else 'origin'
        flags = [] if source != 'origin' else ['--filter=blob:none']
        run('git', '-C', kernel, 'fetch', '--depth=1', *flags, source, project['revision'])
        run('git', '-C', kernel, 'checkout', '--detach', project['revision'])
    if git(kernel, 'status', '--porcelain'):
        raise RuntimeError('Refusing a modified kernel checkout')
    if git(kernel, 'rev-parse', 'HEAD^{tree}') != LOCK['kernel_tree']:
        if git(kernel, 'rev-parse', 'HEAD') != project['revision']:
            raise RuntimeError('Refusing an unexpected kernel revision')
        patches = [REPO / name for name in LOCK['patches']]
        run('git', '-C', kernel, 'apply', '--index', *patches)
        if git(kernel, 'write-tree') != LOCK['kernel_tree']:
            raise RuntimeError('Patch replay did not reproduce the locked M8 tree')
        run('git', '-C', kernel, '-c', 'user.name=A50 snapshot', '-c',
            'user.email=snapshot@example.invalid', 'commit', '-m',
            'Reconstruct clean A50 driver stack through M8.3')
    return kernel


def prepare_runtime(work, assets):
    listing = bootstrap.prepare_ramdisk(work, assets)
    init = work / 'payload/halium-init-runtime'
    for name in ('reference/m75-integration/i2-init-delta.patch',
                 'reference/m75-integration/i4-init-delta.patch'):
        run('patch', '--batch', '--fuzz=0', init, REPO / name)
    verify(init, LOCK['expected']['halium-init-runtime'])
    run('sh', '-n', init)
    entries = listing.read_text().splitlines()
    entries.append('dir /a50/m75 0755 0 0')
    for target, source in LOCK['runtime_files'].items():
        if source.endswith('.sh'):
            run('sh', '-n', REPO / source)
        entries.append(f'file /a50/m75/{target} {REPO / source} 0644 0 0')
    listing.write_text('\n'.join(entries) + '\n')
    return listing


def build(work, listing, jobs):
    ack, out = work / 'ack', work / 'out'
    kernel = ack / 'common'
    out.mkdir(exist_ok=True)
    shim = work / 'shim'
    shim.mkdir(exist_ok=True)
    if not (shim / 'bc').exists():
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
    expected = (SNAPSHOT / 'config').read_text().replace('@INITRAMFS@', str(listing))
    (out / '.config').write_text(expected)
    make = ['make', '-C', kernel, f'-j{jobs}', 'ARCH=arm64', 'LLVM=1', f'O={out}',
            f'RUSTC={ack / "prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(*make, 'olddefconfig', env=env)
    if (out / '.config').read_text() != expected:
        raise RuntimeError('Locked M8 config changed; inspect out/.config.old')
    run('python3', '-I', REPO / 'tools/m52/guard_unittest.py', kernel, '0x1c8700', '0xee42ff')
    run('python3', '-I', REPO / 'tools/m53/sense_unittest.py', kernel)
    run(*make, 'Image', 'exynos/exynos9610-a50-gpu.dtb', env=env)
    dtb = out / 'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
    verify(dtb, LOCK['expected']['dtb'])
    verify(out / 'usr/initramfs_data.cpio', LOCK['expected']['initramfs_data.cpio'])
    image = out / 'arch/arm64/boot/Image'
    bootstrap.pack_boot(work / 'assets/boot-public.img', image, work / 'boot.img', work)
    outputs = [image, dtb, out / '.config', out / 'usr/initramfs_data.cpio', work / 'boot.img']
    result = {'profile': 'M8.3 clean source with I4 runtime', 'kernel_tree': LOCK['kernel_tree'],
              'diagnostic_reset_code': False, 'phone_tested_as_this_clean_image': False,
              'note': 'Image/config/BOOT hashes depend on absolute initramfs-list path; DTB and cpio are locked.',
              'files': {str(p.relative_to(work)): {'size': p.stat().st_size, 'sha256': sha(p)} for p in outputs}}
    (work / 'build-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=REPO / 'src/reproduce-m8')
    parser.add_argument('--cache', type=Path, help='optional pinned ACK/toolchain Git object cache')
    parser.add_argument('--assets', type=Path, help='optional hash-verified public download cache')
    parser.add_argument('--jobs', type=int, default=min(16, os.cpu_count() or 1))
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    work = args.work.resolve()
    if args.jobs < 1 or any(c.isspace() for c in str(work) + str(REPO)):
        parser.error('jobs must be positive; repository/work paths cannot contain whitespace')
    for name, digest in LOCK['tracked_inputs'].items():
        verify(REPO / name, digest)
    cache = args.cache.resolve() if args.cache else None
    work.mkdir(parents=True, exist_ok=True)
    prepare_kernel(work, cache)
    for project in LOCK['projects'][1:]:
        bootstrap.prepare_project(project, work, cache)
    assets = bootstrap.download_assets(work, args.assets.resolve() if args.assets else None)
    listing = prepare_runtime(work, assets)
    if not args.prepare_only:
        build(work, listing, args.jobs)


if __name__ == '__main__':
    main()

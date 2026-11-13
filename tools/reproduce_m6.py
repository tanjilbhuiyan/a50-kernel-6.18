#!/usr/bin/env python3
"""Reconstruct and build the tested M6 snapshot using pinned public inputs.

No phone access. All downloads, generated payloads and outputs stay in --work.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile

REPO = Path(__file__).resolve().parents[1]
SNAPSHOT = REPO / 'reproduce/m6'
LOCK = json.loads((SNAPSHOT / 'sources.lock.json').read_text())


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(path, expected):
    if sha(path) != expected:
        raise RuntimeError(f'Hash mismatch: {path}')


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def prepare_project(project, work, cache):
    dest = work / 'ack' / project['path']
    rev = project['revision']
    new = not dest.exists()
    if new:
        dest.parent.mkdir(parents=True, exist_ok=True)
        cached = cache / project['path'] if cache else None
        if cached and cached.exists() and project['path'] != 'common':
            # Only pinned public objects are used, never the cache's branch tip.
            run('git', 'clone', '--shared', '--no-checkout', cached, dest)
            run('git', '-C', dest, 'remote', 'set-url', 'origin', project['url'])
        else:
            run('git', 'init', dest)
            run('git', '-C', dest, 'remote', 'add', 'origin', project['url'])
            source = str(cached) if cached and cached.exists() else 'origin'
            flags = [] if source != 'origin' else ['--filter=blob:none']
            run('git', '-C', dest, 'fetch', '--depth=1', *flags, source, rev)
    if project['subdir']:
        run('git', '-C', dest, 'sparse-checkout', 'init', '--cone')
        subdirs = project['subdir']
        if isinstance(subdirs, str):
            subdirs = [subdirs]
        run('git', '-C', dest, 'sparse-checkout', 'set', *subdirs)
    if new:
        run('git', '-C', dest, 'checkout', '--detach', rev)
    if project['path'] == 'common':
        tree = git(dest, 'rev-parse', 'HEAD^{tree}')
        if tree != LOCK['kernel_tree']:
            if git(dest, 'rev-parse', 'HEAD') != rev or git(dest, 'status', '--porcelain'):
                raise RuntimeError(f'Refusing to alter unexpected kernel checkout: {dest}')
            run('git', '-C', dest, 'apply', '--index', SNAPSHOT / 'kernel.patch')
            if git(dest, 'write-tree') != LOCK['kernel_tree']:
                raise RuntimeError('Reconstructed kernel tree differs from the tested source')
            run('git', '-C', dest, '-c', 'user.name=A50 snapshot', '-c',
                'user.email=snapshot@example.invalid', 'commit', '-m',
                'Reconstruct M6 tested tree; provenance in reproduce/m6/source-history.txt')
    elif git(dest, 'rev-parse', 'HEAD') != rev:
        raise RuntimeError(f'Unexpected toolchain revision: {dest}')
    if git(dest, 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError(f'Modified pinned checkout: {dest}')


def download_assets(work, cache):
    assets = work / 'assets'
    assets.mkdir(exist_ok=True)
    for name, info in LOCK['assets'].items():
        path = assets / name
        if not path.exists():
            if cache and (cache / name).is_file():
                shutil.copyfile(cache / name, path)
            else:
                temporary = path.with_suffix('.download')
                run('curl', '-fL', '--retry', '2', info['url'], '-o', temporary)
                verify(temporary, info['sha256'])
                temporary.rename(path)
        verify(path, info['sha256'])
    return assets


def prepare_ramdisk(work, assets):
    payload = work / 'payload'
    payload.mkdir(exist_ok=True)
    rd = payload / 'ramdisk.gz'
    manifest = payload / 'halium-manifest.txt'
    run('python3', '-I', REPO / 'tools/m37/gen_manifest.py',
        assets / 'boot-public.img', rd, manifest)
    verify(rd, LOCK['expected']['ramdisk.gz'])
    # Extract one known ELF from the verified .deb; never execute package scripts.
    with (payload / 'busybox-data.tar.zst').open('wb') as out:
        run('ar', 'p', assets / 'busybox.deb', 'data.tar.zst', stdout=out)
    with (payload / 'busybox-data.tar').open('wb') as out:
        run('zstd', '-dc', payload / 'busybox-data.tar.zst', stdout=out)
    with tarfile.open(payload / 'busybox-data.tar') as archive:
        matches = [m for m in archive if m.isfile() and m.name.lstrip('./') in
                   ('bin/busybox', 'usr/bin/busybox')]
        if len(matches) != 1:
            raise RuntimeError('Expected exactly one BusyBox ELF in the pinned package')
        (payload / 'busybox').write_bytes(archive.extractfile(matches[0]).read())
    verify(payload / 'busybox', LOCK['expected']['busybox'])
    listing = payload / 'initramfs.list'
    run('python3', '-I', REPO / 'tools/m37/gen_embed_list.py', rd,
        payload / 'original', listing)
    entries = listing.read_text().splitlines()
    entry, = [s for s in entries if s.startswith('file /init ')]
    original = Path(entry.split()[2])
    init = payload / 'halium-init-runtime'
    shutil.copyfile(original, init)
    for patch in ('reference/m54-usb-ssh/force-init.patch',
                  'reference/m64-runtime/runtime7-init-delta.patch'):
        run('patch', '--batch', '--fuzz=0', init, REPO / patch)
    verify(init, LOCK['expected']['halium-init-runtime'])
    run('sh', '-n', init)
    entries[entries.index(entry)] = entry.replace(str(original), str(init), 1)
    entries.append('dir /a50/m64 0755 0 0')
    for name in ('mount_android_safe.sh', 'prepare_policy.sh',
                 'runtime_status.sh', 'defer_tee.sh'):
        source = REPO / 'reference/m64-runtime/runtime7-scripts' / name
        run('sh', '-n', source)
        entries.append(f'file /a50/m64/{name} {source} 0644 0 0')
    text = '\n'.join(entries) + '\n'
    text = text.replace('@REPO@/src/m22/busybox', str(payload / 'busybox'))
    text = text.replace('@REPO@/src/m36/halium-manifest.txt', str(manifest))
    text = text.replace('@REPO@', str(REPO))
    listing.write_text(text)
    return listing


def pack_boot(donor, image, output, work):
    # Android boot header v1: retain S-Boot's tested header verbatim apart
    # from component sizes, matching tools/m22_pack.sh's historical packer.
    data = donor.read_bytes()
    if data[:8] != b'ANDROID!':
        raise RuntimeError('Donor is not an Android boot image')
    kernel_size, _, rd_size, _, second_size, _, _, page, version, _ = struct.unpack_from('<10I', data, 8)
    if version != 1 or page != 2048 or second_size:
        raise RuntimeError('Unexpected pinned donor layout')
    marker_dir = work / 'marker'
    marker_dir.mkdir(exist_ok=True)
    marker = marker_dir / 'a50-marker'
    marker.write_text('a50-firstlight ramdisk marker\n')
    os.utime(marker, (1793750400, 1793750400))
    cpio = subprocess.check_output(['cpio', '-o', '-H', 'newc', '--reproducible', '--quiet'],
                                   cwd=marker_dir, input=b'a50-marker\n')
    rd = subprocess.check_output(['gzip', '-9', '-n'], input=cpio)
    kernel = image.read_bytes()
    header = bytearray(data[:page])
    struct.pack_into('<I', header, 8, len(kernel))
    struct.pack_into('<I', header, 16, len(rd))
    align = lambda blob: blob + b'\0' * (-len(blob) % page)
    result = bytes(header) + align(kernel) + align(rd)
    if len(result) > 57671680:
        raise RuntimeError('BOOT image exceeds partition size')
    output.write_bytes(result)


def build(work, listing, jobs):
    ack = work / 'ack'
    kernel = ack / 'common'
    clang = ack / 'prebuilts/clang/host/linux-x86/clang-r584948c'
    rust = ack / 'prebuilts/rust-toolchain/linux-x86/1.91.1.p3'
    out = work / 'out'
    out.mkdir(exist_ok=True)
    shim = work / 'shim'
    shim.mkdir(exist_ok=True)
    if not (shim / 'bc').exists():
        (shim / 'bc').symlink_to(ack / 'prebuilts/build-tools/linux-x86/bin/gavinhoward-bc')
    env = os.environ.copy()
    # Do not let caller build identity or Kbuild overrides change the snapshot.
    for key in ('LOCALVERSION', 'KCONFIG_ALLCONFIG', 'KCONFIG_CONFIG', 'KBUILD_OUTPUT',
                'KCFLAGS', 'KCPPFLAGS', 'KRUSTFLAGS', 'KBUILD_EXTRA_SYMBOLS'):
        env.pop(key, None)
    env.update(PATH=os.pathsep.join(map(str, [shim, clang / 'bin',
        ack / 'prebuilts/kernel-build-tools/linux_musl-x86/bin',
        ack / 'prebuilts/build-tools/linux-x86/bin'])) + os.pathsep + env['PATH'],
        LIBCLANG_PATH=str(clang / 'lib'), KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026',
        KBUILD_BUILD_USER='a50', KBUILD_BUILD_HOST='firstlight',
        KBUILD_BUILD_VERSION='1', SOURCE_DATE_EPOCH='1793750400')
    expected = (SNAPSHOT / 'config').read_text().replace('@INITRAMFS@', str(listing))
    (out / '.config').write_text(expected)
    make = ['make', '-C', kernel, f'-j{jobs}', 'ARCH=arm64', 'LLVM=1', f'O={out}',
            f'RUSTC={rust / "bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(*make, 'olddefconfig', env=env)
    if (out / '.config').read_text() != expected:
        raise RuntimeError('olddefconfig changed the locked config; inspect out/.config.old')
    run('python3', '-I', REPO / 'tools/m52/guard_unittest.py', kernel, '0x1c8700', '0xee42ff')
    run('python3', '-I', REPO / 'tools/m53/sense_unittest.py', kernel)
    run(*make, 'Image', 'exynos/exynos9610-a50-sysmmu.dtb', env=env)
    verify(out / 'usr/initramfs_data.cpio', LOCK['expected']['initramfs_data.cpio'])
    dtb = out / 'arch/arm64/boot/dts/exynos/exynos9610-a50-sysmmu.dtb'
    verify(dtb, LOCK['expected']['dtb'])
    image = out / 'arch/arm64/boot/Image'
    pack_boot(work / 'assets/boot-public.img', image, work / 'boot.img', work)
    outputs = [image, dtb, out / '.config', out / 'usr/initramfs_data.cpio', work / 'boot.img']
    manifest = {'kernel_tree': LOCK['kernel_tree'], 'files': {
        str(p.relative_to(work)): {'sha256': sha(p), 'size': p.stat().st_size} for p in outputs}}
    (work / 'build-results.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=REPO / 'src/reproduce-m6')
    parser.add_argument('--cache', type=Path, help='optional existing ACK workspace containing pinned public git objects')
    parser.add_argument('--assets', type=Path, help='optional cache of the two hash-verified downloads')
    parser.add_argument('--jobs', type=int, default=min(16, os.cpu_count() or 1))
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    work = args.work.resolve()
    if any(c.isspace() for c in str(work) + str(REPO)):
        parser.error('Kbuild/initramfs list paths must not contain whitespace')
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    for path, digest in LOCK['tracked_inputs'].items():
        verify(REPO / path, digest)
    work.mkdir(parents=True, exist_ok=True)
    for project in LOCK['projects']:
        prepare_project(project, work, args.cache.resolve() if args.cache else None)
    assets = download_assets(work, args.assets.resolve() if args.assets else None)
    listing = prepare_ramdisk(work, assets)
    if not args.prepare_only:
        build(work, listing, args.jobs)


if __name__ == '__main__':
    main()

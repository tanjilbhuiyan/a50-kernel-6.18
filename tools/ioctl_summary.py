#!/usr/bin/env python3
"""Summarise strace ioctl captures (M1.3) into per-subsystem contract tables.

Usage: python3 -I tools/ioctl_summary.py RAW_DIR KERNEL_TREE OUT_DIR

RAW_DIR   directory with files named  cap-<scenario>-<host|cont>-<pid>-<comm>.txt
          (made by tools/cap_ioctl.sh; `strace -f -y -e trace=ioctl`)
KERNEL_TREE  kernel source used to resolve ioctl names to numbers (the 4.14 baseline tree)
OUT_DIR   one <subsystem>.md per subsystem, plus summary.tsv

Numbers: `_IOC(dir, type, nr, size)` is converted with the asm-generic layout
(arm64: nr 8 bits, type 8 bits, size 14 bits, dir 2 bits at 30). Names are
resolved by compiling a tiny C program against the tree's uapi headers; names
the headers do not define stay "unresolved" (never guessed).
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

LINE = re.compile(r'ioctl\((\d+)<([^>]*)>,\s*(_IOC\([^)]*\)|[A-Za-z_][A-Za-z_0-9]*|0x[0-9a-fA-F]+)(?:,\s*([^)]*))?\)\s*=\s*(-?\d+|\?)')
IOCARG = re.compile(r'_IOC\(([^,]*),\s*(0x[0-9a-f]+|\d+|\'.\'),\s*(0x[0-9a-f]+|\d+),\s*(0x[0-9a-f]+|\d+)\)')
SUBSYS = [
    ('mali', r'/dev/mali'),
    ('ion', r'(/dev/ion|anon_inode:(dmabuf|sync_file))'),
    ('display', r'/dev/(graphics/fb|fb\d|g2d|fimg2d|dri|video|v4l)'),
    ('audio', r'/dev/(snd/|seiren)'),
    ('wifi_bt', r'/dev/(scsc|mx_|mxlog)'),
    ('modem', r'/dev/(umts|ipc|smd|drb|ramdump|gnss)'),
    ('sensors', r'/dev/(ssp|nanohub)'),
    ('tee', r'/dev/(tzdev|mobicore)'),
    ('input', r'/dev/input'),
    ('binder', r'/dev/(hw|vnd)?binder'),
    ('net', r'socket:'),
]


def subsys(node):
    for name, pat in SUBSYS:
        if re.search(pat, node):
            return name
    return 'other'


def ioc_value(arg):
    m = IOCARG.match(arg)
    if not m:
        return None
    d, t, nr, sz = m.groups()
    dirs = 0
    if 'READ' in d:
        dirs |= 2
    if 'WRITE' in d:
        dirs |= 1
    if t.startswith("'"):
        t = ord(t[1])
    else:
        t = int(t, 0)
    return (dirs << 30) | (int(sz, 0) << 16) | (t << 8) | int(nr, 0), dirs, t, int(nr, 0), int(sz, 0)


VENDOR_HEADERS = [
    'drivers/gpu/arm/b_r26p0/mali_kbase_ioctl.h',
    'drivers/gpu/arm/b_r26p0/jm/mali_kbase_jm_ioctl.h',
    'drivers/staging/android/uapi/ion.h',
    'include/uapi/linux/dma-buf.h',
    'include/uapi/linux/sync_file.h',
    'drivers/gpu/exynos/g2d/g2d_uapi.h',
    'drivers/video/fbdev/exynos/dpu20/decon.h',
    'include/uapi/linux/fb.h',
    'drivers/misc/modem_v1/modem_prj.h',
    'include/uapi/sound/asound.h',
    'fs/f2fs/f2fs.h',
]
DEFINE = re.compile(r"#define\s+(\w+)\s*(?:\\\n)?\s*_IO(?:WR|R|W)?\(\s*([^,\s]+)\s*,\s*(0x[0-9a-fA-F]+|\d+)")
TYPEDEF = re.compile(r"#define\s+(\w+)\s+(0x[0-9a-fA-F]+|'.'|\d+)\s*$", re.M)


def vendor_map(tree):
    """(ioctl type, nr) -> [macro names] from the baseline kernel's own headers.
    Type macros (e.g. KBASE_IOCTL_TYPE) are shared across the listed headers."""
    texts = []
    for h in VENDOR_HEADERS:
        try:
            texts.append(open(os.path.join(tree, h), errors='replace').read())
        except OSError:
            continue
    types = {}
    for txt in texts:
        types.update({m.group(1): m.group(2) for m in TYPEDEF.finditer(txt)})
    out = collections.defaultdict(list)
    for txt in texts:
        for m in DEFINE.finditer(txt):
            name, t, nr = m.groups()
            t = types.get(t, t)
            try:
                tv = ord(t[1]) if t.startswith("'") else int(t, 0)
            except ValueError:
                continue
            out[(tv, int(nr, 0))].append(name)
    return out


def resolve_names(names, tree):
    """Ask gcc for the value of each ioctl macro found in the uapi headers.
    One compile per name, so a macro that needs a missing header only loses itself."""
    inc = ['-I', f'{tree}/include/uapi', '-I', f'{tree}/arch/arm64/include/uapi',
           '-I', f'{tree}/include', '-I', f'{tree}/arch/arm64/include',
           '-I', f'{tree}/drivers/staging/android/uapi']
    heads = ['linux/ioctl.h', 'sound/asound.h', 'linux/android/binder.h', 'linux/fb.h',
             'linux/videodev2.h', 'linux/input.h', 'linux/sockios.h', 'linux/wireless.h',
             'asm/termbits.h', 'asm/ioctls.h', 'linux/sync_file.h', 'linux/dma-buf.h', 'ion.h', 'linux/fs.h']
    pre = ['#include <sys/types.h>', '#include <stdio.h>']
    pre += [f'#if __has_include(<{h}>)\n#include <{h}>\n#endif' for h in heads]
    vals, errs = {}, []
    with tempfile.TemporaryDirectory() as td:
        for n in sorted(names):
            c, exe = os.path.join(td, 'r.c'), os.path.join(td, 'r')
            open(c, 'w').write('\n'.join(pre) + f'\n#ifdef {n}\nint main(void){{printf("%lx\\n",(unsigned long)({n}));return 0;}}\n#else\n#error undefined\n#endif\n')
            r = subprocess.run(['gcc', '-w'] + inc + [c, '-o', exe], capture_output=True, text=True)
            if r.returncode:
                errs.append(n)
                continue
            out = subprocess.run([exe], capture_output=True, text=True).stdout.strip()
            if out:
                vals[n] = int(out, 16)
    return vals, ('not resolvable: ' + ' '.join(errs)) if errs else ''


def main():
    raw, tree, outd = sys.argv[1:4]
    os.makedirs(outd, exist_ok=True)
    agg = collections.defaultdict(lambda: [0, collections.Counter(), ''])
    for fn in sorted(os.listdir(raw)):
        m = re.match(r'cap-(.+?)-(host|cont)-(\d+)-(.+)\.txt$', fn)
        if not m:
            continue
        scen, where, pid, comm = m.groups()
        comm = comm.rstrip('_')
        for line in open(os.path.join(raw, fn), errors='replace'):
            mm = LINE.search(line)
            if not mm:
                continue
            fd, node, req, arg, ret = mm.groups()
            key = (subsys(node), node, comm, where, scen, req)
            a = agg[key]
            a[0] += 1
            a[1][ret] += 1
            if not a[2]:
                a[2] = (arg or '').strip()[:60]
    names = {k[5] for k in agg if not k[5].startswith(('_IOC', '0x'))}
    vals, err = resolve_names(names, tree)
    vmap = vendor_map(tree)
    rows = []
    for (ss, node, comm, where, scen, req), (cnt, rets, sample) in agg.items():
        if req.startswith('_IOC'):
            v = ioc_value(req)
            hexv, desc = (f'0x{v[0]:08x}', f'dir={v[1]} type=0x{v[2]:02x} nr={v[3]} size={v[4]}') if v else ('?', req)
            name = req
            if v and vmap.get((v[2], v[3])):
                name = '/'.join(vmap[(v[2], v[3])])
        elif req.startswith('0x'):
            hexv, desc, name = req, '', req
        else:
            v = vals.get(req)
            name = req
            hexv = f'0x{v:08x}' if v is not None else 'unresolved'
            desc = ''
            if v is not None:
                desc = f'dir={v >> 30} type=0x{(v >> 8) & 0xff:02x} nr={v & 0xff} size={(v >> 16) & 0x3fff}'
        rows.append((ss, node, comm, where, scen, name, hexv, desc, cnt,
                     ','.join(f'{r}x{c}' for r, c in rets.most_common(3))))
    rows.sort()
    with open(os.path.join(outd, 'summary.tsv'), 'w') as f:
        f.write('subsystem\tnode\tprocess\twhere\tscenario\trequest\thex\tdecoded\tcount\tretvals\n')
        for r in rows:
            f.write('\t'.join(map(str, r)) + '\n')
    by = collections.defaultdict(list)
    for r in rows:
        by[r[0]].append(r)
    for ss, rs in by.items():
        with open(os.path.join(outd, f'{ss}.md'), 'w') as f:
            f.write(f'# Observed ioctls: {ss}\n\nGenerated by tools/ioctl_summary.py from reference/contract/raw. '
                    'Only what the captured scenarios exercised; absence means "not observed", not "unused".\n\n'
                    'CAVEAT: hex values for NAMED requests come from the 64-bit 4.14 uapi headers. Processes that run in 32-bit mode '
                    '(e.g. the Android audio HAL, see strace "runs in 32 bit mode") send compat-sized numbers; the kernel must keep its compat_ioctl paths.\n\n'
                    '| node | process | where | scenario | request | hex | decoded | calls | ret |\n|---|---|---|---|---|---|---|---|---|\n')
            for r in rs:
                f.write('| {} | {} | {} | {} | {} | {} | {} | {} | {} |\n'.format(
                    r[1], r[2], r[3], r[4], r[5].replace('|', '+'), r[6], r[7], r[8], r[9].replace('|', '+')))
    # always emit the subsystems the contract needs, even when nothing was observed
    for ss in ('mali', 'ion', 'display', 'audio', 'wifi_bt', 'modem'):
        if ss not in by:
            with open(os.path.join(outd, f'{ss}.md'), 'w') as f:
                f.write(f'# Observed ioctls: {ss}\n\nNo ioctls were observed on this subsystem\'s device nodes in the captured scenarios '
                        '(this means "not observed", not "not needed"; see README.md).\n')
    print('rows', len(rows), 'subsystems', sorted(by), '| names', len(names), 'resolved', len(vals),
          'unresolved', sorted(names - set(vals)))
    if err:
        print('gcc error tail:', err)


if __name__ == '__main__':
    main()

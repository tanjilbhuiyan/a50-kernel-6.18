#!/usr/bin/env python3
"""Reproduce host evidence for M7.4; proprietary disassembly stays in src/."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LLVM = ROOT / 'src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin'
PRIVATE = ROOT / 'src/m74/audit'
PRIVATE.mkdir(parents=True, exist_ok=True)
inputs = {}


def record(name):
    path = ROOT / name
    data = path.read_bytes()
    inputs[name] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    return data


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout


vendor = ROOT / 'src/m71/vendor'
for line in (vendor / 'SHA256SUMS').read_text().splitlines():
    expected, name = line.split()
    rel = str((vendor / name).relative_to(ROOT))
    record(rel)
    assert inputs[rel]['sha256'] == expected, rel

functions = {}
for abi in ('lib64', 'lib'):
    for library in ('libacryl.so', 'libexynosdisplay.so'):
        path = vendor / abi / library
        args = [str(LLVM / 'llvm-objdump'), '--demangle', '-d']
        if abi == 'lib':
            args += ['--triple=thumbv7-linux-gnueabi']
        (PRIVATE / f'{abi}-{library}.disasm').write_text(run(args + [str(path)]))
        symbols = run(['readelf', '-W', '--dyn-syms', str(path)])
        symbols = run(['c++filt'], input=symbols)
        selected = {}
        for line in symbols.splitlines():
            match = re.match(r'\s*\d+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+\S+\s+\S+\s+(\S+)\s+(.+)', line)
            if not match or match[3] == 'UND':
                continue
            name = match[4]
            if not any(x in name for x in (
                'AcrylicDevice::open(', 'AcrylicDevice::ioctl(',
                'AcrylicCompositorG2D9810::AcrylicCompositorG2D9810(',
                'AcrylicCompositorG2D9810::ioctlG2D(',
                'AcrylicCompositorG2D9810::executeG2D(',
                'AcrylicFactory::createAcrylic(', 'Acrylic::createInstance(',
                'ExynosMPP::ExynosMPP(', 'ExynosMPP::doPostProcessing(',
                'ExynosDisplay::doExynosComposition(')):
                continue
            address = int(match[1], 16)
            selected[name] = {'symbol_address': hex(address),
                              'code_address': hex(address & ~1 if abi == 'lib' else address),
                              'size': int(match[2])}
        assert selected, path
        functions[f'{abi}/{library}'] = selected

config = record('src/m73/g2g-as-built/.config').decode()
flags = [f'# CONFIG_{name} is not set' for name in ('MODULES', 'MEDIA_SUPPORT', 'DRM')]
assert all(flag in config for flag in flags)
assert 'CONFIG_EXYNOS_GRAPHICS_G2D=y' not in config
elf = 'src/m73/g2g-as-built/vmlinux'
record(elf)
g2d_symbols = []
for line in run([str(LLVM / 'llvm-nm'), '--defined-only', str(ROOT / elf)]).splitlines():
    address, kind, name = line.split(maxsplit=2)
    if 'g2d' in name.lower() or 'fimg2d' in name.lower():
        g2d_symbols.append({'kind': kind, 'name': name})
# Clock tables are present. No G2D execution/registration functions are linked.
assert g2d_symbols and all(s['kind'].lower() not in ('t', 'w') for s in g2d_symbols)

runtime = {}
for stage in ('g2f', 'g2g', 'g2h'):
    prefix = f'reference/m73-gpu/{stage}'
    dump = record(prefix + '-dump.txt').decode()
    stats = record(prefix + '-stats.txt').decode()
    result = json.loads(record(prefix + '-results.json'))
    frames = [line for line in dump.splitlines() if 'late: frames' in line][-1]
    counters = {k: int(v, 0) for k, v in re.findall(r'(\w+)=(0x[0-9a-f]+|\d+)', frames)}
    layers = [line for line in stats.splitlines() if line.startswith('layers0=')][-1]
    layers = {k: int(v) for k, v in re.findall(r'(layers\d)=(\d+)', layers)}
    last_stats = [line for line in stats.splitlines() if line.startswith('fence_ctx=')][-1]
    sampled_configs = int(re.search(r'\bwin_configs=(\d+)', last_stats)[1])
    assert layers['layers1'] == sampled_configs <= counters['win_configs']
    assert all(v == 0 for k, v in layers.items() if k != 'layers1')
    assert counters['copied'] + counters['scanned'] == counters['win_configs']
    runtime[stage] = {'late_counters': counters, 'final_sampled_layer_counts': layers,
                      'final_sampled_win_configs': sampled_configs,
                      'postflight_pass': result['postflight_pass'],
                      'baseline_fsck': result['baseline_fsck']}

for name in (
    'src/m71/vendor/SHA256SUMS',
    'reference/contract/README.md', 'reference/contract/display.md',
    'reference/contract/openers-raw.txt', 'reference/contract/summary.tsv',
    'log/2026-11-14-M7.1-display-gpu-audit.md',
    'src/samsung-a50-4.14-aa17rf2/drivers/gpu/exynos/g2d/g2d_drv.c',
    'src/samsung-a50-4.14-aa17rf2/drivers/gpu/exynos/g2d/g2d_uapi.h',
    'src/samsung-a50-4.14-aa17rf2/drivers/gpu/exynos/g2d/Kconfig',
    'src/samsung-a50-4.14-aa17rf2/drivers/gpu/exynos/g2d/Makefile',
    'src/m73/g2g-kernel/drivers/video/fbdev/a50-decon.c',
    'src/m73/boot-g2g.img', 'src/m73/dt-g1.img',
    'reference/m73-gpu/g2h-run.txt', 'reference/m73-gpu/g2h-live.txt',
    'tools/m74/audit_g2d.py'):
    record(name)

print(json.dumps({
    'task': 'M7.4 G2D requirement decision',
    'method': 'host-only source/binary/build and saved runtime evidence; no phone access',
    'symbol_note': '32-bit ELF symbols carry Thumb bit; code_address clears it',
    'consumer_functions': functions,
    'build_disabled': flags,
    'linked_g2d_named_symbols': g2d_symbols,
    'linked_g2d_named_text_symbols': 0,
    'runtime': runtime,
    'interpretation': 'See decision.md for reviewed branch behavior and scoped decision; these counters do not trace G2D ioctls.',
    'inputs': inputs,
}, indent=2))

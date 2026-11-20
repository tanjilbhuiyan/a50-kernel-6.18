#!/usr/bin/env python3
"""Build the experimental M10.2 A1 audio-DSP stack from pinned public inputs.

This reuses the stable public build implementation with a separate source/config
lock and output directory. No phone operations; no private backup is required.
"""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    spec = importlib.util.spec_from_file_location('a50_m10_a1_public_builder', ROOT / 'tools/reproduce_m8.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.SNAPSHOT = ROOT / 'reproduce/m10-a1'
    builder.LOCK = json.loads((builder.SNAPSHOT / 'sources.lock.json').read_text())
    builder.__doc__ = __doc__
    if not any(a == '--work' or a.startswith('--work=') for a in sys.argv[1:]):
        sys.argv.extend(('--work', str(ROOT / 'src/reproduce-m10-a1')))
    builder.main()


if __name__ == '__main__':
    main()

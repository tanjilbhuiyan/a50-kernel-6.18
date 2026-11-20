#!/usr/bin/env python3
"""Build M10.2 A2b: the A1 build (tools/m10/build_a1.py, same seed, checks and outputs) on a50-m10-a2b-test, plus
CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50 (the ABOX sound card) and CONFIG_SND_DYNAMIC_MINORS (stock has it; the card's
13 PCM devices exceed the static minor layout, A2r -EBUSY). Usage: build_a2b.py TAG. Never flashes."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ.setdefault('A50_KERNEL', 'src/m10/a2-kernel')
os.environ.setdefault('A50_BRANCH', 'a50-m10-a2b-test')
import build_a1  # noqa: E402

build_a1.AUDIO['CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50'] = 'y'
build_a1.AUDIO['CONFIG_SND_DYNAMIC_MINORS'] = 'y'
build_a1.main()

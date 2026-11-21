#!/usr/bin/env python3
"""Build M10.3 B1: the A1 build (tools/m10/build_a1.py, same seed, checks and outputs) on a50-m10-b1-test, plus
CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50 (the ABOX sound card) and CONFIG_SND_DYNAMIC_MINORS (stock has it; the card's
13 PCM devices exceed the static minor layout, A2r -EBUSY). Usage: build_b1.py TAG (A2c plus the RT5665 codec on UAIF0: card widgets/routing, codec node, I2S pins; SND_SOC_RT5665 is selected by the card). Never flashes."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ.setdefault('A50_KERNEL', 'src/m10/a2-kernel')
os.environ.setdefault('A50_BRANCH', 'a50-m10-b1-test')
import build_a1  # noqa: E402

build_a1.AUDIO['CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50'] = 'y'
build_a1.AUDIO['CONFIG_SND_DYNAMIC_MINORS'] = 'y'
build_a1.main()

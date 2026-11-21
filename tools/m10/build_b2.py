#!/usr/bin/env python3
"""Build B2a, the TFA9872 probe-only image on the diagnostic B1 test base.

Adds amplifier/HSI2C/synchronized IPC to B1. Default probe_only is true;
no EFS/calibration helper, calibration programming, or speaker playback.
Uses the established seed, unchanged I5 runtime, guard checks and packer.
Usage: python3 -I tools/m10/build_b2.py b2a
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ.setdefault("A50_KERNEL", "src/m10/a2-kernel")
os.environ.setdefault("A50_BRANCH", "a50-m10-b2a-test")
import build_a1  # noqa: E402

build_a1.AUDIO.update({
    "CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50": "y",
    "CONFIG_SND_DYNAMIC_MINORS": "y",
    "CONFIG_SND_SOC_TFA9872": "y",
    "CONFIG_SEC_SND_SYNCHRONIZED_IPC": "y",
    "CONFIG_I2C_EXYNOS5": "y",
})
build_a1.main()

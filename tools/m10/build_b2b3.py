#!/usr/bin/env python3
"""Build M10.3 B2b3: the B2b image (build_b2.py) plus CONFIG_HIGH_RES_TIMERS=y, nothing else.

B2b2's ABOX firmware log showed IPC messages handled one per 4 ms tick: abox_process_ipc() sleeps
usleep_range(10, 100) after each message, which rounds up to a full tick (HZ=250) without high-resolution
timers. Stock 4.14 and gki_defconfig both enable them; CPU idle is off on 6.18, so the arch timer never stops.
Usage: A50_BRANCH=a50-m10-b2b3-test python3 tools/m10/build_b2b3.py b2b3
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ.setdefault("A50_KERNEL", "src/m10/a2-kernel")
os.environ.setdefault("A50_BRANCH", "a50-m10-b2b3-test")
import build_a1  # noqa: E402

build_a1.AUDIO.update({
    "CONFIG_SND_SOC_SAMSUNG_EXYNOS9610_A50": "y",
    "CONFIG_SND_DYNAMIC_MINORS": "y",
    "CONFIG_SND_SOC_TFA9872": "y",
    "CONFIG_SEC_SND_SYNCHRONIZED_IPC": "y",
    "CONFIG_I2C_EXYNOS5": "y",
    "CONFIG_HIGH_RES_TIMERS": "y",
    # Kconfig consequences of HIGH_RES_TIMERS (select TICK_ONESHOT; SCHED_HRTICK def_bool), listed so the guard checks them.
    "CONFIG_TICK_ONESHOT": "y",
    "CONFIG_SCHED_HRTICK": "y",
})
build_a1.main()

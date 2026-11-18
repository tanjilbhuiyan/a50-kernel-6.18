# ADR-0007 — Leave CMU_PERI to the bootloader; describe PERI consumer clocks as fixed clocks until M12

Status: **Accepted** (2026-11-18, owner: "follow recomendation, option a")

## Context
M8.1 (`log/2026-11-18-M8.1-i2c.md`) measured and bisected the M4.4 I2C freeze:
- R1: the bootloader leaves CMU_PERI in global automatic gating (option register `0x30000000`), every read PERI gate on
  (value 1, not manual) and every I2C Q-channel with CLOCK_REQ=1.
- T1: with CMU_PERI unregistered and the I2C controller on a fixed clock at the measured PERI bus rate (66.625 MHz, the
  stock parent of `GATE_I2C_n_QCH`), `i2c-s3c2410` probes bus 4 and transfers complete (T2) without faults.
- T3: changing only the clock provider to the 6.18 CMU_PERI driver (0x8000 window, manual gate mode) and the real
  `I2C_4_PCLK` reproduces the freeze: hard lockup of the CPU running the initcalls, caught by the buddy detector.
The driver's automatic mode (0x10000 window) would write option bits never verified on this SoC (`0xF1000000`).
CPU DVFS is already deferred for a similar reason (ACPM, plan M4), and the GPU already uses a fixed boot clock (M7.3).

## Decision
Until M12 (power) or a replacing ADR:
1. The A50 device tree does not register `samsung,exynos9610-cmu-peri`. CMU_PERI stays exactly as the bootloader
   configures it; no 6.18 code writes CMU_PERI registers.
2. Consumers of CMU_PERI clocks (the I2C controllers first) reference a `fixed-clock` that describes the measured
   bootloader rate. Their `clk_enable`/`clk_disable` calls therefore never gate the hardware.
3. Each such fixed clock cites the measurement it describes; a new consumer needs its rate measured first.

## Consequences
- I2C works now on the stock pins (M8.2 touch, M8.3 keys and M4.4's S2MPB03 can proceed).
- PERI clocks cannot be gated or rate-changed by Linux; power saving and suspend/resume of PERI blocks are not
  available. M12's DoD gains: register CMU_PERI (validated automatic or manual mode), move PERI consumers to real clocks,
  and remove these fixed clocks.
- If the bootloader ever leaves a needed PERI gate off, the consumer will not work; R1's register read is the check.

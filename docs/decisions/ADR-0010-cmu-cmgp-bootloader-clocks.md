# ADR-0010 — Leave CMU_CMGP to the bootloader; describe the TFA9872 HSI2C3 clocks as fixed clocks until M12

Status: **Accepted** (2026-11-26, owner: "ADR, as CMU_PERI (Recommended)")

## Context
The TFA9872 speaker amplifier sits on HSI2C3 (`11d10000`, SPI 273, CMGP pins gpm2-0/gpm3-0 function 3). In stock
4.14 its clocks come from CMU_CMGP (`11c00000`), fed by the APM bus (`11800000`) from TOP SHARED PLLs.
- B2C (`reference/m10-audio/b2c-results.json`, `log/2026-11-22-M10.3-tfa9872.md`) read the CMGP, APM and TOP
  registers read-only on the unchanged B1 image at 80, 150 and 390 s. All three snapshots were identical: CMGP I2C
  mux 1, divider 1 (÷2), giving IPCLK **99 937 500 Hz** and PCLK **199 875 000 Hz** (CCF parent `dout_cmu_apm_bus`).
  The bootloader leaves the HSI2C3 IPCLK/PCLK gates and the APM->CMGP bus gate enabled.
- Since B2a the A50 DT describes these two rates as `fixed-clock` nodes (`cmgp_i2c_bootclk`, `cmgp_bus_bootclk`). No
  6.18 code writes CMU_CMGP or the APM CMU. On that basis the TFA9872 probed (B2a) and loaded its container. It kept
  the factory calibration through every boot (B2a-B2m), and the speaker tone was audible to the owner (B2b5,
  2026-11-26).
- ADR-0007 made the same choice for CMU_PERI after the 6.18 CMU_PERI driver froze a CPU in manual gate mode (M8.1 T3).
  6.18 has no Exynos 9610 CMU_CMGP driver; writing one means verifying gate modes and Q-channels on this SoC, with
  the same class of risk, for no functional gain in M10.

## Decision
Until M12 (power) or a replacing ADR:
1. The A50 device tree does not register a CMU_CMGP (or APM CMU) clock controller. CMU_CMGP stays exactly as the
   bootloader configures it; no 6.18 code writes CMU_CMGP or APM CMU registers.
2. HSI2C3 references the two measured `fixed-clock` nodes (99.9375 MHz `hsi2c`, 199.875 MHz `hsi2c_pclk`). Its
   `clk_enable`/`clk_disable` calls therefore never gate the hardware.
3. Any other CMGP consumer needs its rate measured first (as B2C did) and cites the measurement, as in ADR-0007.

## Consequences
- M10.3's last open item is closed: the CMGP clocks are an accepted deferral, not a prototype.
- CMGP clocks cannot be gated or rate-changed by Linux, so HSI2C3 cannot save power or suspend through its clocks.
  M12's DoD gains: register CMU_CMGP (validated mode), move HSI2C3 to real clocks, and remove these fixed clocks.
- If the bootloader ever leaves a CMGP gate off, HSI2C3 will not work. B2C's register read is the check
  (`APM_GATE_CMGP_BUS`, `CMGP_GATE_I2C00_IPCLK/PCLK`, `CMGP_GATE_I2C_CLK`).

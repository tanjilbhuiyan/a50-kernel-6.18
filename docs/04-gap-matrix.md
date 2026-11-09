# 04 — Driver gap matrix (A50 → Linux 6.18)

Generated 2026-11-01 by `tools/gap_matrix.py` from the **live device tree**
of this phone (`reference/live-dt-compatibles.tsv`, 318 nodes, 271 enabled)
against `src/samsung-a50-4.14-aa17rf2` and `src/linux-6.18.60`.
Raw per-node data: `reference/gap-matrix-6.18.tsv`. Re-run after any change.

Categories: **A** exact compatible supported in 6.18 · **B** same IP family
has a 6.18 driver (add SoC data/compatible) · **C** Samsung-only, forward-port
or replace · **D** no driver needed (CPU/memory/data/Android/firmware nodes).

Totals: A 40 · B 18 · C 150 · D 63 (nodes). C = 90 distinct driver files.
Note: the automatic match is by file path; drivers that moved/renamed in
mainline were corrected by hand below (marked ✱).

Samsung delta vs 4.14.194 (`reference/measurements/`): 8,761 files,
+3.16 M lines total, but most is other models (7 Mali DDKs, other sensors,
TV tuners). Only the drivers below matter.

## Curated by subsystem

| Subsystem | A50 driver in 4.14 | 6.18 status | Strategy | Milestone |
|---|---|---|---|---|
| CPU, PSCI, GIC, arch timer | arm generic | A | DT only | M2 |
| Clocks (CMU) | `clk/samsung/clk-exynos9610.c` (CAL-based) | none in 6.18; partial series on LKML (Chimac v3, Jul 2026, excludes SHUB/MIF/ISP/VIPX/MFC); `clk-exynos850.c` as template | adopt LKML series, extend for needed CMUs | M2 |
| Pinctrl | `pinctrl/samsung` + `exynos9610` data | B; 9610 data merged in mainline **after** 6.18 | backport the mainline 9610 pinctrl patch | M2 |
| UART / USI v2 | `tty/serial/samsung.c`, `soc/samsung/usi_v2.c` | ✱B `samsung_tty.c`, `exynos-usi.c` (exynos850) | add 9610 data | M2 (no physical UART; low priority) |
| PMU, chipid, sysreg | `soc/samsung/exynos-pmu.c`, chipid | B (chipid 9610 in mainline master) | add 9610 data | M2 |
| Reserved memory, ramoops, simplefb | debug-snapshot | A (generic) | new DT nodes (`docs/03` §4) | M1/M2 |
| UFS storage | `scsi/ufs/ufs-exynos.c` | ✱B `ufs/host/ufs-exynos.c` | add 9610 variant (PHY/sysreg data) | M3 |
| SD card (DW-MMC) | `mmc/host/dw_mmc-exynos.c` | B | add data | later |
| USB DRD controller | `usb/dwc3/dwc3-exynos.c` | B (exynos850 data exists) | add 9610 data | M3 |
| USB PHY | `phy/samsung/phy-exynos-usbdrd.c` | ✱B `phy-exynos5-usbdrd.c` | add 9610 PHY data | M3 |
| USB-C / MUIC / charger | `usb/typec/sm5713`, `mfd/sm5713_core.c`, `battery_v2/sec_battery.c` | C | port minimal sm5713 MFD + typec role/VBUS detect; replace sec_battery with power-supply class driver | M3 (detect), M12 (battery) |
| IOMMU (SysMMU) | `iommu/exynos-iommu.c` | A (10 nodes) | DT check vs v7 SysMMU | M6 |
| DMA (PL330) | `dma/pl330.c` | A (AMBA match) | DT | M4 |
| I2C, PWM, keys, fixed regulators | mainline drivers | A (14/15 i2c) | DT | M4 |
| Speedy bus | `i2c/busses/i2c-exynos-speedy` | C | not needed: PMIC access is through ACPM (M3.6, plan change 2026-11-10) | M4 |
| PMIC s2mpu09 + s2mpb03 | `mfd/s2mpu09-core.c`, `regulator/s2mpb03.c` | C (mainline has s2mps/s2mpg family, `sec-i2c.c`, `sec-acpm.c`) | port as `sec-core` variant | M4 |
| ACPM (power firmware IPC) | `soc/samsung/acpm/*`, `cal-if/acpm_dvfs.c` | ✱B-ish: `firmware/samsung/exynos-acpm.c` (gs101) | adapt mainline ACPM to 9610 protocol | M4 |
| CPU DVFS / devfreq / cpuidle | `cal-if`, `devfreq/exynos`, `cpuidle-exynos64.c` | C (cpuidle → PSCI generic A) | cpufreq via ACPM DVFS; devfreq later | M4, M12 |
| Thermal (TMU) | `thermal/samsung/exynos_tmu.c` | B | add 9610 data | M4 |
| Power domains | `exynos-pd` (D, no driver match) | mainline `exynos-pm-domains` | DT + data | M4 |
| ION + heaps | `staging/android/ion` + `ion_fdt_exynos.c` | C (removed upstream) | port legacy ION ABI on top of dma-buf (contract §2a) | M6 |
| Display DECON/DPP/DSIM | `video/fbdev/exynos/dpu20/*` | C (mainline exynos DRM covers 5433/7 generation only) | forward-port dpu20 with its ioctl ABI (vendor HWC needs it) | M7 |
| Panel | `display-lcd_a50_common.dtsi` panel driver | C | port with dpu20 | M7 |
| GPU | Mali kbase r26p0 | C for vendor ABI (Panfrost supports G72 but not the vendor blob ABI) | port kbase r26p0 (ARM DDK) | M7 |
| G2D | `gpu/exynos/g2d` | C | port only if HWC requires it (contract capture) | M7 |
| Touch | `input/touchscreen/melfas/mss100` | C | port (small) | M8 |
| Hall, vibrator, LEDs (flash) | `input/misc/hall*.c`, `motor/sec_vib.c`, `leds-sm5713-fled.c` | C | port small drivers / use mainline equivalents | M8 |
| Wi-Fi + BT | SCSC `misc/samsung/scsc*`, `net/wireless/scsc` | C (93.5 k lines in net/wireless + core) | forward-port SCSC | M9 |
| Audio | ABOX `sound/soc/samsung/abox/*` (27 nodes), `codecs/tfa9872` | C | forward-port ABOX + TFA9872 | M10 |
| Modem + GNSS IPC | `misc/modem_v1`, `mcu_ipc`, `shm_ipc`, `gnss_if` | C | forward-port | M11 |
| Camera | fimc-is2 (4 sensors: 2x5, 4ha, gc5035, imx576; actuator dw9808; eeprom; flash) | C (very large) | stretch only | M13 |
| MFC video codec | `media/platform/exynos/mfc` | C (mainline s5p-mfc for older IP) | stretch | M13 |
| Sensor hub | `staging/nanohub/chub.c`, `sensorhub/tc3xxk.c` | C | stretch | M13 |
| Drop (not needed) | debug-snapshot, coresight, itmon, seclog, bcm_dbg, argos, abc_hub, nad, mst, tzdev, mobicore, fm radio, vipx, diskcipher/FMP, gud | — | do not port | — |

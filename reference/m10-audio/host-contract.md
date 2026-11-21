# M10.1 — stock audio contract, host-side evidence (2026-11-20)

Sources: `reference/stock-dt/dt.dtb.0.dts` (SoC DT), `reference/stock-dt/dtbo.5.dts` (board overlay, `dtbo_idx=5`,
`docs/01-device.md`), `reference/live-dt-compatibles.tsv`, `reference/baseline-build/config`,
`src/samsung-a50-4.14-aa17rf2` (stock source), `src/m92/clean-kernel` (6.18 + A50 stack), `reference/stock-vendor/*`.

## Components
| Part | Stock node | Bus / resources | Stock driver | 6.18 status |
|---|---|---|---|---|
| ABOX DSP | `abox@0x14A50000` `samsung,abox` | sfr 0x14a50000+0x10000, sysreg 0x14810000+0x3000, SRAM 0x14b00000+0x35000; IPC offsets tx 0x22000 / rx 0x22300; clocks pll/cpu/audif/bus; `iommus` → SysMMU 0x14920000 (IRQ 216, "ABox"); `abox_gic` 0x14af1000/0x14af2000 (IRQ 198); quirks "try to asrc off", "off on suspend", "scsc bt" | `sound/soc/samsung/abox/*` (~16.7k lines, 15 objects + synchronized IPC) | **port** |
| ABOX children | rdma×8, wdma×5, uaif×4, dsif, spdy, effect, vss, bt, synchronized-ipc, debug | — | same tree | port subset (see boundary) |
| Reserved memory | `abox_rmem@0xE9400000` 40 MiB | — | — | **already reserved `no-map` in the 6.18 DT** |
| Codec | `rt5665@1b` on `i2c@13890000` (DTBO) | IRQ, jack-detect src 2, DMIC2, in1/3/4 differential, regulators 1v8/3v3 | Samsung `rt5665.c` (6545 lines) | mainline `rt5665.c` (4868) exists |
| Amplifier | `tfa98xx@34` on `hsi2c@11D10000` (DTBO) | I2C only | NXP `tfa9872/*` (~17k lines) | **no mainline driver** (`tfa989x` covers 9890/9895/9897 only) |
| Machine | `sound` `samsung,exynos9610-audio` (DTBO), 19 DAI-link children, `xclkout` clock, routing HEADSETMIC/MAINMIC/SUBMIC ↔ MICBIAS1-3 | — | `vogue-rt5665.c` (1149) + `jack_rt5665_sysfs_cb.c` (`SND_SOC_SAMSUNG_VOGUE_RT5665=y`) | **port** |

Stock config: `SND_SOC_SAMSUNG_ABOX`, `SND_SOC_RT5665`, `SND_SOC_TFA9872`, `SND_SOC_SAMSUNG_VOGUE_RT5665`,
`SEC_SND_SYNCHRONIZED_IPC` all built in; no audio vendor modules. No VTS node. `SND_SOC_CS35L41=y` has no enabled node.

## Clocks and power on 6.18
The 6.18 `samsung,exynos9610-cmu.h` binding and `clk-exynos9610.c` already provide the ABOX/AUD clocks
(`CLK_FOUT_AUD_PLL`, `CLK_DOUT_CLK_AUD_{CPU,AUDIF,BUS,UAIF0-2,DSIF,FM}`, `CLK_GOUT_DISPAUD_ABOX_*`). CMU_DISPAUD is
already registered for the display (`exynos9610-a50-sysmmu.dts`, M3.3/M7) and DISPAUD stays powered. The ABOX SysMMU is
the same `samsung,exynos-sysmmu` form as the DPU SysMMU already used on 6.18.

## Firmware (stock `/vendor/firmware`, `reference/stock-vendor/firmware-list.txt`; hashes from the phone, step 2)
- ABOX core: `calliope_sram.bin` (32 540 B, `request_firmware_nowait`/`_direct`), `calliope_dram.bin` (2 061 736 B),
  `calliope_iva.bin` (57 728 B).
- ABOX extra binaries (`ext_bin@N` children): only `tfadsp.bin` (76 972 B) is `okay`; `AP_AUDIO_SLSI.bin`,
  `APBargeIn_AUDIO_SLSI.bin`, `APBiBF_AUDIO_SLSI.bin`, SoundBooster etc. are `disabled` in the DT.
- TFA: `Tfa9872.cnt` (7 645 B) loaded by the TFA driver. `tfadsp.bin` runs the TFA speaker-protection algorithm on ABOX
  (`abox_synchronized_ipc.c` links the TFA driver and ABOX).
- On 6.18 the firmware loader serves `/vendor/firmware` already (`firmware_class.path`, M9.2).

## ABOX dependencies on Samsung-only kernel infrastructure (grep of `abox/*.c`)
| Stock API | Use | 6.18 route (modern-first) |
|---|---|---|
| `exynos_smc` (8) | secure register access | `arm_smccc_smc` (as SCSC, M9.2) |
| `exynos_pmu_{read,write,update}` | ABOX power/reset in PMU | PMU syscon regmap (as SCSC) |
| `pm_qos_*` Samsung classes (26) | bus/CPU frequency floors | drop (no DVFS on 6.18 yet, M4/M12) |
| `exynos_sysmmu_*`, `iovmm_set_fault_handler`, `exynos_iovmm.h` | IOMMU mapping of DRAM/firmware | mainline IOMMU API (`iommu_map`, `iommu_set_fault_handler`) with exynos-iommu |
| `ion_alloc_dmabuf`, `dma-buf-container` | `abox_mmapfd` (MMAP/AAudio buffers) | `dma_alloc_*`/dma-buf heaps, or leave mmapfd out |
| `shm_ipc`, `modem_notifier` | `abox_vss` (voice call path via CP) | stub until M11 (modem) |
| `exynos_abox_panic_handler` | debug | drop |
| WLBT→ABOX mailbox (`scsc bt` quirk, `abox_bt`) | Bluetooth SCO through ABOX | defer (A2DP is native BlueZ, ADR-0008; HFP later) |

## Consumers
- HAL: 32-bit `audio.primary.exynos9610.so` via `android.hardware.audio.service`; standard ALSA PCM/CTL ioctls only
  (`reference/contract/audio.md`, M1.3), so 32-bit compat ALSA must stay enabled.
- Vendor init (`etc_init_init.exynos9610.rc`) chowns `/sys/devices/platform/14a50000.abox/{reset,service}`,
  `0.abox_debug/{gpr,calliope_sram,calliope_dram}`, `/sys/kernel/debug/abox/log-00`, `/sys/class/audio/earjack/*`,
  `/sys/class/nxp/tfa_cal/{status,rdc,temp}`; ueventd `/dev/seiren` (no driver in the stock tree builds it: grep finds
  no `seiren` under `sound/soc/samsung`). Missing nodes make those `chown`s fail harmlessly; whether the HAL needs them is
  checked in step 2.
- Mixer names: 37 control/widget names exist only in Samsung's `rt5665.c` (e.g. `STO1 ADC Left Capture Volume`,
  `Stereo1 DMIC Source`, `IF1_1 ADC TDM`, `TDM1 Data Mux`, `jack type`, `button type`) and 50 only in mainline (slot-
  split TDM/swap muxes, `MONOVOL Playback Volume`). Mainline also lacks the Samsung SAR-button, impedance and offset
  properties (`realtek,sar-*`, `imp_table`, `realtek,offset-comp*`, `realtek,regulator_*`). Whether the vendor
  `mixer_paths*.xml` uses the Samsung-only names decides mainline vs Samsung RT5665 (step 2).

## EFS finding (rule 5)
The stock TFA driver reads **and writes** speaker calibration in EFS from the kernel (`tfa_cal.c`: `filp_open` of
`/efs/nxp/rdc_cal` and `/efs/nxp/temp_cal`, `tfa_cal_write_file` with `O_CREAT|O_TRUNC`, folder creation). On 6.18 this
code is excluded: the kernel never opens EFS files, and `set_fs`-style kernel file I/O no longer exists. Using the
factory calibration values needs an owner decision (a read-only path like ADR-0009); until then the amplifier runs
with the container defaults. Risk to record: speaker protection without per-unit calibration.

# Stock runtime snapshot (step 2, 2026-11-20, read-only; `tools/m10/run_audio_contract.sh`)
Evidence `reference/m10-audio/stock-snapshot.txt`, vendor XMLs `reference/m10-audio/vendor-etc/`.
- Cards: `0 Exynos9610-Audio`, `1 abox_dump` (debug capture of 23 internal points). Card 0 PCMs: RDMA0-4, 6, 7
  playback (device 5 absent), WDMA0-4 capture. 367 controls on card 0.
- Firmware sha256: `calliope_sram.bin` 5b234d64…, `calliope_dram.bin` 43d473fd…, `calliope_iva.bin` e653f861…,
  `tfadsp.bin` 82977ab7…, `Tfa9872.cnt` f4231718… (full hashes in the snapshot).
- ABOX platform children as in the DT (uaif×4, dsif, spdy, rdma×8, wdma×5, effect, bt, vss, synchronized_ipc, debug)
  plus 25 `samsung-abox-dump.*`; sysfs `calliope_version`, `calliope_cmd`, `reset`, `reset_count`.
- `/dev/seiren` absent on stock: not part of the contract. `/sys/class/audio/earjack` present (Samsung jack class).
- HAL (`android.hardware.audio.service`, uid 1041) holds only `/dev/snd/controlC0` while idle; PCMs opened on demand.
- PulseAudio on stock: `module-droid-discover` → `module-droid-card-30`, sinks `sink.primary-out`, `sink.fast`;
  `a50-audio-route` and `a50-audio-hidl-compat` services (M0.4 userspace fix). Kernel boot audio lines had rotated out
  of the ring buffer (uptime 2.5 h); not needed for the boundary.
- Mixer paths: `mixer_paths.xml` + `mixer_gains.xml` use 146 controls: 78 `ABOX …`, 2 `BT …`, the rest codec/machine.
  Every codec control used exists in **mainline** `rt5665.c` (directly or widget + kcontrol), except `Disable NG2`
  (Samsung-only). Machine pin switches `HEADPHONE`, `HEADSETMIC`, `RECEIVER` come from `vogue-rt5665.c`.
  `Main Mic Switch`, `Sub Mic Switch`, `Headset Mic Switch` and 10 ABOX USB/RDMA6/WDMA0
  controls are referenced but absent on stock too (the HAL tolerates them). **Correction 2026-11-22:**
  `Debug Buffer Switch` is present on stock (numid 134), implemented by Samsung `sec_audio_debug.c`;
  the earlier claim that it was absent on stock was wrong. B1r2 enumerates 348 controls, covers 129/133
  HAL names that stock exposes; the four absent names are the two deferred BT SCO controls,
  `Debug Buffer Switch` and the known `Disable NG2`. See `b1r2-control-comparison.json`.

# Port boundary (modern-first)
1. **M10.2 ABOX core:** `abox.c` + `abox_gic`, `abox_rdma`, `abox_wdma`, `abox_if` (UAIF/DSIF/SPDY), `abox_effect`,
   `abox_util`, `abox_log`/`abox_dbg` (debugfs only), firmware via `request_firmware` (`calliope_sram/dram/iva`,
   `ext_bin` `tfadsp.bin`). Mainline APIs: exynos-iommu (DT SysMMU 0x14920000), CMU_DISPAUD clocks, PMU regmap,
   `arm_smccc_smc`, snd_soc 6.18 component API. Left out: Samsung PM QoS, `abox_vss` (stub, M11), `abox_bt` (SCO via
   WLBT mailbox, deferred), `abox_mmapfd`/ION (no MMAP streams), `abox_failsafe`, `abox_dump` card, panic hooks.
2. **M10.3 codec/amp/machine:** mainline `rt5665.c` + one small A50 patch only if `Disable NG2` proves needed (the HAL
   skips missing controls); Samsung jack/button SAR extras stay out (headset buttons later). `vogue-rt5665.c` machine
   driver ported (DAI links from the DTBO `sound` node, pin switches, MICBIAS routing, `xclkout`). TFA9872: port of the
   NXP driver without kernel EFS file I/O (container defaults), plus `abox_synchronized_ipc`. DT: add the DTBO-5 nodes
   (`rt5665@1b` on i2c@13890000, `tfa98xx@34` on hsi2c@11D10000, `sound`) to the 6.18 A50 DT (the 6.18 build uses a
   no-op DTBO).
3. **M10.4:** remove the ADR-0005 overlay and the `a50-audio-route` mask; PulseAudio `module-droid-discover` as stock.

# Boot-test plan (one variable each)
- A1: ABOX core only. Pass: firmware loaded, `calliope_version` readable, IPC alive, no SysMMU faults.
- A2: ABOX + DMA/UAIF components with a dummy machine card. Pass: card 0 PCMs match stock (RDMA0-4/6/7, WDMA0-4).
- B1: + RT5665 (mainline) + machine driver. Pass: codec probes, controls cover the 146 HAL names as stock does.
- B2: + TFA9872. Pass: amp probes, `Tfa9872.cnt` loaded; speaker tone via `tinyplay`/HAL path heard by the owner.
- M10.4: PulseAudio droid sink; `paplay`/`parecord` (S6) against the stock baseline (M0.5 mic defect on stock).

# Unresolved
- Speaker calibration: stock keeps per-unit TFA calibration in EFS (kernel read/write). 6.18 runs uncalibrated defaults
  until the owner decides (read-only path, new ADR). Volume should stay moderate in tests until then.
- Whether `abox_vss`'s absence breaks the HAL's call paths: checked in M11.

## Calibration policy correction (B2 preparation, 2026-11-22)
Stock `TFA Calibration` is readable and nonzero on this phone; its getter reads the amplifier's calibration mirror
(register F5). EFS reads are in `tfa_cal.c`'s status helper. Its EFS write code is compile-conditional;
`TFA_WRITE_CAL_TO_FILE` is commented out in the baseline Makefile, so earlier wording that the running stock
kernel writes calibration to EFS was too broad. Presence of write-capable source is not evidence it executes.

Owner chose **use existing amplifier calibration; stop if invalid**. No additional EFS exception or recalibration
is authorized/needed for that policy. B2a is probe-only: inspect ID, firmware, MTPEX and resistance-presence flags,
without output. A nonzero stock value alone does not validate playback protection. Both calibration-programming
entry points return NOT_SUPPORTED in the port. Raw values remain private; status logs use flags.
See `log/2026-11-22-M10.3-tfa9872.md`; the earlier defaults-vs-EFS question is superseded by this decision.

# tasks/ — tickets

One file per task. A ticket is the unit a session works on ("work on
`tasks/M1.1-…`"). Tickets exist only for the current and next milestone;
later milestones get tickets when we reach them (evidence first, Rule 1).

## Status values
`todo` · `in-progress` · `blocked (reason)` · `done (log/…)` · `dropped (reason)`

## Rules
- A ticket is done only when **every** acceptance criterion has evidence in `log/`.
- Change scope → edit the ticket (and `docs/05-plan.md` if the milestone changes) first.
- `Needs phone: yes` tickets wait for M0 DoD and require the owner present.

## Index

| ID | Title | Needs phone | Depends on | Status |
|---|---|---|---|---|
| M0.1 | Root SSH key on the phone | yes | — | done (log/2026-11-02-M0.1-root-ssh.md) |
| M0.2 | Baseline function checklist | yes | M0.1 | done (log/2026-11-02-M0-baseline-checklist.md) |
| M0.3 | USB access despite PD detection | yes | M0.1 | done (log/2026-11-02-M0.3-usb-access.md) |
| M0.4 | Diagnose baseline audio failure (kernel vs userspace) | yes | M0.2 | done (log/2026-11-02-M0.4-audio-diagnosis.md): userspace config |
| M0.5 | Microphone captures no voice (tracked defect) | yes | M0.4 | deferred: UT-image session |
| M1.1 | Reproduce baseline 4.14 kernel byte-identically | no | — | done (log/2026-11-01-M1.1-reproduce-baseline.md) |
| M1.2 | Build ACK android17-6.18 GKI for arm64 | no | — | done (log/2026-11-01-M1.2-ack-build.md) |
| M1.3 | Capture the vendor kernel ABI (contract capture) | yes | M0, M0.4 | done (log/2026-11-02-M1.3-contract-capture.md) |
| M1.4 | Does S-Boot boot a compressed Image? | yes | M0, M1.1 | done (log/2026-11-04-M1.4-compressed-image.md): gzip FAIL, lz4 untested |
| M1.5 | Working ramoops/pstore crash log | yes | M0, M1.1 | done (log/2026-11-04-M1.5-ramoops.md): last_kmsg works, ramoops@0xf9d10000 empty |
| M2.1 | A50 device tree for 6.18 (first-light subset) | no | M1.2 | done (log/2026-11-01-M2.1-dt.md; fb format risk accepted) |
| M2.2 | Minimal 6.18 defconfig + boot.img within budget | no | M1.2, M1.4 | done (log/2026-11-04-M2.2-firstlight-build.md) |
| M2.3 | DTB/DTBO partition images in stock dt_table format | no | M2.1 | done (log/2026-11-02-M2.3-dt-images.md) |
| M2.4 | First light on the phone | yes | M2.1–M2.3, M1.5 | done (log/2026-11-04-M2.4-diag-build.md, Test 19; DoD amended) |
| M3.1 | Boot 6.18 with our own DTB/DTBO | yes | M2.3, M2.4 | done (log/2026-11-07-M3.1-our-dt.md) |
| M3.2 | Readout at any time (panic hook + delayed dump) | yes | M3.1 | done (log/2026-11-07-M3.2-readout.md) |
| M3.3 | Exynos 9610 clock driver (CMUs for UFS and USB) | build no / test yes | M3.1, M3.2 | done (log/2026-11-07-M3.3-clocks.md) |
| M3.4 | Exynos 9610 pinctrl data (backport) | build no / test yes | M3.1 | done (log/2026-11-07-M3.4-pinctrl.md) |
| M3.5 | UFS storage, read-only | yes | M3.3, M3.4 | done (log/2026-11-07-M3.5-ufs.md; acceptance reworded) |
| M3.6 | USB device mode (DRD + PHY + gadget) | yes | M3.3, M3.4 | done |
| M3.7 | Halium initramfs on 6.18: mount /data, telnet over USB (M3 DoD) | yes | M3.5, M3.6 | done (caveat in ticket) |
| M4.1 | All 8 CPUs online | yes | M3 | done (log/2026-11-10-M4.1-smp.md) |
| M4.2 | ACPM firmware IPC for Exynos 9610 | yes | M3 | done (log/2026-11-10-M4.2-acpm.md) |
| M4.3 | S2MPU09 and S2MPB03 PMICs, regulators | yes | M4.2, M4.4 | todo |
| M4.4 | I2C, PWM, keys, PL330 DMA | yes | M3 | todo |
| M4.5 | Power domains | yes | M3 | todo |
| M4.6 | Thermal (TMU) | yes | M3 | todo |
| M4.7 | CPU frequency via ACPM DVFS | yes | M4.1, M4.2, M4.6 | dropped from M4 (owner decision 2026-11-10) |
| M4.8 | Core SoC integration and DoD | yes | M4.1-M4.7 | todo |

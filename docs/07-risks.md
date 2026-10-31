# 07 — Risks and mitigations

Ranked by impact on the goal. Review at every milestone boundary.

| # | Risk | Evidence | Impact | Mitigation / exit |
|---|---|---|---|---|
| R1 | **BOOT partition too small** for a 6.18 Image + Halium ramdisk | limit 57,671,680 B; baseline already 53.6 MB with uncompressed Image | blocks M2 | Verify `Image.gz` support (M1.4); minimal config; modules in ramdisk only if needed |
| R2 | **Mali kbase r26p0 on 6.18**: vendor libGLES requires this exact DDK ABI; r26p0 targets older kernels | `CONFIG_MALI_BIFROST_R26P0_R`; ARM DDK out-of-tree | blocks S2 | Port r26p0 with compat shims; fallback: Panfrost (G72 supported in 6.18) + non-vendor graphics — would violate ADR-0002, requires new ADR |
| R3 | **ION ABI shim** correctness (Samsung heap IDs, `ion_fdt_exynos`, `ionfd2phys`) | ION removed upstream; vendor gralloc uses it | blocks M6/M7 | Port 4.14 ION + exynos heaps as staging driver; replay captured ioctls (M1.3) |
| R4 | **No early console** (no practical UART) | phone hardware | slows M2–M4 debugging | ramoops at 0xf9d10000 + simplefb @0xca000000 first (M1.5/M2) |
| R5 | **Clocks/ACPM/PMIC** differences from mainline Exynos850/gs101 code | partial LKML clock series; ACPM protocol may differ | blocks M2/M4 | Use Samsung CAL tables as reference; incremental CMU enablement |
| R6 | **DECON/dpu20 + HWC ABI** coupling | vendor hwcomposer.exynos9610 expects Samsung fbdev/DPU ioctls (verify in M1.3) | blocks S2 | Forward-port dpu20 unchanged in ABI; capture ioctls first |
| R7 | **SCSC Wi-Fi/BT** size (~93 k + core) and firmware handshake | `net/wireless/scsc`, `misc/samsung/scsc*` | blocks S4/S8 | Port after core; keep baseline as daily driver |
| R8 | **Rust toolchain** needed for ACK ashmem | `depends on SHMEM && RUST` | build complexity | Pin ACK's prebuilt toolchain versions in the container |
| R9 | **S-Boot DT handling** (DTB/DTBO partition formats, overlay idx 5) | Android DT table magic `d7b7ab1e` | blocks M2 | Build dt_table with same id/rev fields as stock; keep stock images for rollback |
| R10 | **Bricking risk** | EFS/bootloader untouched by rule | catastrophic | Rules in `CLAUDE.md`; EFS backups in `../backup`; only BOOT/DTB/DTBO change |
| R11 | **Effort/time** — multi-month; single developer + AI | 90 Samsung driver files in C category | schedule | Strict milestone order; stretch items excluded from DoD |
| R12 | Upstream drift: ACK android17-6.18 moves (6.18.33 today) | ACK branch | rebases | Pin ACK commit per milestone; rebase only at milestone boundaries |

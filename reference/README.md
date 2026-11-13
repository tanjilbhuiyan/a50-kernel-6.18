# reference/ — evidence (do not edit by hand; regenerate with tools/)

| File | Produced by | Content |
|---|---|---|
| live-dt-compatibles.tsv | tools/dump_live_dt.sh on baseline (2026-11-01) | merged runtime DT: status, node, compatibles |
| gap-matrix-6.18.tsv | tools/gap_matrix.py vs src/linux-6.18.60 | per-node category A/B/C/D, driver files |
| halium-check-kernel-config.sh | Halium halium-boot repo (master) | official Halium kernel config checker |
| measurements/numstat.txt, namestatus.txt | git diff samsung-a50-4.14 vs linux-4.14.194 | per-file Samsung delta |
| stock-vendor/ | debugfs from stock vendor.img (A505FDDS9CWA2) | ueventd.rc, init rc, vintf manifest, fstab, HAL/firmware lists, dev-nodes |
| stock-images/dt.img, dtbo.img | firmware zip AP | stock DTB/DTBO partitions (rollback + reference) |
| m62-wakelock/ | M6.2 control/candidate boots | native wakelock, Binder/ashmem/sync checks and stock restores |
| m63-ion/ | baseline capture, host ABI helpers and M6.3 boots | measured heap-0 ABI, source patch and native/compat replay |
| m63-sysmmu/ | M6.3 config/provider boots | isolated DPU SysMMU probe, inputs, replay and restore evidence |
| m64-runtime/ | seven M6.4 boots | real Android/allocator startup, block policy, immutable scripts, manifests and clean restores |

The latest complete tested source/config and a public-input build recipe are
in [reproduce/m6/](../reproduce/m6/README.md). Historical input manifests name
large ignored local artifacts by hash; the recipe reconstructs the final
kernel/runtime without those private workspace files.

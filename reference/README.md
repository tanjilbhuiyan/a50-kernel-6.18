# reference/ — evidence (do not edit by hand; regenerate with tools/)

| File | Produced by | Content |
|---|---|---|
| live-dt-compatibles.tsv | tools/dump_live_dt.sh on baseline (2026-11-01) | merged runtime DT: status, node, compatibles |
| gap-matrix-6.18.tsv | tools/gap_matrix.py vs src/linux-6.18.60 | per-node category A/B/C/D, driver files |
| halium-check-kernel-config.sh | Halium halium-boot repo (master) | official Halium kernel config checker |
| measurements/numstat.txt, namestatus.txt | git diff samsung-a50-4.14 vs linux-4.14.194 | per-file Samsung delta |
| stock-vendor/ | debugfs from stock vendor.img (A505FDDS9CWA2) | ueventd.rc, init rc, vintf manifest, fstab, HAL/firmware lists, dev-nodes |
| stock-images/dt.img, dtbo.img | firmware zip AP | stock DTB/DTBO partitions (rollback + reference) |

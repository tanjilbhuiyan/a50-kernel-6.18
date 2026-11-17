# G2g: padded linear DMA scanout

G2g adds direct presentation of G2f's measured 1088x2352 buffers while
retaining the visible 1080x2340 image. It does not add scaling, cropping,
rotation, protected or compressed DMA. Results and rollback evidence:
[session log](../../log/2026-11-17-M7.3-g2g-padded-scanout.md).

## Reconstruct and build

Starting from the exported G2f source tree
`7253f8a58c52a3aa9c77b6458bd4ce81c28589b4`, apply
`reference/m73-gpu/g2g-padded-stride.patch`. Resulting tree must be
`ecb4aab84e0af0b68b6fb0aab5c155aaa2574908`.
The local isolated worktree is `src/m73/g2g-kernel`, dirty on
`a50-m73-g2g-wip`, based on Git commit `dce5cdc6e` plus the exported G2f
metadata and G2g stride patches. G2f's earlier worktree is preserved.

```sh
python3 -I tools/m73/scanout_unittest.py src/m73/g2g-kernel
python3 -I tools/m73/build_metadata_probes.py src/m73/g2g-kernel src/m73/g2g-session
bash tools/m73/build_g2g.sh /absolute/path/to/fresh/output
```

The actual build uses `src/ack-6.18/out/m73-g2g`. Its first full compile
caught a member-name typo; the corrected final build reran the checks and
linked cleanly without compiler-error overrides. Final artifacts are frozen
in `src/m73/g2g-as-built/`. Config/DTB/runtime cpio must exactly match G2f.
Package using `tools/m22_pack.sh`.

BOOT `src/m73/boot-g2g.img` SHA256:
`42cbbeb884bab6088a2835697bf8446e3edb025e60bde675ed33bcb4544053ad`.
DT stays `src/m73/dt-g1.img`. The 33 input hashes and 15 frozen source/
script snapshots are in `reference/m73-gpu/g2g-boot-inputs.json` and
`g2g-scripts/`. Source-derived helpers and raw logs remain ignored.

## Geometry and bounds

Stock `cal_9610/dpp_reg.c:108` programs full source size independently
from the visible image. `regs-dpp.h:182` defines SRC_SIZE at 0x10,
SRC_OFFSET at 0x14, IMG_SIZE at 0x18. Stock DT dpp_0 source-full maxima
are 65534x8190. For the observed padded buffers the values are:

| Register | Padded UI | Boot framebuffer fallback |
|---|---|---|
| SRC_SIZE | `0x09300440` (1088x2352) | `0x09240438` (1080x2340) |
| SRC_OFFSET | zero | zero |
| IMG_SIZE | `0x09240438` | `0x09240438` |

Eligibility checks require a supported linear format, zero crop, unscaled
full-screen image, valid full extents and adequate dma-buf backing. The
contiguous mapped IOVA prefix must cover the entire padded extent and
end within the 32-bit address space. Source geometry is reset when
switching to the boot framebuffer; old scanout mapping is released after
the existing frame synchronization point.

The host test compiles the real eligibility, range, SG-map and MMIO/
fallback routines. Positive/boundary cases and seven broken variants
exercise padding, backing size, mapping gaps/cleanup, end-address checks,
register encoding and boot-framebuffer restoration. This is a functional
algorithm test with mocked DMA/MMIO, not a hardware emulation.

## Boot procedure and limits

With current owner confirmation and fresh baseline pre-flight:

```sh
bash tools/m73/run_g2g.sh 192.168.181.225
```

The prepared cycle uses the established DTB/DTBO/BOOT flash/restore runner.
Native/compat metadata regressions run, then natural UI/runtime/storage
snapshots at 100/200/300 seconds. There is no competing graphics client.
Independent kernel/counter streams and late actual IDMA readback establish
the scanout path. Normal timed dump, stock restore, partition verification
and saved fsck complete the cycle. Existing evidence is not overwritten.

Judge visible correctness from owner observation alongside counters and
readback. Presentation update rate is workload-specific, not a general GPU
benchmark or a claim of perceptible smoothness. Natural UI may never use
fallback; fallback restoration is then host-tested only. This 420-second
diagnostic window does not complete the M7 ten-minute soak or focused
kbase allocation/import/query/sync validation.

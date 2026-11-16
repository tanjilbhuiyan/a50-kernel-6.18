# G2b build and diagnostics

The candidate removes the unsafe process-page-table check from soft-job
cancellation and adds passive display diagnostics. G2 config, DTB,
ramdisk, fence semantics and display routing stay the same. See the
[session log](../../log/2026-11-17-M7.3-g2b.md) and
[input manifest](../../reference/m73-gpu/g2b-inputs.json) for current test status.

## Build from public exported source

After the [M6 prerequisites](../../reproduce/m6/README.md):

```sh
python3 -I tools/reproduce_m6.py --prepare-only
git -C src/reproduce-m6/ack/common switch -c a50-m73-g2b-wip
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g1-kernel.patch"
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g1b-irq.patch"
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g2b-cancel.patch"
git -C src/reproduce-m6/ack/common apply "$PWD/reference/m73-gpu/g2b-display-diagnostics.patch"
A50_ACK_WORKSPACE="$PWD/src/reproduce-m6/ack" \
A50_KERNEL_TREE="$PWD/src/reproduce-m6/ack/common" \
    bash tools/m73/build_g2b.sh src/m73/g2b-rebuild
```

An existing ACK/toolchain workspace defaults to `src/ack-6.18`, and this
session's isolated source defaults to `src/m73/g2b-kernel`. The script
requires a fresh output directory; `--resume OUTPUT` permits an incremental
rebuild only with the exact locked config. Cancellation/guard/sense/mmap
tests run before the kernel build. The exported patches reconstruct tree
`89009e6d9e9170360d724a9e6258c2a917e66389`.

Packing/flashing additionally requires the owner's verified stock partition
templates, baseline donor and rollback setup. The build never flashes.

## Read the evidence

The read-only `g2b_stats` attribute is on the existing platform device:

```sh
cat /sys/devices/platform/148b0000.decon_f/g2b_stats
```

`fence_ctx` identifies this display timeline. Compare it directly with the
Mali guilty-fence context from the same boot; do not assume a global context
number has the same owner after init-order changes. `fence_seq`/`pending`,
`completed`, `scanned`, `copied`, `dma_fallbacks` and layer/format counters
distinguish submission and worker progress. `completed` counts the worker
reaching release signaling; it does not by itself prove scanout or visible
pixels. The existing frame/timeout report and IRQs provide further evidence.

`stage` names the active worker operation: `hw-lock`, `acquire-fences`,
`dma-map`, `dma-frame-sync`, `cpu-access-or-vmap`, `cpu-pixels`,
`cpu-vunmap-or-end`, `bootfb-frame-sync`, `signal-release`, or `idle`.
`worker_seq` and `worker_layers` identify that update; `worker_formatN`
holds its layers' formats (unused slots are 4294967295). Snapshot fields
are asynchronous, so use repeated stable samples to diagnose a stall.

`layersN` counts accepted configurations with N buffer layers; failed
imports can make their total differ from the older `win_configs` count.
DMA eligibility in a sampled log is not proof that mapping/scanout succeeded;
the existing path counters and completion count provide that distinction.

The prepared runner streams these snapshots and kernel output before the
GLES tests. It checks the login-shell TLS setting, records client exit
status and keeps the timeout cancellation test. The rootfs/vendor content
and service environment files are not edited. Every live cycle requires
owner presence, exclusive access and a fresh baseline pre-flight.

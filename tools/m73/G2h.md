# G2h: focused kbase memory ABI checks

G2h runs the same static native and compat helpers on stock 4.14 and the
unchanged G2g 6.18 image. No kernel changes or new kernel build are involved.
See the [session log](../../log/2026-11-17-M7.3-g2h-memory-abi.md) and
`reference/m73-gpu/g2h-boot-inputs.json` for exact inputs and frozen sources.
Reconstruct G2g using [its recipe](G2g.md) first if needed.

```sh
python3 -I tools/m73/build_memory_probe.py src/m73/g2g-kernel src/m73/g2h-session
```

The builder reads the actual r26p0 ioctl declarations and extracts the
memory/context/sync constants. Both builds assert ioctl numbers and layout
sizes. Each of six cases opens a fresh GPU context after fork, disables job
submission and checks descriptor cleanup. Cases cover tracking prerequisites,
cached allocations/query/map/sync/lifetime, pending cookies, heap-0 dma-buf
import and exporter-fd lifetime, aligned user-buffer reservation, and bounded
invalid requests. This is neither a fuzz test nor a GPU benchmark.

With owner present and Claude idle, run the stock control before flashing:

```sh
bash tools/m73/run_memory_baseline.sh 192.168.181.225
```

Check both `G2H_BASELINE_*_RC=0` markers and both six-case PASS summaries;
the wrapper's exit status alone does not establish probe success. Stock
creates a per-task `anon_inode:<pid>` dma-buf accounting descriptor. Only
one matching CLOEXEC descriptor is allowed by the dma-buf case; any other
descriptor discrepancy fails. Pilot logs preserve the original helper
assumption that incorrectly treated this accounting descriptor as a leak.

Prepare and review hashes/frozen sources in `g2h-boot-inputs.json`, verify
the backup and baseline pre-flight, then obtain confirmation for this boot:

```sh
bash tools/m73/run_g2h.sh 192.168.181.225
```

The runner refuses to overwrite an existing G2h run. Preserve old evidence
and use new capture names for a subsequent cycle. It flashes the unchanged
G2g image via the established DTB/DTBO/BOOT runner, uploads helpers only into
`/run` tmpfs, runs each ABI with a 60-second bound and captures natural UI
runtime/storage at 160/300 seconds. Independent kernel/counter streams,
a late snapshot, timed dump, stock restore, partition verification and
baseline fsck complete the cycle. Published text is redacted; raw logs and
binaries remain under ignored `src/m73/`.

Both sync directions are checked for native and dma-buf memory. User-buffer
cache sync returns EINVAL on stock; the test preserves that ABI. No probe
submits jobs, pins user imports around external-resource jobs, or proves
GPU-produced readback on every buffer. Real GPU execution and presentation
are established separately by the G2f/G2g UI evidence. Unsupported secure
heaps, standalone EGL failure, startup/session integration and M8 input
remain explicit limits. A rendered greeter does not prove successful login.
This diagnostic window does not replace M7.5's ten-minute soak.

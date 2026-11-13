# M6.4 runtime evidence

Final result: **test 7 passes the M6 startup/allocator DoD**. See
[results.json](results.json) and the [session log](../../log/2026-11-14-M6.4-runtime.md).
Phone restored to stock, hashes verified and baseline init's saved fsck clean.

| Test | Variable/result |
|---|---|
| 1 | Safe mount stage; overly strict existing-rootfs check stops before LXC |
| 2 | Root bind fixed; missing LXC global allow denies character devices |
| 3 | Device-policy default fixed; Android runs and normal boot property reaches 1 |
| 4 | Full block denial; diagnostic namespace setup fails, no probe success claimed |
| 5 | Same image, corrected diagnostics: policy matrix and guest ION pass |
| 6 | All four M5 masks removed; full kmsg locates blocking TEEGRIS post-fs wait |
| 7 | Runtime TEEGRIS deferral: real allocator running/HIDL-registered, guest replay and policy pass, multi-user/degraded/zero jobs |

Each `runtimeN-run.txt` records flash/restore/post-flight. Each
`runtimeN-baseline-fsck.txt` is the baseline init's saved output after
restore, never a checker run against a mounted filesystem.

`inputs.json` is test 1's manifest; later tests have numbered manifests.
`source_snapshots` resolves evolving tool/build paths to immutable as-run
copies. Exact scripts are in `runtimeN-scripts/`. Large build artifacts
are ignored under `src/m64/runtimeN/as-built/`; the shared build workspace
was reused only after preserving earlier artifacts. Test 5 deliberately
reuses test 4's exact image.

The authoritative device probe is `block_policy_matrix.c`, covering all
open modes and mknod against an absent synthetic device without block I/O.
The baseline negative control correctly fails the restrictive-policy
assertions. Early exploratory helpers exist only in historical snapshots.

Limits: TEEGRIS/security HALs deferred; six reserved/secure heaps unsupported;
three diagnostic power masks remain; legacy task-profile warnings and
hardware graphics DMA remain unvalidated. All four M5 HAL masks are gone.
No display, GPU, Bluetooth, modem, audio or suspend success follows from
passing M6. Dumps/live captures have hardware identifiers redacted and
trailing whitespace normalized; runner byte counts precede that cleanup.

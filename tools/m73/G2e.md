# G2e: gralloc ION hints

G2e changes only the accepted ION allocation hint bits (0x2/0x8), atop
G2d's allocation diagnostics and G2c's stock display-format translation.
It passed both native and compat request replay and zeroing/protection
checks. Mir stays active, but reports a 0x0 mode and usable rendering is
unverified. See [results](../../reference/m73-gpu/g2e-results.json) and
[session log](../../log/2026-11-17-M7.3-g2e-ion-hints.md).

## Source and image

Follow the [G1 reproduction recipe](README.md) and [G2b recipe](G2b.md),
then apply, in order, the exported `g2c-format.patch`, `g2d-ion-log.patch`
and `g2e-ion-flags.patch` from `reference/m73-gpu/`.
Final source tree must equal `b632eb2709cbce0cfad645109d94b5ce4ba9b8cb`.
Local tested commit is `dce5cdc6e9d1c3cd64f063d5f29e1344e5724756`, branch
`a50-m73-g2e-wip`, isolated tree `src/m73/g2b-kernel`. The build script
checks that branch name; use a separate prepared worktree. It never
switches or flashes the shared checkout.

```sh
tools/m73/build_g2e.sh /absolute/path/to/fresh/output
```

The existing build produced the tested image; no rebuild was done in the
office session. Exact image/config/runtime/DT and build-script hashes are
in `reference/m73-gpu/g2e-inputs.json`. Config/DTB/cpio equal G2d.
The tested BOOT is `src/m73/boot-g2e.img`, SHA256
`9202dbc17d63260bbe593ea5775f1698239041a450277c40b818a70aff4614fc`.

## Probe builds and procedure

From the project root, using the existing pinned Android NDK r27:

```sh
mkdir -p src/m73/g2e-session
src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang \
  -std=gnu11 -static -O2 -Wall -Wextra -Werror \
  -I src/m73/g2b-kernel/drivers/staging/android/uapi \
  tools/m73/ion_flags_test.c -o src/m73/g2e-session/ion-flags64
src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang \
  -std=gnu11 -static -O2 -Wall -Wextra -Werror \
  -I src/m73/g2b-kernel/drivers/staging/android/uapi \
  tools/m73/ion_flags_test.c -o src/m73/g2e-session/ion-flags32
```

The existing `src/m73/winconfig-test-g2d` is built from
`tools/m72/winconfig_test.c`; its tested hash is in the candidate manifest.
G2e did not execute that helper because LightDM stayed active.

`collect_g2e.sh` observes natural startup to uptime 100, captures Mir and
runtime state, runs both ION probes, then bounded GLES/EGL clients through
a login shell with the required static-TLS setting. Three unsupported
requests per ABI intentionally generate six rejection logs. Only /run
tmpfs files/mounts are added. A direct display test is skipped while
LightDM is active.

`run_g2e.sh` uses the established flash/restore runner and independent
USB SSH watcher/streaming evidence. It verifies both input manifests,
rejects existing run output and waits for stock restore even when a client
fails. The completed invocation was:

```sh
bash tools/m73/run_g2e.sh 192.168.181.225
```

That invocation has already run. Preserve its evidence. A later test needs
its own output paths/manifests and fresh owner-presence confirmation per
CLAUDE.md. Candidate, session and supplementary observation manifests
record the exact files; `g2e-scripts/` preserves script/header snapshots.
Raw output stays ignored until hardware identifiers are redacted.

## Next investigation

Audit HWC2 display config/attribute queries and the kernel metadata they
consume against the restored baseline. Mir sees 1080x2340 on baseline and
0x0 on G2e, despite fbdev reporting correct dimensions on both. Both
FBIOGET_VSCREENINFO pixel clocks are zero, so do not treat a missing pixel
clock as an established cause. `read_fb_mode.py` is a read-only control
reader. The EGL SIGSEGV and second composer-client rejection remain
explicit limitations; neither proves a GPU kernel fault.

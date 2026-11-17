# M7.4: omit G2D for the measured single-layer M7 path

**Decision (2026-11-17): drop the conditional G2D port for the exercised
normal, single-layer greeter/display path.** Keep G2D absent from the kernel
and preserve vendor userspace. Reopen the ticket when a required workload
selects G2D processing and cannot complete through the existing path.
This does not establish that every Lomiri scene or vendor consumer can
work without G2D. M7.5 integration and soak remain open.

## Evidence and reasoning

The [M1.3 contract](../contract/README.md) records real `/dev/g2d` openers
in both Android composer and the host compositor. It has no G2D ioctl in
the sampled steady-UI/app-start captures, but explicitly excludes startup
traffic. That absence alone cannot justify omitting the driver. The
[M7.1 audit](../../log/2026-11-14-M7.1-display-gpu-audit.md) therefore
left G2D conditional, starting without it. This decision combines that
history with consumer control flow, donor source, the actual linked build,
and positive display results obtained without a functional G2D provider.

### Consumer control flow

The unchanged stock `libexynosdisplay.so` imports Acrylic; it constructs
the M2M compositor/scaler objects, rather than requiring every displayed
frame to execute a G2D job. Relevant locations in the inspected 64-bit
vendor binaries are below. Addresses are virtual code addresses, not
phone memory reads. Exact binary hashes and both ABI symbol locations
are in [host-audit.json](host-audit.json).

| Library / function | Location | Reviewed behavior |
|---|---|---|
| display: `ExynosMPP` constructor | `0x50bf4`, `0x50cc0` | Creates `default_compositor` / `default_scaler` Acrylic objects; a null object is a separate constructor error path |
| acryl: `createAcrylic` / `createInstance` | `0x13ca4`, `0x139d0` | Default compositor resolves to `fimg2d_9610`; branch `0x13a14` reaches allocation/constructor `0x13b48`–`0x13b90`, then returns the object at `0x13b94` |
| acryl: G2D9810 constructor | `0xe62c` | Selects `/dev/g2d` or `/dev/fimg2d` from capability data; initializes command version to zero, attempts query `0x80044d07` at `0xe6dc`, logs failure and continues from `0xe70c`; no device-open failure is converted into a null Acrylic object here |
| acryl: `AcrylicDevice::ioctl` | `0x15e40` | Opens the named device if necessary; failed open logs and returns -1 at `0x15eec`; it does not pretend to execute the ioctl |
| display: `doExynosComposition` | `0x38950`–`0x38958`, `0x38b00` | Tests the composition-enabled field; when zero, returns success without calling the M2M operation |
| display: enabled M2M path | `0x38964`, `0x38abc` | Requires an MPP and calls `doPostProcessing`; missing MPP or processing failure reaches error handling |
| acryl: real task execution | `0xfe3c`, `0xf130` | `executeG2D` calls `ioctlG2D`; the latter sends the task (`0xc1304d04` on the default version path), returning negative errno on failure at `0xf27c`–`0xf284` |

The 32-bit Thumb library confirms the important missing-device behavior:
G2D9810 constructor starts at `0xaaec`; its query at `0xab52` branches to
logging on failure, then continues at `0xab76` and returns the object.
`AcrylicDevice::ioctl` at `0xf3a0` returns -1 at `0xf3bc` when open fails.
The display implementation at `0x2bd54` similarly tests the composition
flag (`0x2bdd0`–`0x2bde2`) and skips to its success epilogue when disabled.
ELF symbol addresses have a Thumb bit; use the cleared `code_address` in
the audit when reproducing disassembly.

**Inference from this control flow:** initialization can survive a missing
G2D device; it does not imply a universal CPU/GPU fallback for an explicitly
selected G2D task. We have not traced every HWC policy/resource-assignment
branch and do not assert that all complex scenes choose a safe fallback.

### Source and actual build

Samsung donor source at commit
`4f37ef3970e95faa8713191b3aac32b432277e82` identifies the real interface:
`drivers/gpu/exynos/g2d/g2d_drv.c:950` / `:961` registers misc devices
`g2d` / `fimg2d`. `__g2d_ioctl` dispatches task processing at line 291
and starts the task at line 369; priority and performance requests are
separate cases. `g2d_uapi.h:263` defines PROCESS as `_IOWR('M', 4, ...)`.
The compat dispatcher at `g2d_drv.c:561` translates the pointer-bearing
task ABI. A future port must preserve this actual interface and fences;
the unrelated upstream Exynos DRM or V4L2 G2D interfaces are not drop-in
implementations for these vendor binaries.

The tested G2g build has MODULES, MEDIA_SUPPORT and DRM disabled and no
Samsung G2D port. Its frozen `vmlinux` has **zero G2D/fimg2d-named text
symbols**; the 25 matching symbols are clock data tables. The display
driver `a50-decon.c` has no G2D backend. Thus these measured frames cannot
be evidence of successful G2D hardware execution. This is build/source
evidence; this host session did not collect a fresh `/dev` listing.
The `ion_compat: G2d alloc ...` log prefix names the earlier **G2d test
stage**, not the G2D accelerator or a G2D allocation client.

### Positive runtime evidence with G2D unavailable

Saved G2f/G2g/G2h runs use the unchanged vendor libraries and initialize
Mir's ARM/Mali-G72 renderer at 1080x2340. Owner observations establish
recognizable greeter rendering in G2f/G2g, refined by the later report
that touch is unresponsive and PIN/login was not tested.

| Run | Final display updates | Direct DMA | CPU copies | Latest sampled cumulative layer counts |
|---|---:|---:|---:|---|
| G2f | 1,019 | 0 | 1,019 | 1,009 single-layer; all other counts zero |
| G2g | 19,725 | 19,725 | 0 | 19,717 single-layer; all other counts zero |
| G2h | 19,574 | 19,574 | 0 | 19,574 single-layer; all other counts zero |

Counter polling ends before the late dump; the first two sampled layer
totals therefore trail their final frame totals. These are DECON
WIN_CONFIG layer counts, not a count of all surfaces inside the GPU's
rendered scene or a G2D ioctl trace. G2g/G2h show zero skipped frames,
DMA fallbacks and acquire/frame/shadow timeouts in the final dump.
G2h's UI buffers are 1088x2352, with a visible 1080x2340 image.

This positively establishes presentation without G2D for the measured
path, rather than simply failing to observe a G2D ioctl. It does not
establish a stable phablet session: G2h's session exits status 1 and falls
back to a greeter, with startup/service issues still recorded. No evidence
here attributes that session exit or standalone EGL crash to G2D, or
rules G2D out for every future workload. See
[G2h results](../m73-gpu/g2h-results.json) and
[owner clarification](../../log/2026-11-17-M7.3-owner-login-observation.md).

## Scope, reopen conditions and next work

Drop **implementation for the currently exercised normal single-layer
path**, not the general vendor ABI requirement. Leave secure/protected
content, video/YUV conversion, scaling/rotation, virtual/external displays
and complex composition unverified. Four stock DPP windows do not imply
that the current single-window port supports four layers, or that a fifth
layer always requires G2D; the actual consumer assignment determines that.

Reopen M7.4 if a required workload attempts G2D processing or reports an
M2M assignment/execute failure that prevents presentation, or if M7.5
reveals a mandatory path needing G2D format/transform/blending support.
Capture the consumer, native/compat request, geometry, buffers and fences
before choosing a port. Do not add a fake device, success-returning ioctl,
vendor-library patch or broader storage permissions to hide that need.

M7.5 must assess startup/session stability, exercise the required UI
workloads and complete its ten-minute soak. It should carry this scoped
decision forward and revisit it on contrary evidence. Touch remains M8.
M7's DoD is not closed by this decision.

## Reproduction and session boundary

```sh
python3 -I tools/m74/audit_g2d.py > reference/m74-g2d/host-audit.json
```

Requires local M7.1 vendor extracts with their saved SHA256SUMS, donor
source, frozen G2g build and saved G2f/G2g/G2h evidence. The tool verifies
vendor hashes, records 34 input hashes, extracts function addresses,
checks the linked/configured provider status and derives runtime counts.
Full proprietary disassembly remains ignored under `src/m74/audit/`;
only identities, symbol locations and reviewed findings are published.
The JSON provides observations; the scoped interpretation is this document.

Host-only work: no phone access, flash, new build, kernel change, commit
or push. Last phone verification remains the G2h stock restore on
2026-11-17 at 15:01:33, baseline boot 15:01:46, partition post-flight
passed and fsck clean (7051 files). Current live state has not been rechecked.

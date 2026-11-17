# HWC2 mode initialization: first missing query

This is a static trace of the installed vendor binaries, checked against
read-only metadata queries on the working stock kernel. No G2f boot has
run; successful initialization after implementing the missing ABI remains
unverified.

## Evidence identities

| Input | Identity |
|---|---|
| Stock source `src/samsung-a50-4.14-aa17rf2` | commit `4f37ef3970e95faa8713191b3aac32b432277e82` |
| Candidate source `src/m73/g2b-kernel` | clean `dce5cdc6e9d1c3cd64f063d5f29e1344e5724756` |
| 64-bit `src/m71/vendor/lib64/libexynosdisplay.so` | SHA256 `aa93b5099889ddc770a62f3f1414d7165ffd3fde2abecd9e1a6c88a79e9bd922` |
| 32-bit `src/m71/vendor/lib/libexynosdisplay.so` | SHA256 `157148d33f0317dec7dde93794b9cec18d4d0657ecd0a3c7ebec5b4780dd587f` |
| Live baseline query | `g2f-baseline-display-info.txt`, through phablet SSH at office `192.168.181.225` |
| Earlier test/control behavior | `g2e-live.txt`, `g2e-baseline-display.txt` |

Vendor binaries and their disassembly remain ignored under `src/`.
Only hashes, function/branch locations, ABI facts and observations are
published here. Exact analysis input hashes are in `g2f-inputs.json`.

## Call sequence and early return

`hwcomposer.exynos9610.so` exports `exynos_getDisplayConfigs` and
`exynos_getDisplayAttribute`; the display implementation is in
`libexynosdisplay.so`. In the 64-bit library:

| Location | Behavior |
|---|---|
| `ExynosPrimaryDisplayFbInterface::init`, `0x7190c` | Opens the display and calls `getDisplayHWInfo()` at `0x71968` |
| `getDisplayHWInfo`, `0x7197c` | Initializes a 248-byte metadata buffer with version 2 |
| `0x71a04`–`0x71a10` | Calls `ioctl(fd, 0x40f84704, buffer)` |
| `0x71a14`–`0x71a18` | A return of -1 branches to error handling at `0x71a84` |
| `0x71a84`–`0x71aac` | Logs `EXYNOS_DISP_INFO ioctl failed: %s`, then jumps to the function exit |
| `0x71a54`–`0x71a60` | Only on metadata success: calls `FBIOGET_VSCREENINFO` (`0x4600`) |
| `0x71adc`–`0x71af8` | If fbdev `reserved[0:2]` are zero, copies xres/yres into them and calls `FBIOPUT_VSCREENINFO` |
| `0x71b10`, `0x71b20` | Stores dimensions in the display object, then calculates DPI and initializes configuration data |

The 32-bit Thumb implementation has the same gate: function `0x53088`,
ioctl call `0x530bc`, failure branch `0x530c2`, framebuffer read only at
`0x530ea`. Decode it as Thumb, not ARM instructions.

G2e's `a50_fb_ioctl()` implements only VSYNC_INT, WIN_CONFIG and POWER_MODE;
all other requests return `-ENOTTY`. Thus this exact mandatory metadata
request fails before the library reads the otherwise correct fbdev
dimensions. The early return explains why independently reading
FBIOGET_VSCREENINFO correctly was insufficient. It is a concrete missing
ABI dependency; a fixed-image boot is still required to verify the result.

## Mandatory ABI and measured stock response

Stock `dpu20/decon.h:1389` defines
`EXYNOS_DISP_INFO = _IOW('F', 260, struct decon_disp_info)`.
The request number is **`0x40f84704`**, with size **248**, in both native
and compat layouts. Do not mask the unusual command number 260 down to
eight bits when reproducing Samsung's ioctl value.

`decon.h:470`, `panels/decon_lcd.h:40` and `:49` define this layout:

| Offset | Field | Baseline value |
|---|---|---|
| 0 | HWC version | 2, caller supplied |
| 4 | PSR mode | 2, `DECON_MIPI_COMMAND_MODE` |
| 8 | Multi-resolution enabled | 0 |
| 12 | Multi-resolution entry count | 1 |
| 16–115 | Five entries, five u32 fields each | First entry `(68,147,0,0,0)`; four remaining entries zero |
| 116 | Chip version | 9610 |
| 120–247 | Reserved bytes | Stock handler preserves caller bytes; zero in this query |

The stock `decon_core.c:2933` handler copies the caller's entire structure,
fills PSR mode, chip version and the panel's multi-resolution data, then
copies it back. Version/reserved bytes are preserved. Its metadata query
does not set a display mode. The measured mres entry is 68x147; do not
replace those values with 1080x2340 by assuming they are pixel dimensions.
The separate fbdev response supplies the pixel dimensions and physical size.

## Optional mode enumeration has a working fallback

`getDisplayConfigsFromDPU()` at `0x72c08` queries the mode count
(`0x400446bc`) and per-mode fields (`0x401c46bd`). On error, the branch at
`0x72de8` reaches `0x72e40`, which inserts a configuration using the already
initialized display dimensions/DPI/default refresh. Current-mode request
`0x400446c1` also has error handling with a fallback index.

All three optional requests return errno 25 (`ENOTTY`) on the live working
baseline. Its Mir still reports 1080x2340. Implementing those optional
queries is therefore not required to match the demonstrated working path.
The mandatory metadata request succeeds there, which is the relevant
contrast with G2e.

The stock fbdev reserved words are `[1080,2340,0,0]`. Both kernels report
pixclock zero, as already measured in G2e; a new clock/timing change is not
justified by the mode mismatch alone.

## Reproduce the trace

The read-only probe is `tools/m73/read_display_info.py`. The completed
baseline invocation was:

```sh
ssh -o BatchMode=yes phablet@192.168.181.225 python3 - < tools/m73/read_display_info.py
```

Use the existing LLVM objdump at
`src/ack-6.18/prebuilts/clang/host/linux-x86/clang-r584948c/bin/llvm-objdump`:

```sh
llvm-objdump --demangle -d --start-address=0x7190c --stop-address=0x71bd0 src/m71/vendor/lib64/libexynosdisplay.so
llvm-objdump --demangle -d --start-address=0x72c08 --stop-address=0x72ea4 src/m71/vendor/lib64/libexynosdisplay.so
llvm-objdump --triple=thumbv7-linux-gnueabi --demangle -d --start-address=0x53088 --stop-address=0x53152 src/m71/vendor/lib/libexynosdisplay.so
```

## Proposed next change

Implement only EXYNOS_DISP_INFO in the diagnostic display driver, retaining
the stock copy-in/copy-out behavior and measured metadata. Assert the
248-byte layout, offsets and native/compat ioctl number. Check invalid
user pointers and preservation of caller version/reserved bytes. Keep
optional mode queries unsupported so the observed stock fallback is used.
Then test whether HWC2/Mir reports 1080x2340 and Lomiri progresses, with a
normal baseline restore. No kernel patch, build or flash was made for this
tracing task.

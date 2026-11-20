# Galaxy A50 on Linux 6.18

An open effort to run **Ubuntu Touch 26.04 (Halium 11)** on the **Samsung Galaxy A50 (SM-A505F, Exynos 9610)** with a
modern kernel: Google's Android Common Kernel `android17-6.18` (Linux 6.18 LTS) instead of Samsung's 4.14. The stock
Android 11 vendor partition (`A505FDDS9CWA2`) stays unchanged; the new kernel has to provide what it expects.

Why: Samsung's 4.14.194 kernel is out of support, and every newer userspace needs shims for it (Ubuntu 26.04 `tar`
needs `openat2`, for example). Goal, success criteria and non-goals: [docs/00-goal.md](docs/00-goal.md).

> [!WARNING]
> **Experimental. Not for daily use.** The 6.18 display/GPU and touch work, but screen blanking, Wi-Fi,
> audio, modem and charging remain incomplete or unverified. Testing flashes the BOOT and DTB/DTBO partitions, which can leave
> it unbootable until you restore it. The project never writes EFS, SEC_EFS, CPEFS, PARAM, the bootloader or the vendor
> partition, and its UFS write guard (below) enforces that in the kernel, but you use this at your own risk.
> SM-A505F only; no other A50 variant has been tested.

## Status

The 6.18 kernel boots on the phone, runs Halium's init and brings Ubuntu Touch up to systemd multi-user. Root SSH works
over USB networking (RNDIS). The Android container boots, its real graphics allocator registers over HIDL, and 64/32-bit
ION replay passes as Android's system user. [M7.3](log/2026-11-17-M7.3-g2h-memory-abi.md) verifies the measured Mali
memory paths and greeter presentation through direct DMA. [M7.4](reference/m74-g2d/decision.md) drops G2D for that
single-layer path. [M7.5](log/2026-11-18-M7.5-i3-handler-startup.md) completes M7: the Lomiri session becomes ready
at about 50 s, composites on the Mali-G72 GPU and ran a ten-minute soak without faults (idle greeter; touch is M8).
M8.5's [interactive soak](log/2026-11-19-M8.5-input-integration.md) verified unlocking, Settings and navigation for
ten minutes without recorded graphics faults or a session restart, completing M8 (S3: touch and keys). Hall events,
USB resets and a memory-retention review moved to M12.
Current state and next action: [STATUS.md](STATUS.md).

| Milestone | What | State |
|---|---|---|
| M0-M1 | Baseline 4.14 system measured, reproducible builds, vendor kernel ABI captured | done |
| M2 | First light: 6.18 boots on the A50 | done |
| M3 | Storage (UFS) and USB gadget | done |
| M4 | Core SoC: 8 CPUs, ACPM, PMIC regulators, power domains, thermal | done; I2C and CPU frequency deferred |
| M5 | Ubuntu Touch userspace: systemd multi-user, SSH over USB | done, with limits below |
| M6 | Android container: binder, ashmem, ION and real allocator startup | done, with runtime limits below |
| M7 | Display/GPU: Lomiri UI on the Mali GPU | done with limits (G2D omitted, fixed GPU clock, light-load soak) |
| M8 | Input: I2C, touch, keys, hall sensor and vibrator | done with limits (hall events, USB resets, memory review → M12) |
| M9 | Wi-Fi/Bluetooth (SCSC) | done: Wi-Fi (S4) and Bluetooth pairing + A2DP audio (S8), factory addresses (ADR-0009) |
| M10 | Audio: ABOX, codec, amplifier, PulseAudio | in progress; ABOX DSP boots normally, PCM/card and audio paths pending |
| M11-M12 | Modem, power/charging | planned |

Current bring-up limits (details in [the M6.4 log](log/2026-11-14-M6.4-runtime.md)):

- The four M5 HAL masks are removed. Bluetooth/audio services still fail or retry while their drivers are unported.
- Touch works since M8.2 (mainline `melfas_mip4`; Lomiri usable by touch). I2C runs with CMU_PERI left to the
  bootloader ([ADR-0007](docs/decisions/ADR-0007-cmu-peri-bootloader-clocks.md)). Open: the touch controller is not
  powered down when the screen blanks, and it storms with empty interrupts from boot until the first touch (as on
  stock). Volume/power key events work; screen blanking remains deferred while repowerd is masked. The vibrator works;
  hall sensors register but actual cover events remain unverified (no magnet available; M12). Intermittent USB
  re-enumeration reproduced without keys; its cause remains unresolved (M12).
- A per-boot read-only RC bind defers unported TEEGRIS startup, with vendor unchanged and no fake readiness. Secure heaps
  and security-dependent HALs are unsupported; only the measured normal system heap is implemented.
- Audio is in progress (M10): the ABOX DSP boots automatically after the CMU bus-clock fix
  ([A1l evidence](log/2026-11-20-M10.2-abox-core.md)); PCM/card, codec and amplifier work remain.
  Per [ADR-0005](docs/decisions/ADR-0005-defer-android-audio-hal.md), 6.18 boots overlay
  PulseAudio's startup script without the Android audio HAL module, so the session can start; there is no sound.
- Hardware video codecs are unported (MFC, M13). Per [ADR-0006](docs/decisions/ADR-0006-defer-gst-hybris-codecs.md),
  6.18 boots hide GStreamer's Android codec plugin so the session can start; only software codecs are available.
- Three diagnostic power-service masks remain; automatic suspend and legacy Android task-profile migration are unvalidated.
- USB networking needs a one-boot override (`usb-moded -f -r`), because cable and charger detection don't work yet (M12).
- All test boots used the diagnostic kernel build, which dumps its log and reboots after a fixed time.

Full plan with each milestone's Definition of Done: [docs/05-plan.md](docs/05-plan.md). Tickets: [tasks/](tasks/README.md).

## How the work is done

- **Evidence first.** Every claim cites a log, a command output or a source file; unknowns are marked "unverified".
- **One change per boot test**, recorded in [log/](log/) with input hashes, the result and the rollback check.
- **A known-good fallback before every flash.** The test runner flashes the test kernel, collects its log, restores the
  stock DTB/DTBO and the baseline 4.14 boot image, then checks the phone again.
  Workflow and recovery: [docs/06-workflow.md](docs/06-workflow.md).
- **Default-deny storage.** `A50_UFS_SAFE` in the UFS driver refuses every write command unless it is enabled, and then
  only inside the userdata partition. Each boot runs a self-test of the guard before any UFS traffic, and host tests
  check it against deliberately broken copies (`tools/m35/`, `tools/m52/`, `tools/m53/`).
- **Modern mechanisms first.** Where 6.18 offers a newer mechanism than 4.14 used (nftables, `CONFIG_LSM`, cgroup v2,
  mainline drivers), the port uses it.

## Kernel source

- **Build the stable M9 driver stack:** [reproduce/m8/](reproduce/m8/README.md).
  After cloning, run `python3 -I tools/reproduce_m8.py --jobs 16`. This fetches pinned public inputs, applies all
  70 patches, reconstructs the current Halium runtime and builds Image, raw DTB and BOOT without private backups.
  This clean image excludes timed-test code and has not itself been flashed; the individual drivers have phone evidence.
- **Build the experimental ABOX DSP core:** [reproduce/m10-a1/](reproduce/m10-a1/README.md).
  Run `python3 -I tools/reproduce_m10_a1.py --jobs 16` for the 77-patch A1 source and unchanged I5 runtime.
  The DSP boots; speaker/microphone support is still in progress. No private inputs are required.
- **Build the historical phone-tested M6 snapshot:** [reproduce/m6/](reproduce/m6/README.md).
  After cloning, run `python3 -I tools/reproduce_m6.py --jobs 16`. This fetches pinned public
  inputs and builds the kernel, embedded runtime, raw DTB and BOOT image without private backups.
  It includes the complete diagnostic source and final M6 configuration; build prerequisites and
  remaining runtime limits are documented there.
- **Base:** [ACK](https://android.googlesource.com/kernel/common) branch `android17-6.18`, commit `d9a614fed`
  (2026-10-31), Linux 6.18.33. Built with ACK's clang prebuilt (`clang-r584948c`) via `tools/m22_build.sh`.
- **A50 changes:** [patches/](patches/README.md), 70 patches that apply to that base with `git am`: device tree and
  defconfig, Exynos 9610 clocks, pinctrl, UFS, USB PHY, ACPM, S2MPU09 regulators, thermal, the UFS guard, the ION ABI,
  the `a50-decon` display driver, the Mali kbase, I2C, touchscreen, GPIO keys, hall switches, vibrator and the SCSC Wi-Fi/Bluetooth drivers. Where possible they extend the mainline Samsung drivers. Build steps are in [patches/README.md](patches/README.md).
- **Config:** the `a50_firstlight_defconfig` from the series, plus the Halium/Ubuntu Touch flags in
  [tools/m51/halium.flags](tools/m51/halium.flags).
- The working kernel tree is a local checkout (`src/`, not in this repository). `tools/export_patches.sh` regenerates
  `patches/` from it and checks that the series reproduces the branch exactly. Diagnostic and one-off test patches stay
  with their evidence under [reference/](reference/README.md).

No prebuilt images are published.

## Repository layout

| Path | Contents |
|---|---|
| [docs/](docs/) | Goal, device facts, baseline and restore, [kernel contract](docs/03-kernel-contract.md), gap matrix, plan, workflow, risks, open questions, [decision records](docs/decisions/) |
| [tasks/](tasks/README.md) | One ticket per task, with acceptance criteria |
| [log/](log/) | One file per test session: what changed, what was flashed, the result |
| [reference/](reference/README.md) | Evidence: live device tree, vendor ABI captures, stock vendor extracts, dumps, exported kernel patches |
| [patches/](patches/README.md) | The clean A50 kernel patch series on top of ACK `android17-6.18` (GPL-2.0-only) |
| [reproduce/m6/](reproduce/m6/README.md) | Complete tested M6 diagnostic source/config, pinned dependencies and build instructions |
| [reproduce/m8/](reproduce/m8/README.md) | Current clean M8 driver stack, locked config, runtime and one-command public build |
| [tools/](tools/) | Scripts that build, pack, test and produce the evidence, grouped by milestone |
| `baseline/` | Hashes and sources of the known-good 4.14 system; the images themselves are not committed |
| `src/` | Local kernel trees and build output; ignored by Git |

## Contributing

Issues and pull requests are welcome, especially from people with Exynos 9610 knowledge or an SM-A505F to test on.
Before working on something:
1. Read [CLAUDE.md](CLAUDE.md). It holds the project rules for everyone, human or AI assistant; the project is developed
   with Claude Code and Codex, and Codex starts from [AGENTS.md](AGENTS.md).
2. Read [STATUS.md](STATUS.md) and the ticket it names. A task that isn't in the plan needs a plan change first.
3. Record every phone test in `log/` with its inputs and its rollback result.
4. Don't commit device identifiers (serial numbers, IMEI) or proprietary images.

## License

The project is licensed under the [Apache License 2.0](LICENSE), with these exceptions:
- **Kernel code is GPL-2.0-only** ([LICENSES/GPL-2.0-only.txt](LICENSES/GPL-2.0-only.txt)), like the Linux kernel it
  modifies: the patch series in [patches/](patches/), the kernel snapshot in [reproduce/m6/](reproduce/m6/), every other `.patch` file under `reference/`, and the kernel
  modules in `tools/` that carry a `SPDX-License-Identifier: GPL-2.0` header. Device-tree files are kernel sources
  too: the `.dtb` files under `reference/` are compiled from this project's DT patches, and `reference/stock-dt/` holds
  Samsung's stock DTB/DTBO, built from Samsung's GPL kernel source, with decompiled `.dts` next to each.
- **Third-party material keeps its owner's terms.** This covers files taken from other projects, such as
  [reference/halium-check-kernel-config.sh](reference/halium-check-kernel-config.sh) from Halium, and extracts and logs
  of Samsung's stock firmware under `reference/` (for example `reference/stock-vendor/`), kept as evidence of what
  the kernel must provide.

## Related projects

- [Android Common Kernel](https://android.googlesource.com/kernel/common): the base kernel.
- [Halium](https://halium.org) and [UBports / Ubuntu Touch](https://ubuntu-touch.io): the userspace this port targets.
- The working 4.14 baseline (Samsung/FreshROMs Mint kernel with a50-halium patches) is described in
  [docs/02-baseline.md](docs/02-baseline.md).

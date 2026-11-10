# Galaxy A50 on Linux 6.18

An open effort to run **Ubuntu Touch 26.04 (Halium 11)** on the **Samsung Galaxy A50 (SM-A505F, Exynos 9610)** with a
modern kernel: Google's Android Common Kernel `android17-6.18` (Linux 6.18 LTS) instead of Samsung's 4.14. The stock
Android 11 vendor partition (`A505FDDS9CWA2`) stays unchanged; the new kernel has to provide what it expects.

Why: Samsung's 4.14.194 kernel is out of support, and every newer userspace needs shims for it (Ubuntu 26.04 `tar`
needs `openat2`, for example). Goal, success criteria and non-goals: [docs/00-goal.md](docs/00-goal.md).

> [!WARNING]
> **Experimental. Not for daily use.** Nothing here gives you a usable phone on 6.18 yet: no display, touch, Wi-Fi,
> audio, modem or charging. Testing means flashing the BOOT and DTB/DTBO partitions of your own device, which can leave
> it unbootable until you restore it. The project never writes EFS, SEC_EFS, CPEFS, PARAM, the bootloader or the vendor
> partition, and its UFS write guard (below) enforces that in the kernel, but you use this at your own risk.
> SM-A505F only; no other A50 variant has been tested.

## Status

The 6.18 kernel boots on the phone, runs Halium's init and brings Ubuntu Touch up to systemd multi-user. Root SSH works
over USB networking (RNDIS). Current state and the next action: [STATUS.md](STATUS.md).

| Milestone | What | State |
|---|---|---|
| M0-M1 | Baseline 4.14 system measured, reproducible builds, vendor kernel ABI captured | done |
| M2 | First light: 6.18 boots on the A50 | done |
| M3 | Storage (UFS) and USB gadget | done |
| M4 | Core SoC: 8 CPUs, ACPM, PMIC regulators, power domains, thermal | done; I2C and CPU frequency deferred |
| M5 | Ubuntu Touch userspace: systemd multi-user, SSH over USB | done, with limits below |
| M6 | Android container: binder, ashmem, ION | next |
| M7-M12 | Display/GPU, input, Wi-Fi/Bluetooth, audio, modem, power/charging | planned |

Limits of what M5 proves (details in [log/2026-11-10-M5.4-usb-ssh.md](log/2026-11-10-M5.4-usb-ssh.md)):
- Four services that need Android's hardware layer (`rild`, `ofono`, `bluebinder`, `a50-audio-route`) are masked for the
  test boot. They return in M9-M11.
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

- **Base:** [ACK](https://android.googlesource.com/kernel/common) branch `android17-6.18`, commit `d9a614fed`
  (2026-10-31), Linux 6.18.33. Built with ACK's clang prebuilt (`clang-r584948c`) via `tools/m22_build.sh`.
- **A50 changes:** [patches/](patches/README.md), 35 patches that apply to that base with `git am`: device tree and
  defconfig, Exynos 9610 clocks, pinctrl, UFS, USB PHY, ACPM, S2MPU09 regulators, thermal, and the UFS guard. Where
  possible they extend the mainline Samsung drivers. Build steps are in [patches/README.md](patches/README.md).
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
| [patches/](patches/README.md) | The A50 kernel patch series on top of ACK `android17-6.18` (GPL-2.0-only) |
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
  modifies: the patch series in [patches/](patches/), every other `.patch` file under `reference/`, and the kernel
  modules in `tools/` that carry a `SPDX-License-Identifier: GPL-2.0` header.
- **Third-party material keeps its owner's terms.** This covers files taken from other projects, such as
  [reference/halium-check-kernel-config.sh](reference/halium-check-kernel-config.sh) from Halium, and extracts and logs
  of Samsung's stock firmware under `reference/` (for example `reference/stock-vendor/`), kept as evidence of what
  the kernel must provide.

## Related projects

- [Android Common Kernel](https://android.googlesource.com/kernel/common): the base kernel.
- [Halium](https://halium.org) and [UBports / Ubuntu Touch](https://ubuntu-touch.io): the userspace this port targets.
- The working 4.14 baseline (Samsung/FreshROMs Mint kernel with a50-halium patches) is described in
  [docs/02-baseline.md](docs/02-baseline.md).

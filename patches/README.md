# A50 kernel patch series

The Galaxy A50 changes as one ordered series on top of the Android Common Kernel.

For a **new-clone build of this current M8 stack**, use
[reproduce/m8/](../reproduce/m8/README.md):
`python3 -I tools/reproduce_m8.py --jobs 16`. It verifies the 70-patch tree,
uses a locked full config and reconstructs the current runtime from public
inputs. No existing local kernel checkout or private image is needed.

For the **historical phone-tested M6 diagnostic build**, use
[reproduce/m6/](../reproduce/m6/README.md). It includes the complete test source,
final config, pinned toolchains and public ramdisk bootstrap. This directory
continues to hold the separate clean driver series.

- **Base:** https://android.googlesource.com/kernel/common, branch `android17-6.18`,
  commit `d9a614feddce2e8e68767df1d3421305d26a965b` (2026-10-31, Linux 6.18.33).
- **Series:** `0001` to `0070`. It is the project's clean driver stack:
  - `0001`-`0035` (M2-M5): device tree and defconfig, Exynos 9610 clocks, pinctrl, UFS with the `A50_UFS_SAFE` write
    guard, USB PHY, ACPM, S2MPU09 regulators (read-only), thermal (read-only), and the userdata write allow-list;
  - `0036`-`0040` (M6): tracepoint and Rust build fixes, and the Exynos ION system-heap ABI on native DMA-BUF heaps;
  - `0041`-`0045` (M7): the pinctrl GPIO-interrupt fix, display clocks and DPU SysMMU in the DT, the `a50-decon` fbdev
    driver on the bootloader's display pipeline, and Samsung's Mali r26p0 kbase ported to 6.18 at a fixed GPU clock;
  - `0046`-`0048` (M8): the I2C controllers (buses 0/1/3/4/6) on a fixed PERI clock with CMU_PERI left to the
    bootloader ([ADR-0007](../docs/decisions/ADR-0007-cmu-peri-bootloader-clocks.md)), and I2C in the defconfig;
  - `0049`-`0054` (M8): the Melfas MSS100 touchscreen on mainline `melfas_mip4` (event format 8, a zero-event-size fix,
    the event format from the device tree when the firmware reports none), its DT node, and evdev in the defconfig;
  - `0055`-`0056` (M8): volume up/down and power on mainline `gpio-keys`, with their DT pins and keyboard config.
    K3 verified all three key events; repowerd remains masked until M12, so power-key screen blanking is deferred;
  - `0057`-`0058` (M8): hall switches (`SW_LID` / `SW_MACHINE_COVER`) and vibrator on mainline gpio-keys/gpio-leds,
    with GPIO LEDs/transient trigger config. Vibrator pulses were felt in H1; hall probe is verified, events remain open.
  - `0059`-`0063` (M9): the Samsung SCSC (Maxwell) Wi-Fi/Bluetooth core for Exynos 9610: `0059` imports the 4.14
    sources verbatim, `0060` adapts them to 6.18 (firmware loader, `memory-region`, IRQs by name, `arm_smccc_smc`),
    `0061` adds the WLBT DT nodes and 16 MiB shared memory, `0062` adds a platform op missing from the 4.14 9610 file,
    `0063` enables the core and adds `/vendor/etc/wifi` to `firmware_class.path`. M9.2 W1r2/W1d booted the chip and
    its stock firmware on 6.18 (NULL test service).
  - `0064`-`0066` (M9): the SCSC Wi-Fi driver, station mode on mainline cfg80211/nl80211: `0064` imports the 4.14
    sources verbatim, `0065` adapts them to 6.18 (cfg80211 op adapters, firmware loader, const addresses, timers),
    `0066` applies the custom regulatory domain outside RTNL (fixes a deadlock on first interface up). M9.3 W2s2
    joined a WPA2 network with DHCP, SSH and transfer over Wi-Fi.
  - `0067`-`0069` (M9): SCSC Bluetooth as a native BlueZ device (ADR-0008): `0067` imports the 4.14 sources
    verbatim, `0068` builds them on 6.18 (H4 core on kernel buffers, mainline `h4_recv_buf()` pattern, send-path
    use-after-free fix), `0069` serialises hci0 registration (fixes a workqueue race). M9.4 B2t paired the owner's
    speaker and played audio over A2DP.
  - `0070` (M9): the Wi-Fi driver always creates `/sys/wifi/mac_addr`, so the runtime can pass the factory MAC
    (ADR-0009; the 4.14 driver tied it to Samsung's One UI version macro).
- **Not included:** diagnostic patches and one-off test patches. They stay with their test evidence under `reference/`.
  The Halium/Ubuntu Touch config flags are in `tools/m51/halium.flags`.

## Apply and build

```sh
git clone https://android.googlesource.com/kernel/common ack-common
cd ack-common
git checkout -b a50 d9a614feddce2e8e68767df1d3421305d26a965b
git am /path/to/this/repo/patches/*.patch
make ARCH=arm64 LLVM=1 O=out a50_firstlight_defconfig
make ARCH=arm64 LLVM=1 O=out -j"$(nproc)" Image
```

The small defconfig is for driver bring-up, not the full Ubuntu Touch
configuration. The current full M8 config is
[reproduce/m8/config](../reproduce/m8/config), with a relocatable initramfs
path populated by the public build command above. GPIO LEDs and the transient trigger are enabled for the vibrator;
the SCSC core and Wi-Fi driver (with cfg80211 and rfkill) are built and the firmware search path includes
`/vendor/etc/wifi`. The small defconfig has networking disabled, so Wi-Fi and Bluetooth are enabled only in the
full config, which also builds `hci_uart` H4 and `uinput` and masks `bluebinder` on the command line (ADR-0008).

The historical full config of the M7 stack is
[reference/m75-integration/clean.config](../reference/m75-integration/clean.config) (it covers `0001`-`0045`; for
`0046`-`0054` also set `CONFIG_I2C=y`, `CONFIG_I2C_CHARDEV=y`, `CONFIG_I2C_S3C2410=y`, `CONFIG_INPUT_EVDEV=y`,
`CONFIG_INPUT_TOUCHSCREEN=y` and `CONFIG_TOUCHSCREEN_MELFAS_MIP4=y`, as the defconfig does; for `0055`-`0056`, add
`CONFIG_INPUT_KEYBOARD=y`, `CONFIG_KEYBOARD_GPIO=y` and `# CONFIG_KEYBOARD_ATKBD is not set`);
`tools/m75/build_clean.py` pins that older 45-patch source tree. Use the M8
entry point for the current series.

The project builds with ACK's clang prebuilt (`clang-r584948c`) through `tools/m22_build.sh`, which also embeds the
initramfs and applies the Halium flags. Packing for S-Boot is `tools/m22_pack.sh`. Read `docs/06-workflow.md` before
flashing anything.

## Regenerating

`tools/export_patches.sh` rewrites this series from the local kernel branch `a50-input` and checks that the series
applied to the base reproduces that branch's tree exactly. Re-run it whenever the clean branch changes.

## License

These patches modify the Linux kernel and are licensed GPL-2.0-only, like the kernel itself
([../LICENSES/GPL-2.0-only.txt](../LICENSES/GPL-2.0-only.txt)). Authorship is kept in each patch: several come from
upstream contributors (Linaro, Alexandru Chimac) and keep their original author lines.

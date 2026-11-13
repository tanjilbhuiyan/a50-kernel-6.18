# Open questions: set aside, to check later

Things we saw and chose not to chase, because the current goal did not need the answer. None of them block the plan today. Each entry says what is known and the cheapest way to pick it up.

| # | Question | What we know | Evidence | Cheapest next step |
|---|---|---|---|---|
| 1 | **Why does the boot.img ramdisk not reach 6.18?** | S-Boot reports the correct sizes and tells the kernel `0x89000000`, the same address as 4.14, but the ramdisk is not there when 6.18 starts (the region is zeros or leftover RAM). Worked around by embedding the ramdisk in the kernel. Candidates, all unverified: the smaller kernel image (7.5 MB vs 42.8 MB), our DT | `log/2026-11-10-M3.7-halium-initramfs.md`, `reference/m37-initramfs/2026-11-10-3pt-test1-dump.txt` | Logging-only test: search mapped RAM for the ramdisk bytes. Or pad the kernel to the baseline size (one packing change) |
| 2 | **Why did 6.18 hang once after the USB shell test?** | One clean-image run (2026-11-09 18:20) answered 6/6 commands, then stopped responding and never dumped. The same image ran normally next time. No log | `log/2026-11-08-M3.6-usb.md`, `tasks/M3.6-usb-device-mode.md` | Note whether it recurs. If it does, keep the USB shell open and capture what stopped |
| 3 | **Why does PMIC register `0x00` differ?** | Read `0x00` on 6.18 through ACPM; the baseline's debug file reads `0x0c`. The LDO registers match exactly through the same path | `log/2026-11-08-M3.6-usb.md` (Test 4) | Check which page the baseline debug file uses, during the M4 PMIC work |
| 4 | **Why is `GUCTL` different from the working phone?** | 6.18 `0x02000010`, 4.14 `0x03c24010` (includes Samsung's `REFCLKPER` setting). USB works at high speed without it | `reference/m36-usb/2026-11-09-baseline-regs-414.txt`, `reference/m36-usb/2026-11-09-test9c-dump.txt` | Revisit if USB is unstable under load |
| 5 | **Why is USB-C seen differently at home and at the office?** | On the baseline the phone reports `TA` (charger) at home; at the office the same phone enumerated over USB-C. Download mode and 6.18 USB work in both places | `log/2026-11-10-M3.7-halium-initramfs.md`, `docs/02-baseline.md` known issue #1 | Compare the laptop port and power state when the baseline USB link matters again |
| 6 | **Why was Samsung's `lkmauth` message missing from dmesg?** | The source prints it when a module is refused, but dmesg showed nothing, even with an immediate read. The refusal itself is certain: the function always fails | `log/2026-11-08-M3.6-usb.md` | Low value. Only if module loading on the baseline ever matters |
| 8 | **Why do the real I2C controllers freeze 6.18?** | With `samsung,s3c2440-i2c` enabled, the phone froze before the USB gadget twice (2026-11-10): first with I2C 0/1/3/4/6 plus keys, then with only I2C 0 and 1. No log survives. Same pins worked with bit-banged I2C in M3.6, and PWM on the same clock unit works. Candidates, all unverified: an interrupt storm at probe, register access with the gate off, the `i2cdetect` probing in the test init | `log/2026-11-10-M4.4-buses.md`, `tasks/M4.4-i2c-pwm-keys-dma.md` | To be worked again (owner, 2026-11-10): bus 0 only without probing in the init; then the hardware watchdog to keep a log through a freeze (`tasks/M4.4-i2c-pwm-keys-dma.md`) |
| 7 | **What takes about 15 s before init on 6.18?** | Seen since M3.5; the cause was never identified | `STATUS.md` history, M3.5 and M3.6 dumps | Boot-time logging when boot speed matters |

## M5.4 USB follow-up (2026-11-10; M12)
The tested -f -r runtime profile provides working USB SSH and packaged DHCP,
but legacy usb-tethering/ISC dhcpd also runs on the same gadget/interface.
Both DHCP processes listen on UDP 67; the successful test-2 lease was issued
by Busybox udhcpd. Native cable/charger detection and single-owner gadget/DHCP
integration remain M12. Before disabling legacy usb-tethering, establish which
component creates the initial configfs scaffold. Evidence:
log/2026-11-10-M5.4-usb-ssh.md and reference/m54-usb-ssh/netdevices-live-dhcp.txt.

## M6 runtime follow-up (2026-11-14)

- **TEEGRIS/TZDEV and secure services:** the stock TEEGRIS post-fs action
  waits for a daemon that cannot become ready on the current port. M6.4
  defers that RC through a read-only per-boot bind, without modifying vendor
  or faking readiness. TEE-dependent security/DRM functionality and the six
  reserved/secure heaps remain unsupported. Schedule a real driver/storage
  design before a consumer requires them; normal allocator startup does
  not establish secure allocation support.
- **Android task profiles on cgroup v2:** the container uses native v2,
  but the Android 11 legacy cgroups/profile configuration still emits
  setup errors for paths such as /acct and /dev/cpuset. Current boot and
  allocator checks do not prove scheduling/QoS compatibility. Review
  consumer requirements during M7 and native controller/uclamp/profile
  mapping during power/performance work; do not re-enable v1 as a shortcut.
- **Power masks and the M11 gate:** repowerd, a50-enable-autosuspend and
  sleep.target remain diagnostic masks. The existing activation script
  explicitly enables Android automatic suspend, which the interface-only
  M6.2 tests did not validate. Reassess with real power/suspend prerequisites
  before removal. Resolved 2026-11-14 (owner): the three masks are approved
  until M12, whose DoD now removes them; M11's gate covers the M5 HAL masks only.

Evidence: `log/2026-11-14-M6.4-runtime.md`, `reference/m64-runtime/`.

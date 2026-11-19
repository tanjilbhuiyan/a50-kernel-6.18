# M9.1 — SCSC Wi-Fi/Bluetooth contract and port boundary (A50, stock vendor A505FDDS9CWA2)

Evidence (all 2026-11-19, stock 4.14.194 running, nothing flashed):
- `c1-stock-snapshot.txt`: read-only phablet capture (vendor firmware tree, device nodes, netdevs, rfkill, processes,
  units, mounts, interrupts). `vendor-etc-wifi.sha256`: hashes of every file in `/vendor/etc/wifi`.
- `c4-service-restart.txt` / `c4-state.txt`: Wi-Fi rfkill block/unblock (phablet, no root, owner approved) with the
  kernel log streamed live; redacted by `tools/m91/redact_c4.py` (SSID, BSSID/MAC, IP addresses).
- Source: `src/samsung-a50-4.14-aa17rf2` (`drivers/misc/samsung/scsc`, `scsc_bt`, `drivers/net/wireless/scsc`),
  baseline config `reference/baseline-build/config`, stock DT `reference/stock-dt/dt.dtb.0.dts`.
- An owner-initiated stock reboot (C3, `tools/m91/capture_boot_dmesg.sh`) did **not** capture the chip boot: the stock
  `mms_ts` "packet size = 0" stream fills the 1 MiB ring (`CONFIG_LOG_BUF_SHIFT=20`) before SSH is up at 19 s.

Policy for M9 (owner, 2026-11-19, and `prefer-modern` rule): use 6.18 frameworks; port only what S4/S8 need; keep a
Samsung mechanism only when a named consumer requires it.

## 1. Hardware (stock DT, measured interrupts)

| Item | Stock value | Source |
|---|---|---|
| Node | `scsc_wifibt@119c0000`, `compatible = "samsung,scsc_wifibt"`, reg `0x119c0000` size `0x180` (WLBT mailbox) | DT l.5967 |
| IRQs | SPI 42 MBOX, SPI 28 ALIVE, SPI 72 WDOG, SPI 73 CFG_REQ, level high | DT |
| IRQs requested on stock | GIC 74 (MBOX, 1450-2825 counts), GIC 104 (WDOG, 0), GIC 105 (CFG_REQ, **1 per boot**) | c1, c4 `/proc/interrupts` |
| ALIVE | not requested (`CONFIG_SCSC_ENABLE_ALIVE_IRQ` unset) | platform_mif_9610.c:572 |
| PMU | `exynos-pmu` syscon `0x11860000`: `WLBT_CTRL_NS` 0x50 (RESET_SET bit0, MASK_PWR_REQ bit18), `WLBT_CTRL_S` 0x54 (WLBT_START bit0), `WLBT_DEBUG` 0x5c, `CENTRAL_SEQ_WLBT_STATUS` 0x184 | mif_reg_S5E9610.h |
| Bus windows | syscons `baaw_p_wlbt` 0x12050000 (0xff), `dbus_baaw` 0x14C20000, `pbus_baaw` 0x14C30000, `wlbt_remap` 0x14C50000 (0x300 each), `boot_cfg` 0x14C60000 (0x1200) | DT l.5932-5965 |
| Shared memory | `reserved-memory/wifibt_if`, `compatible = "exynos,wifibt_if"`, **dynamic, size 16 MiB, no reg**; mapped for WLBT at 0x80000000 by DBUS_BAAW | DT l.1696; platform_mif_9610.c:1658 |
| Secure call | EL3 SiP SMC `0x82000710` (`SMC_CMD_CONN_IF`), arg `(1<<32) | 0` = set CONN TZPC non-secure, issued in the CFG_REQ handler. EL3 monitor, **not TEEGRIS** (ADR-0004 does not cover it) | platform_mif_9610.c:743, include/linux/smc.h:113 |
| Clocks / power domains | none through the clock framework or pm_runtime (0 uses); power is the PMU sequence above | source grep |
| smapper | DT has 11 banks; `CONFIG_SCSC_SMAPPER` unset on stock → unused | baseline config |
| qos_table | feeds legacy Exynos `pm_qos` classes (MIF/INT/CL0/CL1 minimum); stock logs "MIF 0 INT 0 CL0 0 CL1 0" | c4 |

6.18 today: no SCSC code in the tree; `a50_firstlight_defconfig` enables no CFG80211/RFKILL/BT; the 6.18 A50 DT omits
`wifibt_if` (comment "dynamic pools omitted") and the five WLBT syscons. The PMU syscon node exists
(`samsung,exynos9610-pmu`, `syscon`).

Related but separate: `abox_bt` (ABOX Bluetooth audio path, M10), GNSS and FM (`fm@14AC0000`) share the WLBT/PMU
area; out of M9 unless S8 proves it needs them.

## 2. Firmware and data files (stock vendor, read-only)

- Location `CONFIG_SCSC_CORE_FW_LOCATION="/vendor/etc/wifi"`; on Ubuntu Touch `/vendor` is the stock vendor mount and is
  readable on the host.
- Variant in use: `mx140` (module default `firmware_variant`; `mx140_t*` = test firmware, not used).
  `mx140.bin` 1835952 B sha256 `ba6dea2d…f7d92bd`. Runtime: `WLBT FW: O|7358|2021-11-15 11:50:16 UTC|leman_s620|
  S620_E9610_R3-1_Y21W46A`, driver `11.19.0.18.0`, `platform.txt` = `leman_s620_a50` (c4, c1).
- Wi-Fi service start loads `mx140_wlan.hcf` and `mx140_wlan_sw.hcf` (MIB), tries the optional `mx140_localmib.hcf`
  (absent, -2), and reads `slsi_reg_database.bin` (regulatory, 252 countries) (c4).
- Bluetooth: `mx140_bt.hcf`; Bluetooth address read from `CONFIG_SCSC_BT_ADDRESS_FILENAME=/mnt/vendor/efs/bluetooth/bt_addr`
  (EFS, mounted rw by Halium on the host, c1). **6.18 may only read it; EFS is never written (CLAUDE.md rule 5).**
- Wi-Fi MAC: "MAC address from sysfs" (c4) — the driver takes it from `/sys/wifi/mac_addr` (driver-created sysfs,
  owner 1010, written by userspace before the interface opens). The writer is **unverified** (candidates: vendor Wi-Fi
  HAL or a Samsung helper reading `/mnt/vendor/efs/wifi/.mac.info`). The driver's own default `/efs/wifi/.mac.info`
  does not exist on the host (c1).
- Writes by the stock driver: `/data/vendor/conn/.wifiver.info` through the `wlbtd` daemon (generic netlink, c4) and
  other `/data/vendor/conn/*.info` files; memdump/log collection to `/data/vendor/log/wifi`.

## 3. Start-up sequence

Chip boot (**source-derived; not measured** — the ring is overwritten before SSH, and an rfkill toggle keeps the chip up):
1. Probe maps the mailbox, looks up the six syscons, takes the 16 MiB `wifibt_if` region.
2. First service open (`mxman_open`) loads `mx140.bin` into shared memory.
3. PMU: set `MASK_PWR_REQ`, release `WLBT_RESET_SET`, set `WLBT_START`; wait for CFG_REQ (timeout).
4. CFG_REQ IRQ: SMC CONN TZPC → `WLBT_REMAP` = 0x80000000>>12 → `CHIP_VERSION_ID` EMA bits → DBUS_BAAW (WLBT 0x80000000
   → shared memory) → six PBUS_BAAW windows (CP/SHUB mailboxes, USI CMG00, SYSREG CMGP, GPIO CMGP, SHUB) → `boot_cfg`
   keep-alive patch → `BOOT_CFG_ACK` → clear `MASK_PWR_REQ`.
5. Firmware runs; the measured CFG_REQ count of 1 per boot (c1 after 1638 s, c4 after the toggle) shows the chip boots
   once and stays up while any service (users≥1) holds it.

Wi-Fi service start (**measured**, c4 247.168-247.39 s): `slsi_start` → `scsc_mx_service_open` ("Already opened:
users=2") → MIB files → allocate mifram, HIP4 init (config 8 KiB, MIB 32 KiB, TX data 1 MiB, TX ctl 64 KiB, RX 1 MiB,
total 2203648 B; 512 data / 32 ctl slots) → `scsc_mx_service_start` → `SM_MSG_START_CFM` (~170 ms) → SAP versions
(MLME 14.7, MA 14.1, DBG 13.3, TEST 14.0) → wiphy update (2.4 + 5 GHz, HT + VHT) → regulatory → wlbtd file write →
MAC from sysfs → `swlan0`/`wlan0` open. Stop: `slsi_net_stop` → service stop/close → `mxman_close` (users 2→1).
Reconnect to WPA2 AP, DHCP: 10 s after unblock (c4).

## 4. Consumers on Ubuntu Touch (measured, c1)

| Consumer | Uses | 6.18 relevance |
|---|---|---|
| NetworkManager + host `wpa_supplicant` (nl80211) | `swlan0` (connected, `managed`), `wlan0`, `p2p0` on one `phy0` | **S4 path**. Only nl80211/cfg80211 needed |
| Android `wifi@1.0`, `vendor.samsung.hardware.wifi@2.0`, `wificond` (container) | nl80211 vendor commands, Android private ioctl (`SIOCDEVPRIVATE+1`) | not needed for S4; keep failing gracefully |
| `wlbtd` (container, uid 1010) | generic netlink family of `scsc_wlbtd.c` (file writes, `ro.build.type`, moredump helper) | avoid in-kernel dependency; drop the calls or make them optional |
| Android `bluetooth@1.0` HAL → `/dev/scsc_h4_0` → `bluebinder` → `vhci` → `hci0` → `bluetoothd` | H4 byte stream; only `TCGETS/TCSETS` handled (no-op) | current S8 path; see boundary B |
| rfkill | `phy0` wlan (soft off/on works for phablet via `/dev/rfkill`, group android_input), `hci0` bluetooth (from vhci) | upstream rfkill |
| `/dev/mx_0_*`, `mx_client_test_0`, `scsc_log_collector_0`, `scsc_ant_0`, `/sys/wifi/memdump`, wifilogger kthreads | debug, ANT, log collection | drop |

`/dev/scsc_h4_0` is `root:root 0600` on the host (host udev; vendor ueventd rule `bluetooth 0660` not applied), yet the
HAL in the container runs; how the container gets access is unverified. No ioctls were observed on SCSC nodes in M1.3
(`reference/contract/wifi_bt.md`); open-time ioctls and 32/64-bit HAL builds are not measured.

Ubuntu Touch connects on `swlan0`, the name stock config gives the AP interface (`CONFIG_SCSC_AP_INTERFACE_NAME`);
why NetworkManager uses it rather than `wlan0` is unverified. A 6.18 port can expose a single station interface `wlan0`.

## 5. Size and 4.14 → 6.18 gaps

Lines (all .c/.h): core `scsc` 43052, `scsc_bt` 7104, `net/wireless/scsc` 92770, `include/scsc` 3297 (several SoC
variants and optional features; compiled subset smaller). Old mechanisms found in the source, with the 6.18 replacement:

| 4.14 mechanism | Where | 6.18 replacement |
|---|---|---|
| `set_fs(KERNEL_DS)` + `filp_open`/`vfs_read` for firmware/MIB/address files | mx140_file.c, mxman.c, log collector | `request_firmware`/`firmware_request_nowarn` (firmware search path to `/vendor/etc/wifi`, e.g. `firmware_class.path`), `kernel_read_file_from_path` only for the EFS address read |
| Android `wake_lock` | 234 uses | `wakeup_source` |
| Exynos `pm_qos` classes from `qos_table` | mifqos, platform_mif | drop (no CPU/bus DVFS in 6.18 port yet, M4.7 dropped); revisit with M12 devfreq |
| `exynos_smc` | platform_mif_9610.c | `arm_smccc_smc` (SiP id unchanged) |
| `exynos_soc_info` | 30 uses | DT compatible / constant |
| `ioremap_nocache`, proc `file_operations`, old timers | various | `ioremap`, `proc_ops`, `timer_setup` |
| Samsung cfg80211/nl80211 patch `CONFIG_CFG80211_SLSI_SAE` | 4.14 net/wireless/nl80211.c | upstream SAE (external auth / SAE offload in 6.18 cfg80211); no core cfg80211 patch |
| GSCAN, NAN, WES/NCHO, RTT, LLS, enhanced logging, wifilogger, ANT, FM, mx_client_test, mmap/gdb, log collection | Kconfig options on stock | not ported (Android-HAL or debug features; S4/S8 do not need them) |

The driver's cfg80211 ops were written for 4.14; 6.18 changed many signatures (multi-link `link_id` arguments, key and
beacon parameter structs). That adaptation is the bulk of M9.3.

## 6. Port boundary (proposal)

- **A. Core (M9.2):** `platform_mif_9610` + mxman, mif ram/mbox/intrbit/stream, mxmgmt/mxlog transports, panicmon,
  fw image/header, firmware file access via `request_firmware`, minimal logring → `printk`. DT: `wifibt_if` 16 MiB
  reserved pool, the five WLBT syscons, the `scsc_wifibt` node. No services. Acceptance: chip boots (CFG_REQ handled,
  SMC returns 0, firmware version line), mailbox IRQ counts rise, no faults, stock restore clean.
- **B. Bluetooth (M9.4), modern-first:** stock already contains `scsc_bluez.c` (`CONFIG_SCSC_BT_BLUEZ`, 337 lines),
  which registers a native `hci_dev` on top of the SCSC BT service. Preferred: native `hci_dev` → BlueZ directly
  (no Android BT HAL, no bluebinder, no vhci); bluebinder then stays inactive. Fallback only if the native path cannot
  meet S8: `/dev/scsc_h4_0` + bluebinder as on stock. Decision recorded in M9.4 with evidence.
- **C. Wi-Fi (M9.3):** `net/wireless/scsc` reduced to station mode + scan + WPA2/WPA3-SAE via upstream cfg80211/nl80211,
  netdev `wlan0` (P2P/AP later only if needed). MAC: read-only from EFS `.mac.info` in-kernel, or the existing sysfs
  override if a userspace writer is identified; never write EFS. No wlbtd dependency.
- Not in M9: smapper, pm_qos, abox_bt, FM, GNSS, ANT, debug devices.

## 7. Boot-test plan (each one variable, runner `tools/m32_run_test.sh`, owner present)

1. **W1 core boot:** A only, built in, `CONFIG_SCSC_*` minimal; capture probe, reserved-memory base, syscon lookups,
   CFG_REQ/SMC result, firmware version, `/proc/interrupts`; timed dump as usual. Failure stops at the step that failed
   (e.g. SMC rejected, CFG_REQ timeout).
2. **W2 Wi-Fi scan:** + C up to netdev and scan (`iw dev wlan0 scan`, read-only, results counted not saved).
3. **W3 S4:** NetworkManager association to the owner's AP, SSH over Wi-Fi; credentials and SSIDs never saved.
4. **B1/B2 Bluetooth:** native hci_dev up (`btmgmt info`), then S8 pairing and A2DP.

## 8. Unresolved (must be closed by the ticket that needs them; no readiness assumed)

1. `wifibt_if` placement and alignment constraints (stock base needs root `/proc/iomem`; the DT gives only size).
2. Whether the EL3 monitor accepts `SMC_CMD_CONN_IF` from the 6.18 kernel (expected, unverified).
3. Chip boot timing and log lines (not captured; W1 records them).
4. Who writes `/sys/wifi/mac_addr` on stock; whether firmware needs anything else from EFS.
5. Which second MX user keeps the chip up (users=2 at Wi-Fi open with Bluetooth soft-blocked).
6. Container access to `/dev/scsc_h4_0` on stock and HAL open-time ioctls (only relevant if fallback B is needed).
7. Whether 6.18's cfg80211 SAE path covers the firmware's SAE model (stock used a Samsung nl80211 patch).
8. Whether firmware requires any PBUS window peers (CP/SHUB mailboxes, CMGP) to be powered; the modem (M11) and
   sensor hub are not running on 6.18.

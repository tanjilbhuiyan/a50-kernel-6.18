# ADR-0008 — Bluetooth through a native BlueZ HCI device instead of the Android HAL and bluebinder

Status: **Accepted** (2026-11-20, owner chose "Native BlueZ (Recommended)" for M9.4)

## Context
On stock Ubuntu Touch the A50 reaches BlueZ through Android: the vendor `android.hardware.bluetooth@1.0` HAL in the
container opens `/dev/scsc_h4_0` (SCSC Bluetooth H4 byte stream), and `bluebinder` bridges the HAL to the kernel's
virtual HCI (`vhci`) for `bluetoothd` (`reference/m91-scsc/contract.md` §4). The plan's M9 DoD names that path
("the M5 runtime mask of `bluebinder` is removed"; M9.4 "bluebinder reaches a stable operational state").

The stock 4.14 SCSC source also contains `scsc_bluez.c` (`CONFIG_SCSC_BT_BLUEZ`, 337 lines): it registers the SCSC
Bluetooth service as a normal Linux `hci_dev`, so BlueZ talks to the chip without Android in between. Stock built
it **off** (`reference/baseline-build/config`), so it has never run on this phone.

The project prefers 6.18-native mechanisms over Android-era bridges where possible (owner, 2026-11-10 and
2026-11-19). M9.2/M9.3 already run the SCSC core and Wi-Fi on mainline frameworks.

## Decision
1. M9.4 ports the SCSC Bluetooth service with the native `hci_dev` (`scsc_bluez.c`) as the BlueZ interface.
   `bluetoothd` uses `hci0` directly.
2. The Android Bluetooth HAL and `bluebinder` are not in the 6.18 Bluetooth path. On 6.18 `bluebinder` stays
   inactive (the M9 DoD item "bluebinder mask removed" is replaced by "Bluetooth works through BlueZ without
   bluebinder; bluebinder is disabled cleanly, not crash-looping").
3. Fallback: if the native path cannot meet S8 (pairing and A2DP playback), the `/dev/scsc_h4_0` + bluebinder path
   is ported instead, through a new ADR.

## Consequences
- Fewer moving parts: no HAL binder round-trips or vhci bridge; standard BlueZ tools (`btmgmt`, `bluetoothctl`)
  see the controller directly.
- Untested on this phone even on stock: firmware/host-interface behaviour of `scsc_bluez.c` must be proven on 6.18.
- The Bluetooth address: stock reads `/mnt/vendor/efs/bluetooth/bt_addr`. EFS is never written; whether the kernel
  may read it, or userspace sets the public address (BlueZ `set_bdaddr`/`btmgmt public-addr`), is decided in M9.4.
- `docs/05-plan.md` M9 DoD and the `CLAUDE.md` ADR index must be updated to reference this ADR (deferred on
  2026-11-20 only because both files had uncommitted edits from another session).

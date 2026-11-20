# ADR-0009 — Read the factory Wi-Fi/Bluetooth addresses from EFS through a transient read-only mount

Status: **Accepted** (2026-11-20; owner: "ok, then first option it is" and "Yes, transient ro mount")

## Context
CLAUDE.md rule 5 says never touch EFS. The 6.18 runtime (M6.4, `mount_android_safe.sh`) therefore skips the EFS,
SEC_EFS and CPEFS mounts entirely, and neither 6.18 SCSC driver reads EFS (M9.3, M9.4). As a result the Wi-Fi MAC and
the Bluetooth address are random on every 6.18 boot: routers see a new device each boot and Bluetooth pairings neither
survive a reboot nor carry over between stock and 6.18 (BlueZ keys pairings by the adapter address).

Stock keeps EFS mounted read-write and passes the same two values to the drivers from userspace: the Wi-Fi driver
reported "MAC address from sysfs" (`/sys/wifi/mac_addr`, M9.1 C4) and the Bluetooth driver takes the
`bluetooth_address` module parameter. The files are `/mnt/vendor/efs/wifi/.mac.info` and
`/mnt/vendor/efs/bluetooth/bt_addr` on stock (both 17 bytes, `xx:xx:xx:xx:xx:xx`; values not recorded).

## Decision
One narrowly scoped exception to rule 5, read-only:
1. A per-boot runtime hook (staged in `/run` by the 6.18 initramfs, like ADR-0005/0006), ordered before urfkill,
   bluetoothd and NetworkManager, mounts the EFS partition **read-only with `noload`** (no journal replay) and
   `nodev,nosuid,noexec` at a private `/run/a50-efs`, reads only `wifi/.mac.info` and `bluetooth/bt_addr`, and
   unmounts immediately.
2. It refuses (and leaves the random fallback in place) unless the partition resolves to the audited `/dev/sda3`, the
   mount point is empty and unused, and the resulting mount is read-only. Values must match `xx:xx:xx:xx:xx:xx`.
3. It writes the Wi-Fi MAC to `/sys/wifi/mac_addr` and the Bluetooth address to
   `/sys/module/scsc_bt/parameters/bluetooth_address`. It never writes, creates, renames or remounts anything on EFS,
   and never mounts it where Android or other services can see it. It logs success/failure, never the values.
4. SEC_EFS and CPEFS stay untouched; no other EFS file is read; the kernel drivers still do not access EFS.

## Consequences
- Stable, factory addresses on 6.18: the same identity as stock for routers and Bluetooth peers; pairings made on one
  kernel are recognised on the other (shared userdata).
- EFS is mounted for well under a second per boot, read-only with no journal replay — stricter than stock.
- Rule 5 stays in force for everything else; any further EFS access needs a new ADR.
- `CLAUDE.md` ADR index and `docs/05-plan.md` to reference ADR-0009 (pending, as for ADR-0008, until another
  session's uncommitted edits to those files are resolved).

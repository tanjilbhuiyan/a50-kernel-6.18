#!/bin/sh
# ADR-0009: pass the factory Wi-Fi MAC and Bluetooth address from EFS to the 6.18 SCSC drivers.
# Transient read-only mount (ro,noload,nodev,nosuid,noexec) of the audited EFS partition at a private /run path,
# read two 17-byte files, unmount immediately. Never writes to EFS. Logs outcome only, never the values.
# On any refusal the drivers keep their random fallback.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
M=/run/a50-efs
log() { echo "a50-efs-addresses: $*" > /dev/kmsg 2>/dev/null; echo "a50-efs-addresses: $*"; }
mac_ok() { echo "$1" | grep -q -E '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$'; }

. /usr/lib/lxc-android-config/common.sh 2>/dev/null
dev=$(find_partition_path efs 2>/dev/null)
[ "$(readlink -f "$dev")" = /dev/sda3 ] || { log "REFUSE: efs partition is not the audited /dev/sda3"; exit 0; }
grep -q ' /dev/sda3 \|^/dev/sda3 ' /proc/mounts && { log "REFUSE: efs already mounted elsewhere"; exit 0; }
mkdir -p "$M" && chmod 0700 "$M"
mountpoint -q "$M" && { log "REFUSE: $M already a mount point"; exit 0; }
mount -t ext4 -o ro,noload,nodev,nosuid,noexec /dev/sda3 "$M" || { log "REFUSE: read-only mount failed"; exit 0; }
case ",$(findmnt -n -o OPTIONS -M "$M")," in
    *,ro,*) ;;
    *) umount "$M"; log "REFUSE: mount is not read-only (unmounted)"; exit 0;;
esac
wifi=$(head -c 64 "$M/wifi/.mac.info" 2>/dev/null | tr -d '\r\n ')
bt=$(head -c 64 "$M/bluetooth/bt_addr" 2>/dev/null | tr -d '\r\n ')
umount "$M" && rmdir "$M"
log "efs mounted read-only, 2 files read, unmounted"

if mac_ok "$wifi" && [ -w /sys/wifi/mac_addr ]; then
    printf '%s' "$wifi" > /sys/wifi/mac_addr && log "wifi: factory MAC passed to driver" || log "wifi: write failed"
else
    log "wifi: no valid MAC (driver keeps random fallback)"
fi
P=/sys/module/scsc_bt/parameters/bluetooth_address
if mac_ok "$bt" && [ -w "$P" ]; then
    printf '0x%s' "$(echo "$bt" | tr -d ':')" > "$P" && log "bluetooth: factory address passed to driver" || log "bluetooth: write failed"
else
    log "bluetooth: no valid address (driver keeps random fallback)"
fi
exit 0

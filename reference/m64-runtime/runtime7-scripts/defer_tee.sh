#!/bin/sh
# Per-boot LXC mount hook: defer unported TEEGRIS without claiming readiness.
set -eu
umask 077
target="${LXC_ROOTFS_MOUNT:?}/vendor/etc/init/teegris_v3.rc"
expected=b5995dafd91128e971edd0b6098d9145c35b2468eb46d81e1517183a6fa0ad64
actual=$(sha256sum "$target")
[ "${actual%% *}" = "$expected" ] || {
    echo 'A50M64: REFUSE: unexpected TEEGRIS RC input' >&2
    exit 1
}
source=/run/a50-m64/teegris-unported.rc
printf '# M6.4: TEEGRIS/TZDEV unported; no Ready property or secure-storage emulation.\n' > "$source"
chmod 644 "$source"
mount --bind "$source" "$target"
mount -o remount,bind,ro "$target"
echo 'A50M64: deferred TEEGRIS action; security HAL readiness remains unset'

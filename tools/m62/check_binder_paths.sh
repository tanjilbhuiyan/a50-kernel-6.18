#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Exercise the BinderFS mount and aliases used by packaged Halium startup.
set -eu
smoke=${1:?usage: check_binder_paths.sh BINDER_SMOKE_BINARY}
made_dir=0
made_mount=0
made_links=""
cleanup() {
    for node in $made_links; do
        unlink "/dev/$node"
    done
    if [ "$made_mount" = 1 ]; then umount /dev/binderfs; fi
    if [ "$made_dir" = 1 ]; then rmdir /dev/binderfs; fi
}
trap cleanup EXIT

if [ ! -d /dev/binderfs ]; then
    mkdir /dev/binderfs
    made_dir=1
fi
if findmnt -rn --mountpoint /dev/binderfs > /dev/null; then
    test "$(findmnt -rn -o FSTYPE --mountpoint /dev/binderfs)" = binder
else
    mount -t binder -o stats=global binder /dev/binderfs
    made_mount=1
fi
for node in binder hwbinder vndbinder; do
    if [ -e "/dev/$node" ] || [ -L "/dev/$node" ]; then
        test "$(readlink -f "/dev/$node")" = "/dev/binderfs/$node"
    else
        ln -s "/dev/binderfs/$node" "/dev/$node"
        made_links="$node $made_links"
    fi
    test -c "/dev/$node"
    printf '/dev/%s -> %s\n' "$node" "$(readlink -f "/dev/$node")"
done
"$smoke" /dev/binder /dev/hwbinder /dev/vndbinder
cleanup
trap - EXIT
echo 'PASS: Halium Binder device paths'

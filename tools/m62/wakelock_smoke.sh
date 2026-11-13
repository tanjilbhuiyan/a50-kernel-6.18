#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

for unit in repowerd.service a50-enable-autosuspend.service sleep.target; do
    load_state=$(systemctl show -p LoadState --value "$unit")
    active_state=$(systemctl show -p ActiveState --value "$unit")
    printf '%s load=%s active=%s\n' "$unit" "$load_state" "$active_state"
    test "$load_state" = masked
    test "$active_state" = inactive
done
test ! -e /sys/power/autosleep
test -w /sys/power/wake_lock
test -w /sys/power/wake_unlock
printf 'available sleep states: '
cat /sys/power/state

name="a50-m62-wakelock-$$"
active=/sys/power/wake_lock
inactive=/sys/power/wake_unlock
cleanup() {
    printf '%s\n' "$name" > "$inactive"
}

printf '%s\n' "$name" > "$active"
trap cleanup EXIT
grep -qw "$name" "$active"
printf '%s manually acquired\n' "$name"
printf '%s\n' "$name" > "$inactive"
if grep -qw "$name" "$active"; then
    echo 'Lock remains active after release' >&2
    exit 1
fi
grep -qw "$name" "$inactive"
printf '%s manually released\n' "$name"

# The kernel interface takes the timeout in nanoseconds.
printf '%s 5000000000\n' "$name" > "$active"
grep -qw "$name" "$active"
attempt=0
while grep -qw "$name" "$active"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo 'Timed lock failed to expire within ten seconds' >&2
        exit 1
    fi
    sleep 0.2
done
grep -qw "$name" "$inactive"
printf '%s timed acquisition expired\n' "$name"
cleanup
trap - EXIT
echo 'PASS: native wakelock acquire, release and timeout'

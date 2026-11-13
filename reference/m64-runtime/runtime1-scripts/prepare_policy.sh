#!/bin/sh
# Runs after the packaged A50 prepare unit, immediately before normal LXC start.
set -eu
config=/var/lib/lxc/android/config
[ "$config" -ef /run/a50-android/config ] || {
    echo 'A50M64: REFUSE: packaged runtime config overlay is missing' >&2
    exit 1
}
[ "$(findmnt -n -o FSTYPE -T /sys/fs/cgroup)" = cgroup2 ] || {
    echo 'A50M64: REFUSE: expected unified cgroup v2' >&2
    exit 1
}
if grep -q '^lxc.cgroup2.devices\.' "$config"; then
    echo 'A50M64: REFUSE: unexpected existing device policy' >&2
    exit 1
fi
cat >> "$config" <<'EOF'

# M6.4: guest storage uses mounted filesystems; no raw block writes or mknod.
lxc.cgroup2.devices.deny = b *:* wm
lxc.log.level = DEBUG
lxc.log.file = /run/a50-m64/lxc.log
EOF
echo 'A50M64: installed raw block write/mknod deny policy in runtime config'

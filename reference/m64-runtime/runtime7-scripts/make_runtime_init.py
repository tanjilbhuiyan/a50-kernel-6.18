#!/usr/bin/env python3
"""Stage M6.4 scripts and unit drop-ins in /run before the tested handoff."""
from pathlib import Path
import difflib
import subprocess
import sys

repo = Path(__file__).resolve().parents[2]
output = repo / (sys.argv[1] if len(sys.argv) > 1 else 'src/m64')
output.mkdir(parents=True, exist_ok=True)
entries = (repo / 'src/m54/embed-force.list.in').read_text().splitlines()
entry, = [line for line in entries if line.startswith('file /init ')]
source = Path(entry.split()[2])
original = source.read_text()
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1
insertion = '''# M6.4: runtime-only Android mount and device policy.
mkdir -p "${rootmnt}/run/a50-m64" \\
    "${rootmnt}/run/systemd/system/mount-android-partitions.service.d" \\
    "${rootmnt}/run/systemd/system/lxc-android-config.service.d"
busybox cp /a50/m64/*.sh "${rootmnt}/run/a50-m64/"
cat > "${rootmnt}/run/systemd/system/mount-android-partitions.service.d/90-a50-safe.conf" <<'A50M64_UNIT'
[Service]
ExecStart=
ExecStart=/bin/sh /run/a50-m64/mount_android_safe.sh
StandardOutput=append:/run/a50-m64/mount.log
StandardError=append:/run/a50-m64/mount.log
A50M64_UNIT
cat > "${rootmnt}/run/systemd/system/lxc-android-config.service.d/90-a50-policy.conf" <<'A50M64_UNIT'
[Unit]
Requires=a50-container-prepare.service
After=a50-container-prepare.service
[Service]
ExecStartPre=/bin/sh /run/a50-m64/prepare_policy.sh
A50M64_UNIT
busybox chroot "${rootmnt}" /bin/sh /run/a50-m64/runtime_status.sh </dev/null >"${rootmnt}/dev/kmsg" 2>&1 &
'''
updated = original.replace(handoff, insertion + handoff)
out = output / 'halium-init-runtime'
out.write_text(updated)
subprocess.run(['sh', '-n', str(out)], check=True)
entries[entries.index(entry)] = entry.replace(str(source), str(out), 1)
entries.append('dir /a50/m64 0755 0 0')
for name in ('mount_android_safe.sh', 'prepare_policy.sh', 'runtime_status.sh', 'defer_tee.sh'):
    path = repo / 'tools/m64' / name
    subprocess.run(['sh', '-n', str(path)], check=True)
    snapshot = output / 'payload' / name
    snapshot.parent.mkdir(exist_ok=True)
    snapshot.write_bytes(path.read_bytes())
    entries.append(f'file /a50/m64/{name} {snapshot} 0644 0 0')
(output / 'embed-runtime.list.in').write_text('\n'.join(entries) + '\n')
delta = 'init-delta.patch' if len(sys.argv) == 1 else f'{output.name}-init-delta.patch'
(repo / 'reference/m64-runtime' / delta).write_text(''.join(
    difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                         fromfile='halium-init-m54', tofile='halium-init-m64')))
print('Generated runtime-only M6.4 payload and unit overrides')

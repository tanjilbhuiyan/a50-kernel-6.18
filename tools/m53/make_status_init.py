#!/usr/bin/env python3
"""Generate test-4 Halium init/list from test 3 with a read-only observer.

Only the /init entry changes. A chrooted child enters the real root before
switch_root deletes the initramfs; a tmpfs handshake avoids an exec race.
The original Halium init and embedded list are preserved.
"""
from pathlib import Path
import difflib
import shlex
import subprocess

repo = Path(__file__).resolve().parents[2]
template = repo / 'src/m37/embed.list.in'
entries = template.read_text().splitlines()
init_entry, = [line for line in entries if line.startswith('file /init ')]
source = Path(init_entry.split()[2])
original = source.read_text()
observer = (repo / 'tools/m53/systemd_status.sh').read_text()
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1, 'unexpected Halium init handoff'
insertion = '''# M5.3 test 4: enter the real root before switch_root removes the initramfs.
busybox chroot "${rootmnt}" /bin/sh -c %s </dev/null >"${rootmnt}/dev/kmsg" 2>&1 &
a50_observer_wait=0
while [ ! -e "${rootmnt}/run/a50-status-armed" ] && [ "$a50_observer_wait" -lt 5 ]; do
    busybox sleep 1
    a50_observer_wait=$((a50_observer_wait + 1))
done
if [ ! -e "${rootmnt}/run/a50-status-armed" ]; then
    echo "A50STATUS: observer did not arm before handoff" >"${rootmnt}/dev/kmsg"
fi
''' % shlex.quote(observer)
updated = original.replace(handoff, insertion + handoff)
out = repo / 'src/m53/halium-init-status'
out.write_text(updated)
subprocess.run(['sh', '-n', str(out)], check=True)
new_entry = init_entry.replace(str(source), str(out), 1)
assert new_entry != init_entry
entries[entries.index(init_entry)] = new_entry
(repo / 'src/m53/embed-status.list.in').write_text('\n'.join(entries) + '\n')
(repo / 'reference/m53-halium-init/test4-init-observer.patch').write_text(
    ''.join(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                 fromfile='halium-init-original', tofile='halium-init-status')))
print('Generated /init observer; original init and list preserved')

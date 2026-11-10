#!/usr/bin/env python3
"""M5.4: temporary usb-moded fallback/rescue environment plus USB observations.

Keep the tested Halium handoff, M5.3 systemd snapshots and kernel config.
Only /init changes in the embedded ramdisk. Persistent rootfs files stay intact.
"""
from pathlib import Path
import difflib
import shlex
import subprocess

repo = Path(__file__).resolve().parents[2]
entries = (repo / 'src/m37/embed.list.in').read_text().splitlines()
init_entry, = [line for line in entries if line.startswith('file /init ')]
source = Path(init_entry.split()[2])
original = source.read_text()
observer = (repo / 'tools/m53/systemd_status.sh').read_text()
anchor = '    capture findmnt -no TARGET,OPTIONS /userdata\n'
extra = '''    capture ip -brief address
    capture systemctl show usb-moded.service usb-tethering.service usb-moded-udhcpd.service usb-moded-ssh.service -p Id -p ActiveState -p SubState
    capture /bin/sh -c 'for u in /sys/class/udc/*; do echo "UDC ${u##*/}"; cat "$u/state"; done; for g in /sys/kernel/config/usb_gadget/*; do echo "gadget ${g##*/}"; cat "$g/UDC"; find "$g/configs" -maxdepth 2 -type l -printf "%f -> %l\\n"; done'
'''
assert observer.count(anchor) == 1
observer = observer.replace(anchor, anchor + extra)
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1
insertion = '''# M5.4: packaged runtime environment, no persistent rootfs edits.
mkdir -p "${rootmnt}/run/usb-moded"
printf 'USB_MODED_ARGS="-f -r"\\n' > "${rootmnt}/run/usb-moded/99-a50-m54.conf"
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
out = repo / 'src/m54/halium-init-force'
out.write_text(updated)
subprocess.run(['sh', '-n', str(out)], check=True)
entries[entries.index(init_entry)] = init_entry.replace(str(source), str(out), 1)
(repo / 'src/m54/embed-force.list.in').write_text('\n'.join(entries) + '\n')
(repo / 'reference/m54-usb-ssh/force-init.patch').write_text(''.join(
    difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                         fromfile='halium-init-original', tofile='halium-init-force')))
print('Generated M5.4 temporary usb-moded environment and observer')

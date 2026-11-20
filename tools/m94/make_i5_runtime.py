#!/usr/bin/env python3
"""M9.4 I5: the I4 runtime (ADR-0005/0006) plus the ADR-0009 factory-address hook.

Regenerates src/m75/i4-runtime with tools/m75/make_i4_runtime.py, then inserts one block before the switch_root
handoff that stages tools/m94/efs_addresses.sh in /run/a50-m94 and adds a oneshot system unit ordered before
urfkill, bluetoothd and NetworkManager (pulled in by drop-ins). Writes src/m94/i5-runtime/{halium-init-runtime,
initramfs.list,payload/*} and reference/m94-bluetooth/i5-init-delta.patch (delta against the I4 init).
"""
from pathlib import Path
import difflib, hashlib, subprocess, sys

repo = Path(__file__).resolve().parents[2]
subprocess.run([sys.executable, '-I', str(repo / 'tools/m75/make_i4_runtime.py')], check=True, stdout=subprocess.DEVNULL)
base = repo / 'src/m75/i4-runtime'
out = repo / 'src/m94/i5-runtime'
(out / 'payload').mkdir(parents=True, exist_ok=True)
entries = (base / 'initramfs.list').read_text().splitlines()
init_entry, = [e for e in entries if e.startswith('file /init ')]
assert Path(init_entry.split()[2]) == base / 'halium-init-runtime'
original = (base / 'halium-init-runtime').read_text()
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1 and 'ADR-0006' in original and 'ADR-0009' not in original
insertion = r'''# M9.4 I5 (ADR-0009): factory Wi-Fi/Bluetooth addresses from a transient read-only EFS mount, before the radios start.
mkdir -p "${rootmnt}/run/a50-m94"
busybox cp /a50/m94/efs_addresses.sh "${rootmnt}/run/a50-m94/"
cat > "${rootmnt}/run/systemd/system/a50-efs-addresses.service" <<'A50M94_UNIT'
[Unit]
Description=A50 6.18: factory Wi-Fi/Bluetooth addresses from read-only EFS (ADR-0009)
DefaultDependencies=no
After=local-fs.target systemd-udev-settle.service
Before=urfkill.service bluetooth.service NetworkManager.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /run/a50-m94/efs_addresses.sh
A50M94_UNIT
for u in urfkill.service bluetooth.service NetworkManager.service; do
    mkdir -p "${rootmnt}/run/systemd/system/${u}.d"
    cat > "${rootmnt}/run/systemd/system/${u}.d/92-a50-efs-addresses.conf" <<'A50M94_UNIT'
[Unit]
Wants=a50-efs-addresses.service
After=a50-efs-addresses.service
A50M94_UNIT
done
'''
updated = original.replace(handoff, insertion + handoff)
(out / 'halium-init-runtime').write_text(updated)
subprocess.run(['sh', '-n', str(out / 'halium-init-runtime')], check=True)
entries[entries.index(init_entry)] = init_entry.replace(str(base / 'halium-init-runtime'), str(out / 'halium-init-runtime'), 1)
snap = out / 'payload' / 'efs_addresses.sh'
snap.write_bytes((repo / 'tools/m94/efs_addresses.sh').read_bytes())
subprocess.run(['sh', '-n', str(snap)], check=True)
entries.append('dir /a50/m94 0755 0 0')
entries.append(f'file /a50/m94/efs_addresses.sh {snap} 0644 0 0')
(out / 'initramfs.list').write_text('\n'.join(entries) + '\n')
(repo / 'reference/m94-bluetooth/i5-init-delta.patch').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), updated.splitlines(True), fromfile='halium-init-runtime (I4)', tofile='halium-init-runtime (I5)')))
for p in sorted(out.rglob('*')):
    if p.is_file():
        print(hashlib.sha256(p.read_bytes()).hexdigest()[:16], p.relative_to(repo))

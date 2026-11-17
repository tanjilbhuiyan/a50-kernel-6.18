#!/usr/bin/env python3
"""M7.5 I2: the I0 runtime initramfs plus the ADR-0005 audio deferral hook.

Reads the tested runtime list/init (src/reproduce-m6/payload), inserts one block before the switch_root handoff that
stages tools/m75/defer_audio.sh and the overlay in /run/a50-m75 and adds a oneshot system unit wanted by (and ordered
before) the phablet user manager, writes src/m75/i2-runtime/{halium-init-runtime,initramfs.list,payload/*} and the
init delta reference/m75-integration/i2-init-delta.patch. Every other list entry is unchanged.
"""
from pathlib import Path
import difflib, hashlib, subprocess

repo = Path(__file__).resolve().parents[2]
src = repo / 'src/reproduce-m6/payload'
out = repo / 'src/m75/i2-runtime'
(out / 'payload').mkdir(parents=True, exist_ok=True)
entries = (src / 'initramfs.list').read_text().splitlines()
init_entry, = [e for e in entries if e.startswith('file /init ')]
init_src = Path(init_entry.split()[2])
assert init_src == src / 'halium-init-runtime', init_src
original = init_src.read_text()
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1
insertion = r'''# M7.5 I2 (ADR-0005): runtime-only PulseAudio overlay without the unported Android audio HAL module.
mkdir -p "${rootmnt}/run/a50-m75" "${rootmnt}/run/systemd/system/user@32011.service.d"
busybox cp /a50/m75/defer_audio.sh /a50/m75/touch.pa "${rootmnt}/run/a50-m75/"
cat > "${rootmnt}/run/systemd/system/a50-defer-audio.service" <<'A50M75_UNIT'
[Unit]
Description=A50 6.18: start PulseAudio without the unported Android audio HAL (ADR-0005)
DefaultDependencies=no
After=local-fs.target
Before=user@32011.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /run/a50-m75/defer_audio.sh
A50M75_UNIT
cat > "${rootmnt}/run/systemd/system/user@32011.service.d/90-a50-audio.conf" <<'A50M75_UNIT'
[Unit]
Wants=a50-defer-audio.service
After=a50-defer-audio.service
A50M75_UNIT
'''
updated = original.replace(handoff, insertion + handoff)
(out / 'halium-init-runtime').write_text(updated)
subprocess.run(['sh', '-n', str(out / 'halium-init-runtime')], check=True)
entries[entries.index(init_entry)] = init_entry.replace(str(init_src), str(out / 'halium-init-runtime'), 1)
entries.append('dir /a50/m75 0755 0 0')
for name, path in (('defer_audio.sh', repo / 'tools/m75/defer_audio.sh'),
                   ('touch.pa', repo / 'tools/m75/audio/touch.pa.adr0005')):
    snap = out / 'payload' / name
    snap.write_bytes(path.read_bytes())
    entries.append(f'file /a50/m75/{name} {snap} 0644 0 0')
subprocess.run(['sh', '-n', str(out / 'payload/defer_audio.sh')], check=True)
(out / 'initramfs.list').write_text('\n'.join(entries) + '\n')
(repo / 'reference/m75-integration/i2-init-delta.patch').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), updated.splitlines(True), fromfile='halium-init-runtime (I0)', tofile='halium-init-runtime (I2)')))
for p in sorted((out).rglob('*')):
    if p.is_file():
        print(hashlib.sha256(p.read_bytes()).hexdigest()[:16], p.relative_to(repo))

#!/usr/bin/env python3
"""M7.5 I4: the I2 runtime (ADR-0005 audio deferral) plus the ADR-0006 gst-hybris deferral hook.

Regenerates src/m75/i2-runtime with tools/m75/make_i2_runtime.py, then inserts one more block before the switch_root
handoff that stages tools/m75/defer_gsthybris.sh and the placeholder in /run/a50-m75 and adds a oneshot system unit
wanted by (and ordered before) the phablet user manager. Writes src/m75/i4-runtime/{halium-init-runtime,
initramfs.list,payload/*} and reference/m75-integration/i4-init-delta.patch (delta against the I2 init).
"""
from pathlib import Path
import difflib, hashlib, subprocess, sys

repo = Path(__file__).resolve().parents[2]
subprocess.run([sys.executable, '-I', str(repo / 'tools/m75/make_i2_runtime.py')], check=True, stdout=subprocess.DEVNULL)
base = repo / 'src/m75/i2-runtime'
out = repo / 'src/m75/i4-runtime'
(out / 'payload').mkdir(parents=True, exist_ok=True)
entries = (base / 'initramfs.list').read_text().splitlines()
init_entry, = [e for e in entries if e.startswith('file /init ')]
assert Path(init_entry.split()[2]) == base / 'halium-init-runtime'
original = (base / 'halium-init-runtime').read_text()
handoff = 'exec busybox switch_root ${rootmnt} ${init} "$@" </dev/null >/dev/kmsg 2>&1'
assert original.count(handoff) == 1 and original.count('ADR-0005') == 2 and 'ADR-0006' not in original
insertion = r'''# M7.5 I4 (ADR-0006): runtime-only placeholder over libgsthybris.so; the Android OMX codec service is unavailable.
busybox cp /a50/m75/defer_gsthybris.sh /a50/m75/libgsthybris.placeholder "${rootmnt}/run/a50-m75/"
cat > "${rootmnt}/run/systemd/system/a50-defer-gsthybris.service" <<'A50M75_UNIT'
[Unit]
Description=A50 6.18: keep GStreamer's plugin scan out of the unavailable Android OMX service (ADR-0006)
DefaultDependencies=no
After=local-fs.target
Before=user@32011.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /run/a50-m75/defer_gsthybris.sh
A50M75_UNIT
cat > "${rootmnt}/run/systemd/system/user@32011.service.d/91-a50-gsthybris.conf" <<'A50M75_UNIT'
[Unit]
Wants=a50-defer-gsthybris.service
After=a50-defer-gsthybris.service
A50M75_UNIT
'''
updated = original.replace(handoff, insertion + handoff)
(out / 'halium-init-runtime').write_text(updated)
subprocess.run(['sh', '-n', str(out / 'halium-init-runtime')], check=True)
entries[entries.index(init_entry)] = init_entry.replace(str(base / 'halium-init-runtime'), str(out / 'halium-init-runtime'), 1)
# Keep I2's staged files (same bytes) and add the two ADR-0006 files.
for name, path in (('defer_gsthybris.sh', repo / 'tools/m75/defer_gsthybris.sh'),
                   ('libgsthybris.placeholder', repo / 'tools/m75/gst/libgsthybris.placeholder')):
    snap = out / 'payload' / name
    snap.write_bytes(path.read_bytes())
    entries.append(f'file /a50/m75/{name} {snap} 0644 0 0')
subprocess.run(['sh', '-n', str(out / 'payload/defer_gsthybris.sh')], check=True)
(out / 'initramfs.list').write_text('\n'.join(entries) + '\n')
(repo / 'reference/m75-integration/i4-init-delta.patch').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), updated.splitlines(True), fromfile='halium-init-runtime (I2)', tofile='halium-init-runtime (I4)')))
for p in sorted(out.rglob('*')):
    if p.is_file():
        print(hashlib.sha256(p.read_bytes()).hexdigest()[:16], p.relative_to(repo))

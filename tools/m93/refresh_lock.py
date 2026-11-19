#!/usr/bin/env python3
"""Refresh reproduce/m8/sources.lock.json for the a50-wlbt patch series (M9.3: SCSC core + Wi-Fi).

Rewrites the patch list, clean source commit, kernel tree, expected DTB and tracked-input hashes. Refuses if any
tracked input other than patches/ or reproduce/m8/config changed.
Usage: refresh_lock.py KERNEL_TREE DTB_SHA256 PATCH_COUNT PROFILE
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LOCKF = REPO / 'reproduce/m8/sources.lock.json'
tree, dtb, count, profile = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
lock = json.loads(LOCKF.read_text())
kernel = REPO / 'src/ack-6.18/common'
head = subprocess.check_output(['git', '-C', kernel, 'rev-parse', 'a50-wlbt'], text=True).strip()
assert subprocess.check_output(['git', '-C', kernel, 'rev-parse', 'a50-wlbt^{tree}'], text=True).strip() == tree
patches = sorted(str(p.relative_to(REPO)) for p in (REPO / 'patches').glob('[0-9][0-9][0-9][0-9]-*.patch'))
old_n = len(lock['patches'])
assert len(patches) == count and patches[:old_n] == lock['patches'], 'existing patch names must be unchanged'
sha = lambda p: hashlib.sha256((REPO / p).read_bytes()).hexdigest()
old = lock['tracked_inputs']
changed = sorted(k for k in old if k in map(str, old) and (REPO / k).exists() and sha(k) != old[k])
unexpected = [k for k in changed if not (k.startswith('patches/') or k == 'reproduce/m8/config')]
assert not unexpected, unexpected
missing = [k for k in old if not (REPO / k).exists()]
assert not missing, missing
new = {k: sha(k) for k in old}
for p in patches[old_n:]:
    new[p] = sha(p)
lock.update(profile=profile,
            clean_source_commit=head, kernel_tree=tree, patches=patches, tracked_inputs=new)
lock['expected']['dtb'] = dtb
LOCKF.write_text(json.dumps(lock, indent=2) + '\n')
print('changed:', len(changed), 'added:', len(patches) - old_n, 'tracked now:', len(new))

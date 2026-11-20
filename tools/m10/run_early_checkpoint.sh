#!/bin/bash
# Owner present: an early M10.2 checkpoint that should reset before userspace/USB.
# Use the established m32 runner for the complete flash/stock-restore cycle.
set -uo pipefail
tag=${1:?usage: run_early_checkpoint.sh TAG BASELINE_WIFI_IP}
ip=${2:?usage: run_early_checkpoint.sh TAG BASELINE_WIFI_IP}
[[ "$tag" =~ ^a1[a-z][0-9]*$ ]] || { echo 'Invalid checkpoint tag'; exit 1; }
prefix=reference/m10-audio/$tag
raw=src/m10/$tag-raw
[ ! -e "$raw/run.txt" ] || { echo 'Existing run; refusing overwrite'; exit 1; }
python3 - "$tag" <<'PY' || exit 1
from pathlib import Path
import hashlib,json,sys
d=json.loads(Path('reference/m10-audio',sys.argv[1]+'-inputs.json').read_text())
for name,v in d['files'].items():
    data=Path(name).read_bytes()
    assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'],name
print('All',len(d['files']),'checkpoint input hashes match')
PY
mkdir -p "$raw"
chmod 700 "$raw"
# Private redaction terms, never published. Stop before flashing if SSH fails.
if ! ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" \
    'nmcli -t -f NAME con show; grep -h "^ssid=" /etc/NetworkManager/system-connections/* 2>/dev/null | cut -d= -f2-' \
    > "$raw/.redact-source"; then
    echo 'Baseline SSH unavailable; nothing flashed'
    exit 1
fi
grep -v -E '^(lo|ril_[0-9]+|rndis0|)$' "$raw/.redact-source" | sort -u > "$raw/.redact"
chmod 600 "$raw/.redact" "$raw/.redact-source"
date --iso-8601=seconds > "$raw/host-start.txt"
DT_IMG=src/m10/dt-$tag.img tools/m32_run_test.sh "src/m10/boot-$tag.img" "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1
runner_rc=$?
cat "$raw/run.txt"
echo "runner=$runner_rc (no test-userspace USB/SSH expected)"
fsck_rc=0
if grep -q '^PRE-FLIGHT: ALL CHECKS PASSED$' "$raw/run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" cat /run/e2fsck.out > "$raw/baseline-fsck.txt"
    fsck_rc=$?
    echo "saved_fsck=$fsck_rc"
    cat "$raw/baseline-fsck.txt"
fi
date --iso-8601=seconds > "$raw/host-end.txt"
python3 - "$raw" "$prefix" <<'PY'
from pathlib import Path
import re,sys
raw,prefix=Path(sys.argv[1]),sys.argv[2]
terms=sorted((t for t in (raw/'.redact').read_text().splitlines() if len(t)>=3),key=len,reverse=True)
for p in raw.glob('*.txt'):
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28M[A-Z0-9]+','<redacted>',s)
    s=re.sub(r'(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}[_:]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])','<mac>',s)
    s=re.sub(r'\b192\.168\.\d{1,3}\.\d{1,3}\b','<lan-ip>',s)
    s=re.sub(r'(?i)\bfe80:[0-9a-f:]+','<ipv6>',s)
    for term in terms:
        s=s.replace(term,'<ssid>')
    Path(prefix+'-'+p.name).write_text('\n'.join(line.rstrip() for line in s.splitlines())+'\n')
PY
publish_rc=$?
[ "$runner_rc" -eq 0 ] || exit "$runner_rc"
[ "$fsck_rc" -eq 0 ] || exit "$fsck_rc"
exit "$publish_rc"

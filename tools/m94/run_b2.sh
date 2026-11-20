#!/bin/bash
# Owner present: M9.4 B2, Bluetooth S8 with the owner speaker (pair, A2DP tone, reconnect); established runner with stock restore.
set -u
ip=${1:?usage: run_b2.sh BASELINE_WIFI_IP [TAG]}
tag=${2:-b2}
prefix=reference/m94-bluetooth/$tag
raw=src/m94/$tag-raw
[ ! -e "$raw/run.txt" ] || { echo "M9.4 $tag run exists; refusing overwrite"; exit 1; }
mkdir -p "$raw"; chmod 700 "$raw"
python3 - "$tag" <<'PY' || exit 1
from pathlib import Path
import hashlib,json,sys
d=json.loads(Path('reference/m94-bluetooth/%s-inputs.json'%sys.argv[1]).read_text())
for name,v in d['files'].items():
    data=Path(name).read_bytes()
    assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M9.4 %s input hashes match'%sys.argv[1])
PY
# Private redaction list (saved profile names/SSIDs); never published.
ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" \
    'nmcli -t -f NAME con show; grep -h "^ssid=" /etc/NetworkManager/system-connections/* 2>/dev/null | cut -d= -f2-' \
    | grep -v -E '^(lo|ril_[0-9]+|rndis0|)$' | sort -u > "$raw/.redact" || exit 1
chmod 600 "$raw/.redact"; echo "redaction terms: $(wc -l < "$raw/.redact")"
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m94/dt-$tag.img tools/m32_run_test.sh src/m94/boot-$tag.img "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"; watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 390 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    timeout 330 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m94/collect_b2.sh > "$raw/live.txt" 2>&1
    echo "collection=$?"
    # raw HCI capture stays private (not *.txt, not published)
    timeout 30 ssh "${options[@]}" root@10.15.19.82 'cat /run/a50-b2/hci.btsnoop' > "$raw/hci.btsnoop" 2>/dev/null; echo "btsnoop_copy=$?"
    timeout 200 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 390 ] && break; sleep 2; done
        uname -r; cat /sys/devices/platform/148b0000.decon_f/g2b_stats
        systemctl show -p SystemState -p NFailedUnits -p NJobs
        findmnt -no TARGET,OPTIONS /userdata; dmesg' > "$raw/late.txt" 2>&1
    echo "late=$?"
    wait "$kernel_pid"; echo "kernel_stream=$?"
else
    echo "USB watch failed=$watch_rc; waiting for restore"
fi
# Never skip rollback because a collector failed.
wait "$runner_pid"; runner_rc=$?
cat "$raw/run.txt"
echo "runner=$runner_rc watch=$watch_rc"
if [ "$runner_rc" -eq 0 ] && grep -q 'PRE-FLIGHT: ALL CHECKS PASSED' "$raw/run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" cat /run/e2fsck.out > "$raw/baseline-fsck.txt"
    echo "saved_fsck=$?"; cat "$raw/baseline-fsck.txt"
    # The 6.18 boot's persistent journal (userspace side; kernel lines are not stored there).
    timeout 90 ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" 'journalctl -b -1 --no-pager -o short-monotonic' \
        > "$raw/journal-b-1.txt" 2>&1; echo "saved_journal=$?"
fi
if [ -s "$raw/ssh.profile-uuid" ]; then
    nmcli connection delete uuid "$(cat "$raw/ssh.profile-uuid")"
fi
python3 - "$raw" "$prefix" <<'PY'
from pathlib import Path
import re,sys
raw,prefix=Path(sys.argv[1]),sys.argv[2]
terms=[t for t in (raw/'.redact').read_text().splitlines() if len(t)>=3]
terms.sort(key=len, reverse=True)
for p in raw.glob('*.txt'):
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28[M][A-Z0-9]+','<redacted>',s)
    s=re.sub(r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{2}[_:]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])','<mac>',s)
    s=re.sub(r'(?i)jbl[ _-]?go[ _-]?3|\bjbl\b','<bt-device>',s)
    s=re.sub(r'(?i)\b([0-9a-f]{1,2}:){2}\*\*:\*\*:\*\*:[0-9a-f*:]+','<mac>',s)
    s=re.sub(r'\b192\.168\.\d{1,3}\.\d{1,3}\b','<lan-ip>',s)
    s=re.sub(r'(?i)\bfe80:[0-9a-f:]+','<ipv6>',s)
    for t in terms:
        s=s.replace(t,'<ssid>')
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
print('published', len(list(raw.glob('*.txt'))), 'redacted copies')
PY

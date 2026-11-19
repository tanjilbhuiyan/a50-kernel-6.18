#!/bin/bash
# Owner present: M9.3 W2, SCSC Wi-Fi with the saved NetworkManager profile (no credentials handled), SSH/ping/transfer
# over Wi-Fi from the host, NM disconnect/reconnect; established runner with stock restore.
set -u
ip=${1:?usage: run_w2.sh BASELINE_WIFI_IP [TAG]}
tag=${2:-w2}
prefix=reference/m93-wifi/$tag
raw=src/m93/$tag-raw
[ ! -e "$raw/run.txt" ] || { echo "M9.3 $tag run exists; refusing overwrite"; exit 1; }
mkdir -p "$raw"; chmod 700 "$raw"
python3 - "$tag" <<'PY' || exit 1
from pathlib import Path
import hashlib,json,sys
d=json.loads(Path('reference/m93-wifi/%s-inputs.json'%sys.argv[1]).read_text())
for name,v in d['files'].items():
    data=Path(name).read_bytes()
    assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M9.3 %s input hashes match'%sys.argv[1])
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
DT_IMG=src/m93/dt-$tag.img tools/m32_run_test.sh src/m93/boot-$tag.img "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"; watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 390 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    timeout 345 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m93/collect_w2.sh > "$raw/live.txt" 2>&1 &
    collect_pid=$!
    # Host side: wait for the phone's Wi-Fi address, then SSH / ping / transfer over Wi-Fi (before the 250 s reconnect).
    wip=
    for i in $(seq 1 200); do
        wip=$(timeout 8 ssh "${options[@]}" root@10.15.19.82 'cat /run/a50-w2/ip 2>/dev/null' 2>/dev/null)
        [ -n "$wip" ] && break; sleep 1
    done
    {
        echo "wifi_ip_present=$([ -n "$wip" ] && echo yes || echo no) at $(date +%T)"
        if [ -n "$wip" ]; then
            echo "== ssh over Wi-Fi"; timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=10 -o HostKeyAlias=192.168.0.171 \
                phablet@"$wip" 'uname -r; cut -d" " -f1 /proc/uptime; ip -4 -o route get 1.1.1.1 | grep -o "dev [a-z0-9]*"'; echo "ssh_rc=$?"
            echo "== ping"; ping -c 20 -i 0.5 -W 2 "$wip" | tail -n 3
            echo "== transfer 20 MB over ssh"; s=$(date +%s.%N)
            n=$(timeout 120 ssh -o BatchMode=yes -o HostKeyAlias=192.168.0.171 phablet@"$wip" 'head -c 20000000 /dev/zero' | wc -c)
            e=$(date +%s.%N); echo "bytes=$n seconds=$(echo "$e - $s" | bc)"
        fi
    } > "$raw/host-wifi.txt" 2>&1
    wait "$collect_pid"; echo "collection=$?"
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
    s=re.sub(r'(?i)\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b','<mac>',s)
    s=re.sub(r'(?i)\b([0-9a-f]{1,2}:){2}\*\*:\*\*:\*\*:[0-9a-f*:]+','<mac>',s)
    s=re.sub(r'\b192\.168\.\d{1,3}\.\d{1,3}\b','<lan-ip>',s)
    s=re.sub(r'(?i)\bfe80:[0-9a-f:]+','<ipv6>',s)
    for t in terms:
        s=s.replace(t,'<ssid>')
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
print('published', len(list(raw.glob('*.txt'))), 'redacted copies')
PY

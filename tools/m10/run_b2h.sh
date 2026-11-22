#!/bin/bash
# Owner present: M10.3 B2h, unchanged B2a image (TFA9872 probe-only) plus a supervised earpiece tone (stock media-handset
# mixer settings, six quiet 1 kHz tones at uptime 180-280 s); standard stock restore. No amplifier, EFS or calibration action.
set -u
ip=${1:?usage: run_b2h.sh BASELINE_WIFI_IP [TAG]}
tag=${2:-b2h}
prefix=reference/m10-audio/$tag
raw=src/m10/$tag-raw
[ ! -e "$raw/run.txt" ] || { echo "M10.3 $tag run exists; refusing overwrite"; exit 1; }
mkdir -p "$raw"; chmod 700 "$raw"
python3 - "$tag" <<'PY' || exit 1
from pathlib import Path
import hashlib,json,sys
d=json.loads(Path('reference/m10-audio/%s-inputs.json'%sys.argv[1]).read_text())
for name,v in d['files'].items():
    data=Path(name).read_bytes()
    assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M10.3 %s input hashes match'%sys.argv[1])
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
DT_IMG=src/m10/dt-$tag.img tools/m32_run_test.sh src/m10/boot-$tag.img "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"; watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 450 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    timeout 340 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m10/collect_b2h.sh > "$raw/live.txt" 2>&1 &
    collect_pid=$!
    wait "$collect_pid"; echo "collection=$?"
    timeout 300 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 390 ] && break; sleep 2; done
        for d in /sys/bus/i2c/devices/*-0034; do test -d "$d" && cat "$d/bringup_status"; done
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
if grep -q '^PRE-FLIGHT: ALL CHECKS PASSED$' "$raw/run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" cat /run/e2fsck.out > "$raw/baseline-fsck.txt"
    echo "saved_fsck=$?"; cat "$raw/baseline-fsck.txt"
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
exit "$runner_rc"

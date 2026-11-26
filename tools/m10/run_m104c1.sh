#!/bin/bash
# Owner present: M10.4 C1, read-only capture of why vendor.audio-hal crash-loops on 6.18. Unchanged B2b5 images
# (speaker audible in B2b5); collect_m104c1.sh reads ALSA nodes, HAL state, crash buffer, newest tombstone and audio
# logcat at ~150 s. No mixer/PulseAudio/HAL change. Calibration checked as before (value never printed); stock restore.
set -u
ip=${1:?usage: run_b2h2.sh BASELINE_WIFI_IP [TAG]}
tag=${2:-m104c1}
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
# Private stock calibration record (never printed or published); the stock phone must still read the same value.
exp=$(sed -n 's/^ *: values=//p' src/m10/b2-stock/post-b2a-calibration.txt | head -n 1)
case "$exp" in ''|*[!0-9]*) echo "private calibration record unreadable; stop"; exit 1;; esac
now=$(ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" "case \"\$(uname -r)\" in 4.14.194*) ;; *) exit 1;; esac
    amixer -c 0 cget 'name=TFA Calibration'" | sed -n 's/^ *: values=//p')
[ "$now" = "$exp" ] || { echo "stock calibration reading differs from the private record or unreadable; stop (nothing flashed)"; exit 1; }
echo "stock calibration matches the private record (value not printed)"
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
    # Copy, verify the hash, then start detached; a retry after a successful start sees the log and counts as started.
    sum=$(sha256sum tools/m10/collect_m104c1.sh | cut -d' ' -f1)
    started=1
    for i in 1 2 3 4 5 6 7 8 9 10; do
        timeout 15 ssh "${options[@]}" root@10.15.19.82 \
            'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; test ! -e /run/m104c1-live.txt || exit 0
             (umask 077; echo '"$exp"' > /run/m104c1-expect) || exit 3
             cat > /run/collect_m104c1.tmp && echo "'"$sum"'  /run/collect_m104c1.tmp" | sha256sum -c --quiet &&
                 mv /run/collect_m104c1.tmp /run/collect_m104c1.sh || exit 3
             setsid nohup sh /run/collect_m104c1.sh > /run/m104c1-live.txt 2>&1 < /dev/null & exit 0' \
            < tools/m10/collect_m104c1.sh && { started=0; break; }
        sleep 5
    done
    echo "collector_started=$started"
    end=$((SECONDS + 400))
    while [ "$started" = 0 ] && [ "$SECONDS" -lt "$end" ]; do
        timeout 10 ssh "${options[@]}" root@10.15.19.82 'cat /run/m104c1-live.txt' > "$raw/live.tmp" 2>/dev/null \
            && mv "$raw/live.tmp" "$raw/live.txt"
        grep -q '^M104C1_DONE$' "$raw/live.txt" 2>/dev/null && break
        sleep 5
    done
    rm -f "$raw/live.tmp"
    grep -q '^M104C1_DONE$' "$raw/live.txt" 2>/dev/null; echo "collection=$?"
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
    post=$(ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" "amixer -c 0 cget 'name=TFA Calibration'" | sed -n 's/^ *: values=//p')
    [ "$post" = "$exp" ] && echo "post-restore stock calibration matches the private record" \
        || echo "POST-RESTORE STOCK CALIBRATION DIFFERS or unreadable"
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
    # Per-unit amplifier calibration: no number on any calibration/impedance line.
    s='\n'.join(re.sub(r'\b\d{3,5}\b','<private>',x) if re.search(r'(?i)calib|re25|mohm|imped|rdc',x) else x
                 for x in s.splitlines())
    s=re.sub(r'(?i)\bfe80:[0-9a-f:]+','<ipv6>',s)
    for t in terms:
        s=s.replace(t,'<ssid>')
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
print('published', len(list(raw.glob('*.txt'))), 'redacted copies')
PY
exit "$runner_rc"

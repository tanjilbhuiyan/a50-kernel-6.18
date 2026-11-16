#!/bin/bash
# Owner present; validated candidate -> bounded clients -> stock restore/fsck.
# All phone captures stay ignored until redacted after the cycle.
set -u
ip=${1:-192.168.0.171}
prefix=reference/m73-gpu/g2b
raw=src/m73/g2b-raw
[ ! -e "$prefix-run.txt" ] || { echo 'G2b evidence exists; refusing overwrite'; exit 1; }
mkdir -p "$raw"
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
d=json.loads(Path('reference/m73-gpu/g2b-inputs.json').read_text())
for name,metadata in d['files'].items():
    p=Path(name)
    assert p.stat().st_size==metadata['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==metadata['sha256'], name
print('All recorded G2b input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m73/dt-g1.img tools/m32_run_test.sh src/m73/boot-g2b.img "$raw/dump.txt" "$ip" 540 > "$prefix-run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"
watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 390 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    timeout 370 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do
            [ "${up%%.*}" -lt 390 ] || break
            printf "\nG2B_STATS uptime=%s\n" "$up"
            cat /sys/devices/platform/148b0000.decon_f/g2b_stats
            grep -E "mali|decon" /proc/interrupts
            sleep 2
        done' > "$raw/stats.txt" 2>&1 &
    monitor_pid=$!
    timeout 130 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m73/collect_g2b.sh > "$raw/live.txt" 2>&1
    echo "collection=$?"
    timeout 310 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 220 ] && break; sleep 2; done
        uname -r; cat /sys/devices/platform/148b0000.decon_f/g2b_stats
        systemctl show -p SystemState -p NFailedUnits -p NJobs
        findmnt -no TARGET,OPTIONS /userdata; dmesg' > "$raw/late.txt" 2>&1
    echo "late=$?"
    wait "$monitor_pid"; echo "monitor=$?"
    wait "$kernel_pid"; echo "kernel_stream=$?"
else
    echo "USB watch failed: $watch_rc"
fi
# A failed/hung client never bypasses the established restore cycle.
wait "$runner_pid"
runner_rc=$?
cat "$prefix-run.txt"
echo "runner=$runner_rc watch=$watch_rc"
if [ "$runner_rc" -eq 0 ] && grep -q 'PRE-FLIGHT: ALL CHECKS PASSED' "$prefix-run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" cat /run/e2fsck.out > "$prefix-baseline-fsck.txt"
    echo "saved_fsck=$?"
    cat "$prefix-baseline-fsck.txt"
fi
if [ -s "$raw/ssh.profile-uuid" ]; then
    nmcli connection delete uuid "$(cat "$raw/ssh.profile-uuid")"
fi
python3 - "$raw" "$prefix" <<'PY'
from pathlib import Path
import re,sys
raw,prefix=Path(sys.argv[1]),sys.argv[2]
for p in raw.glob('*.txt'):
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28M[A-Z0-9]+','<redacted>',s)
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
PY
exit "$runner_rc"

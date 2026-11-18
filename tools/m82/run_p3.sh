#!/bin/bash
# Owner present: M8.2 P3: clean event-format fallback + READY_STATUS probe; passive capture while the owner touches, established stock restore.
set -u
ip=${1:?usage: run_p3.sh BASELINE_WIFI_IP}
prefix=reference/m82-touch/p3
raw=src/m82/p3-raw
[ ! -e "$raw/run.txt" ] || { echo 'M8.2 P3 run exists; refusing overwrite'; exit 1; }
mkdir -p "$raw"
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
for manifest in ('p3-inputs.json',):
    d=json.loads(Path('reference/m82-touch',manifest).read_text())
    for name,v in d['files'].items():
        data=Path(name).read_bytes()
        assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M8.2 P3 input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m82/dt-p3.img tools/m32_run_test.sh src/m82/boot-p3.img "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"; watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 390 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    timeout 370 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do
            [ "${up%%.*}" -lt 390 ] || break
            printf "\nM82_P3_STATS uptime=%s\n" "$up"
            cat /sys/devices/platform/148b0000.decon_f/g2b_stats
            grep -E "mali|decon" /proc/interrupts
            sleep 2
        done' > "$raw/stats.txt" 2>&1 &
    monitor_pid=$!
    ssh "${options[@]}" root@10.15.19.82 'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        mkdir -p /run/a50-p1 && mount -t tmpfs -o mode=700,size=16m tmpfs /run/a50-p1 && cat > /run/a50-p1/evcap && chmod 700 /run/a50-p1/evcap' < src/m82/evcap
    echo "helper_setup=$?"
    ssh "${options[@]}" root@10.15.19.82 'cat > /run/a50-p1/eintread && chmod 700 /run/a50-p1/eintread' < src/m82/eintread
    echo "eintread_setup=$?"
    timeout 300 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m82/collect_p3.sh > "$raw/live.txt" 2>&1
    echo "collection=$?"
    timeout 280 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 390 ] && break; sleep 2; done
        uname -r; cat /sys/devices/platform/148b0000.decon_f/g2b_stats
        systemctl show -p SystemState -p NFailedUnits -p NJobs
        systemctl show lightdm.service -p ActiveState -p SubState -p Result -p ExecMainStatus
        tail -n 100 /var/log/lightdm/unity-system-compositor.log
        findmnt -no TARGET,OPTIONS /userdata; dmesg' > "$raw/late.txt" 2>&1
    echo "late=$?"
    wait "$monitor_pid"; echo "monitor=$?"
    wait "$kernel_pid"; echo "kernel_stream=$?"
else
    echo "USB watch failed=$watch_rc; waiting for restore"
fi
# Never skip rollback because a graphics client or collector failed.
wait "$runner_pid"; runner_rc=$?
cat "$raw/run.txt"
echo "runner=$runner_rc watch=$watch_rc"
if [ "$runner_rc" -eq 0 ] && grep -q 'PRE-FLIGHT: ALL CHECKS PASSED' "$raw/run.txt"; then
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
for p in raw.glob('*.txt'):
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28[M][A-Z0-9]+','<redacted>',s)
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
PY
exit "$runner_rc"

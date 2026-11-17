#!/bin/bash
# Owner present: existing G2e image, bounded observations, established stock restore.
set -u
ip=${1:?usage: run_g2e.sh BASELINE_WIFI_IP}
prefix=reference/m73-gpu/g2e
raw=src/m73/g2e-raw
[ ! -e "$raw/run.txt" ] || { echo 'G2e run exists; refusing overwrite'; exit 1; }
mkdir -p "$raw"
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
for manifest in ('g2e-inputs.json', 'g2e-session-inputs.json'):
    d=json.loads(Path('reference/m73-gpu',manifest).read_text())
    for name,v in d['files'].items():
        data=Path(name).read_bytes()
        assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All G2e candidate and session input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m73/dt-g1.img tools/m32_run_test.sh src/m73/boot-g2e.img "$raw/dump.txt" "$ip" 540 > "$raw/run.txt" 2>&1 &
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
            printf "\nG2E_STATS uptime=%s\n" "$up"
            cat /sys/devices/platform/148b0000.decon_f/g2b_stats
            grep -E "mali|decon" /proc/interrupts
            sleep 2
        done' > "$raw/stats.txt" 2>&1 &
    monitor_pid=$!
    setup_rc=0
    ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        mkdir -p /run/a50-g2e && mount -t tmpfs -o mode=700,size=12m tmpfs /run/a50-g2e' || setup_rc=$?
    if [ "$setup_rc" -eq 0 ]; then
        for bits in 64 32; do
            ssh "${options[@]}" root@10.15.19.82 "cat > /run/a50-g2e/ion-flags$bits && chmod 700 /run/a50-g2e/ion-flags$bits" \
                < "src/m73/g2e-session/ion-flags$bits" || setup_rc=$?
        done
        ssh "${options[@]}" root@10.15.19.82 'cat > /run/a50-g2e/winconfig-test && chmod 700 /run/a50-g2e/winconfig-test' \
            < src/m73/winconfig-test-g2d || setup_rc=$?
    fi
    if [ "$setup_rc" -eq 0 ]; then
        timeout 280 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m73/collect_g2e.sh > "$raw/live.txt" 2>&1
        echo "collection=$?"
    else
        echo "G2e temporary helper setup failed=$setup_rc; waiting for restore"
    fi
    timeout 280 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 260 ] && break; sleep 2; done
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

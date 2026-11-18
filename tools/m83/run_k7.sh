#!/bin/bash
# Owner present: M8.3 K7: unchanged P3 touch-only control, same K6 cable/port plus private USB trace instance; detached USB observer; established stock restore.
set -u
ip=${1:?usage: run_k7.sh BASELINE_WIFI_IP}
prefix=reference/m83-keys/k7
raw=src/m83/k7-raw
[ ! -e "$raw/run.txt" ] || { echo 'M8.3 K7 run exists; refusing overwrite'; exit 1; }
mkdir -p "$raw"
start_time=$(date --iso-8601=seconds)
printf '%s\n' "$start_time" > "$raw/host-start.txt"
journalctl -k -n 1 --no-pager > "$raw/host-log-check.txt" 2>&1 || { echo 'Host kernel journal unavailable; stopping before flash'; exit 1; }
lsusb -t > "$raw/host-usb-before.txt"
cat /proc/sys/kernel/random/boot_id > "$raw/host-boot-id.txt"
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
for manifest in ('k7-inputs.json',):
    d=json.loads(Path('reference/m83-keys',manifest).read_text())
    for name,v in d['files'].items():
        data=Path(name).read_bytes()
        assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M8.3 K7 input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
python3 -I tools/m83/watch_host_usb.py "$raw/host-power.jsonl" "$raw/host-watch.stop" > "$raw/host-power-errors.txt" 2>&1 &
host_power_pid=$!
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
            printf "\nM83_K7_STATS uptime=%s\n" "$up"
            cat /sys/devices/platform/148b0000.decon_f/g2b_stats
            grep -E "mali|decon" /proc/interrupts
            sleep 2
        done' > "$raw/stats.txt" 2>&1 &
    monitor_pid=$!
    ssh "${options[@]}" root@10.15.19.82 'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        mkdir -p /run/a50-k7 && mount -t tmpfs -o mode=700,size=16m tmpfs /run/a50-k7 && cat > /run/a50-k7/phone_side.sh && chmod 700 /run/a50-k7/phone_side.sh' < tools/m83/k7_phone_side.sh
    setup_rc=$?
    echo "phone_side_upload=$setup_rc"
    if [ "$setup_rc" -eq 0 ]; then
        ssh "${options[@]}" root@10.15.19.82 'setsid nohup sh /run/a50-k7/phone_side.sh > /run/a50-k7/phone_side.log 2>&1 < /dev/null &'
        echo "phone_side_launch=$?"
    fi
    timeout 300 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m83/collect_k7.sh > "$raw/live.txt" 2>&1
    echo "collection=$?"
    timeout 280 ssh "${options[@]}" root@10.15.19.82 '
        case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 398 ] && break; sleep 2; done
        for n in udc udc-summary window logind usbmoded dmesg-usb trace-setup trace-stats usb-trace phone_side.log; do
            echo "A50K7_FILE $n"; cat "/run/a50-k7/$n" "/run/a50-k7/$n.txt" 2>/dev/null
        done
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
touch "$raw/host-watch.stop"
wait "$host_power_pid"; echo "host_power=$?"
end_time=$(date --iso-8601=seconds)
printf '%s\n' "$end_time" > "$raw/host-end.txt"
journalctl -k --since "$start_time" --until "$end_time" --no-pager -o short-iso > "$raw/host-kernel.txt" 2>&1
host_rc=$?
echo "host_journal=$host_rc"
grep -i -E 'usb|rndis|cdc_ether|descriptor|xhci' "$raw/host-kernel.txt" > "$raw/host-usb.txt"
lsusb -t > "$raw/host-usb-after.txt"
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
for p in list(raw.glob('*.txt')) + list(raw.glob('*.jsonl')):
    if p.name == 'host-kernel.txt': continue  # unrelated host logs remain private
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28[M][A-Z0-9]+','<redacted>',s)
    s=re.sub(r'(SerialNumber:\s*)\S+',r'\1<redacted>',s)
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
PY
exit "$runner_rc"

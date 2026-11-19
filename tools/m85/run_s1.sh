#!/bin/bash
# Owner present: M8.5 S1: M8.5 interactive soak, detached observers and calibrated USB trace; detached USB observer; established stock restore.
set -u
ip=${1:?usage: run_s1.sh BASELINE_WIFI_IP}
prefix=reference/m85-integration/s1
raw=src/m85/s1-raw
[ ! -e "$raw/run.txt" ] || { echo 'M8.5 S1 run exists; refusing overwrite'; exit 1; }
mkdir -p "$raw"
start_time=$(date --iso-8601=seconds)
printf '%s\n' "$start_time" > "$raw/host-start.txt"
journalctl -k -n 1 --no-pager > "$raw/host-log-check.txt" 2>&1 || { echo 'Host kernel journal unavailable; stopping before flash'; exit 1; }
lsusb -t > "$raw/host-usb-before.txt"
cat /proc/sys/kernel/random/boot_id > "$raw/host-boot-id.txt"
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
for manifest in ('s1-inputs.json',):
    d=json.loads(Path('reference/m85-integration',manifest).read_text())
    for name,v in d['files'].items():
        data=Path(name).read_bytes()
        assert len(data)==v['size'] and hashlib.sha256(data).hexdigest()==v['sha256'], name
print('All M8.5 S1 input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$raw/ssh.txt" 260 > "$raw/watch.txt" 2>&1 &
watch_pid=$!
python3 -I tools/m83/watch_host_usb.py "$raw/host-power.jsonl" "$raw/host-watch.stop" --seconds 1400 > "$raw/host-power-errors.txt" 2>&1 &
host_power_pid=$!
timeout 1400 journalctl -k -f -n 0 --no-pager -o short-iso > "$raw/host-kernel-follow.txt" 2>&1 &
host_journal_pid=$!
DT_IMG=src/m84/dt-h1.img tools/m32_run_test.sh src/m85/boot-s1.img "$raw/dump.txt" "$ip" 1080 > "$raw/run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"; watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    timeout 930 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; dmesg --color=never --follow' > "$raw/kernel-follow.txt" 2>&1 &
    kernel_pid=$!
    setup_rc=0
    ssh "${options[@]}" root@10.15.19.82 'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
        mkdir -p /run/a50-m85-s1 && mount -t tmpfs -o mode=700,size=32m tmpfs /run/a50-m85-s1' || setup_rc=$?
    for f in src/m75/i0-session/kbase-memory64 src/m75/i0-session/kbase-memory32 src/m63/ion-smoke64 src/m63/ion-smoke32 src/m82/evcap; do
        [ "$setup_rc" -eq 0 ] || break
        ssh "${options[@]}" root@10.15.19.82 "cat > /run/a50-m85-s1/${f##*/} && chmod 700 /run/a50-m85-s1/${f##*/}" < "$f" || setup_rc=$?
    done
    for script in phone_soak phone_input phone_usb; do
        [ "$setup_rc" -eq 0 ] || break
        ssh "${options[@]}" root@10.15.19.82 "cat > /run/a50-m85-s1/$script.sh" < "tools/m85/$script.sh" || setup_rc=$?
    done
    echo "helper_setup=$setup_rc"
    if [ "$setup_rc" -eq 0 ]; then
        ssh "${options[@]}" root@10.15.19.82 '
            D=/run/a50-m85-s1
            setsid nohup sh "$D/phone_soak.sh" > "$D/soak.txt" 2>&1 < /dev/null &
            setsid nohup sh "$D/phone_input.sh" > "$D/input-observer.txt" 2>&1 < /dev/null &
            setsid nohup sh "$D/phone_usb.sh" > "$D/usb-observer.txt" 2>&1 < /dev/null &
            echo "DETACHED_OBSERVERS_STARTED uptime=$(cut -d" " -f1 /proc/uptime)"
        ' > "$raw/start.txt" 2>&1
        echo "observer_start=$?"
    fi
    (
        for round in $(seq 1 50); do
            [ ! -e "$raw/progress.stop" ] || break
            printf '\nHOST_PROGRESS %s\n' "$(date --iso-8601=seconds)"
            timeout 12 ssh "${options[@]}" root@10.15.19.82 '
                case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
                echo M85_LIVE_UPTIME; cat /proc/uptime
                runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus \
                    systemctl --user show lomiri-full-greeter.service lomiri-full-shell.service lomiri-shell.service \
                    -p Id -p ActiveState -p SubState -p MainPID -p NRestarts
                tail -n 16 /run/a50-m85-s1/soak.txt
                tail -n 3 /run/a50-m85-s1/usb-observer.txt
                head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats
            ' 2>&1
            sleep 20
        done
    ) > "$raw/live-progress.txt" 2>&1 &
    progress_pid=$!
    phone_up=$(ssh "${options[@]}" root@10.15.19.82 'cut -d" " -f1 /proc/uptime')
    echo "late_wait_from_uptime=$phone_up"
    python3 - "$phone_up" <<'WAIT'
import sys,time
try: delay=max(0,888-float(sys.argv[1]))
except ValueError: delay=840
while delay>0:
    n=min(30,delay);time.sleep(n);delay-=n
WAIT
    late_rc=1
    for attempt in 1 2 3; do
        timeout 12 ssh "${options[@]}" root@10.15.19.82 '
            case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
            D=/run/a50-m85-s1
            for n in soak touch keys udc udc-summary window logind usbmoded dmesg-usb trace-setup trace-final trace-stats usb-trace input-observer usb-observer; do
                echo "A50M85_FILE $n"; cat "$D/$n.txt" 2>/dev/null
            done
            echo A50M85_FINAL_UPTIME; cat /proc/uptime
            cat /sys/devices/platform/148b0000.decon_f/g2b_stats
            findmnt -no TARGET,OPTIONS /userdata
            dmesg' > "$raw/late.txt" 2>&1
        late_rc=$?
        [ "$late_rc" -ne 0 ] || break
        sleep 1
    done
    echo "late=$late_rc"
    touch "$raw/progress.stop"
    wait "$progress_pid"; echo "progress_monitor=$?"
    wait "$kernel_pid"; echo "kernel_stream=$?"
else
    echo "USB watch failed=$watch_rc; waiting for restore"
fi
# Never skip rollback because a graphics client or collector failed.
wait "$runner_pid"; runner_rc=$?
touch "$raw/host-watch.stop"
kill "$host_journal_pid" 2>/dev/null || true
wait "$host_journal_pid"; echo "host_journal_follow=$? (expected termination after restore)"
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
full=raw/'kernel-follow.txt'
if full.exists():
    lines=full.read_text(errors='replace').splitlines()
    selected=[l for l in lines if re.search(r'A50M85|A50-GUARD|A50_UFS|gpio-keys|MELFAS|melfas|usb|dwc3|gadget|UDC|Unable to handle|SError|Internal error|BUG:|Kernel panic|WARNING: CPU|sysmmu|mali|fence.*(wait|timeout)|journal.*abort|remount.*read-only',l,re.I)]
    text='\n'.join(selected)+'\n'
    text=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',text)
    text=re.sub(r'R28[M][A-Z0-9]+','<redacted>',text)
    Path(prefix+'-kernel-events.txt').write_text(text)
for p in list(raw.glob('*.txt')) + list(raw.glob('*.jsonl')):
    if p.name in ('host-kernel.txt', 'host-kernel-follow.txt', 'kernel-follow.txt'): continue  # unrelated host logs remain private
    s=p.read_text(errors='replace')
    s=re.sub(r'(androidboot\.(?:serialno|ap_serial|em\.did)=)[^\s\\]+',r'\1<redacted>',s)
    s=re.sub(r'R28[M][A-Z0-9]+','<redacted>',s)
    s=re.sub(r'(SerialNumber:\s*)\S+',r'\1<redacted>',s)
    Path(prefix+'-'+p.name).write_text('\n'.join(x.rstrip() for x in s.splitlines())+'\n')
PY
exit "$runner_rc"

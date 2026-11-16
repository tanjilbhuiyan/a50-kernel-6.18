#!/bin/bash
# Owner present, baseline verified. Always wait for the runner's restore.
# Usage: bash tools/m73/run_g1.sh [BASELINE_PHONE_IP]
set -u
ip=${1:-192.168.0.171}
prefix=reference/m73-gpu/g1b
[ ! -e "$prefix-run.txt" ] || { echo 'G1 evidence already exists; refusing overwrite'; exit 1; }
python3 - <<'PY' || exit 1
from pathlib import Path
import hashlib,json
d=json.loads(Path('reference/m73-gpu/g1b-inputs.json').read_text())
for name,metadata in d['files'].items():
    p=Path(name)
    assert p.stat().st_size==metadata['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==metadata['sha256'], name
print('All recorded G1 input hashes match')
PY
options=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5
    -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$prefix-ssh.txt" 260 > "$prefix-watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m73/dt-g1.img tools/m32_run_test.sh src/m73/boot-g1b.img "$prefix-dump.txt" "$ip" 540 > "$prefix-run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"
watch_rc=$?
if [ "$watch_rc" -eq 0 ]; then
    tar -cf - -C src/m73/probe gpuprops64 gpuprops32 | timeout 35 ssh "${options[@]}" root@10.15.19.82 \
        'case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac; mkdir -p /run/a50-g1-exec; mount -t tmpfs -o exec,nodev,nosuid,size=16m,mode=0700 tmpfs /run/a50-g1-exec && tar -xf - -C /run/a50-g1-exec'
    transfer_rc=$?
    echo "transfer=$transfer_rc"
    timeout 120 ssh "${options[@]}" root@10.15.19.82 sh -s < tools/m73/collect_g1.sh > "$prefix-live.txt" 2>&1
    echo "collection=$?"
    timeout 330 ssh "${options[@]}" root@10.15.19.82 \
        'while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 220 ] && break; sleep 2; done; uname -r; systemctl show -p SystemState -p NFailedUnits -p NJobs; findmnt -no TARGET,OPTIONS /userdata; dmesg' > "$prefix-late.txt" 2>&1
    echo "late=$?"
else
    echo "USB watch failed: $watch_rc"
fi
wait "$runner_pid"
runner_rc=$?
cat "$prefix-run.txt"
echo "runner=$runner_rc watch=$watch_rc"
if [ "$runner_rc" -eq 0 ] && grep -q 'PRE-FLIGHT: ALL CHECKS PASSED' "$prefix-run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" cat /run/e2fsck.out > "$prefix-baseline-fsck.txt"
    echo "saved_fsck=$?"
    cat "$prefix-baseline-fsck.txt"
fi
if [ -s "$prefix-ssh.profile-uuid" ]; then
    nmcli connection delete uuid "$(cat "$prefix-ssh.profile-uuid")"
fi
exit "$runner_rc"

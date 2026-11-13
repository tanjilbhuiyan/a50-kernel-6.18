#!/bin/bash
# From repo root: bash PATH/run_runtime_test.sh BOOT EVIDENCE_PREFIX [PHONE_IP]
# Freeze this script beside its collector/probes before running a test.
set -u
image=${1:?BOOT image required}
prefix=${2:?evidence prefix required}
phone_ip=${3:-192.168.0.171}
scripts=$(cd "$(dirname "$0")" && pwd)
[ -f tools/m32_run_test.sh ] && [ ! -e "$prefix-run.txt" ] || exit 1
ssh_options=(-o BatchMode=yes -o ConnectTimeout=6 -o HostKeyAlias=192.168.0.171)
python3 -I tools/m54/watch_ssh.py "$prefix-ssh.txt" 260 > "$prefix-watch.txt" 2>&1 &
watch_pid=$!
DT_IMG=src/m63/dt-sysmmu.img tools/m32_run_test.sh "$image" "$prefix-dump.txt" "$phone_ip" 540 > "$prefix-run.txt" 2>&1 &
runner_pid=$!
wait "$watch_pid"
watch_rc=$?
if [ "$watch_rc" -eq 0 ] && grep -q 'A50M54_UNAME=6.18' "$prefix-ssh.txt"; then
    tar -cf - -C "$PWD/src/m64" block-policy-matrix -C "$PWD/src/m63" ion-smoke64 ion-smoke32 | \
        ssh "${ssh_options[@]}" root@10.15.19.82 'case "$(uname -r)" in 6.18*) tar -xf - -C /run/a50-m64;; *) exit 1;; esac'
    ssh "${ssh_options[@]}" root@10.15.19.82 'sh -s' < "$scripts/check_block_policy.sh" > "$prefix-block-policy.txt" 2>&1
    echo "block_policy=$?"
    ssh "${ssh_options[@]}" root@10.15.19.82 'sh -s' < "$scripts/check_container_ion.sh" > "$prefix-container-ion.txt" 2>&1
    echo "container_ion=$?"
    ssh "${ssh_options[@]}" root@10.15.19.82 'sh -s' < "$scripts/collect_runtime.sh" > "$prefix-live-early.txt" 2>&1
    echo "early_collection=$?"
    ssh "${ssh_options[@]}" root@10.15.19.82 'cat > /run/a50-m64/collect-live.sh' < "$scripts/collect_runtime.sh"
    ssh "${ssh_options[@]}" root@10.15.19.82 'while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 220 ] && break; sleep 2; done; /bin/sh /run/a50-m64/collect-live.sh' > "$prefix-live-late.txt" 2>&1
    echo "late_collection=$?"
else
    echo "USB watch failed: $watch_rc"
fi
# Always wait for the runner's stock restore, including failed probes.
wait "$runner_pid"
runner_rc=$?
cat "$prefix-run.txt"
echo "runner=$runner_rc watch=$watch_rc"
if [ "$runner_rc" -eq 0 ] && grep -q 'PRE-FLIGHT: ALL CHECKS PASSED' "$prefix-run.txt"; then
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$phone_ip" 'cat /run/e2fsck.out' > "$prefix-baseline-fsck.txt"
    echo "saved_fsck=$?"
    cat "$prefix-baseline-fsck.txt"
fi
if [ -s "$prefix-ssh.txt.profile-uuid" ]; then
    nmcli connection delete uuid "$(cat "$prefix-ssh.txt.profile-uuid")"
fi
exit "$runner_rc"

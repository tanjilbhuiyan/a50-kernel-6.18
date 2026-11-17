#!/bin/bash
# Owner present; bounded control on stock. Helpers live only in /run tmpfs.
set -u
ip=${1:?usage: run_memory_baseline.sh BASELINE_IP}
raw=src/m73/g2h-raw
mkdir -p "$raw"
ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" '
    case "$(uname -r)" in 4.14*) ;; *) exit 1;; esac
    mkdir -p /run/a50-g2h-control && mount -t tmpfs -o mode=700,size=12m tmpfs /run/a50-g2h-control' || exit 1
for bits in 64 32; do
    ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" "cat > /run/a50-g2h-control/kbase-memory$bits && chmod 700 /run/a50-g2h-control/kbase-memory$bits" \
        < "src/m73/g2h-session/kbase-memory$bits" || exit 1
done
ssh -o BatchMode=yes -o ConnectTimeout=6 root@"$ip" '
    case "$(uname -r)" in 4.14*) ;; *) exit 1;; esac
    uname -r; cat /proc/uptime; sha256sum /run/a50-g2h-control/*
    timeout -k 5 60 /run/a50-g2h-control/kbase-memory64
    echo G2H_BASELINE_64_RC=$?
    timeout -k 5 60 /run/a50-g2h-control/kbase-memory32
    echo G2H_BASELINE_32_RC=$?
    findmnt -no TARGET,OPTIONS /userdata
    dmesg | tail -n 100
    umount /run/a50-g2h-control
' > "$raw/baseline-memory.txt" 2>&1

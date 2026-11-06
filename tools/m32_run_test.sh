#!/bin/bash
# One button-free 6.18 test cycle (owner present, cable plugged in, phone in UT on the baseline):
#  pre-flight -> software reboot to Download -> flash our DTB+DTBO + TEST boot.img WITH reboot -> wait until 6.18 sends
#  the phone back to Download mode -> roll back stock DTB+DTBO + baseline BOOT WITH reboot -> wait for UT -> read the dump
#  -> pre-flight. If 6.18 does not come back to Download mode within WAIT_S, it stops and prints the manual recovery.
#   tools/m32_run_test.sh TEST_BOOT_IMG OUT_DUMP_FILE [PHONE_IP] [WAIT_S]
set -euo pipefail
IMG=${1:?usage: m32_run_test.sh TEST_BOOT_IMG OUT_DUMP_FILE [PHONE_IP] [WAIT_S]}; OUTF=${2:?}; IP=${3:-192.168.0.171}; WAIT=${4:-120}
R=$(cd "$(dirname "$0")/.." && pwd); cd "$R"
DT=${DT_IMG:-src/m31/dt.img}; DTBO=reference/dt-6.18/images/dtbo.img
SDT=reference/stock-images/dt.img; SDTBO=reference/stock-images/dtbo.img; BASE=baseline/ut-26.04-2026-10-19-aa17rf2/boot.img
dl() { lsusb | grep -q "04e8:685d"; }
waitdl() { local t=$1 s=$(date +%s); while [ $(( $(date +%s)-s )) -lt "$t" ]; do dl && return 0; sleep 2; done; return 1; }
echo "[$(date +%T)] test image $IMG $(sha256sum "$IMG" | cut -c1-16)"
tools/m24_preflight.sh "$IP" 2>&1 | tail -1 | grep -q "ALL CHECKS PASSED" || { echo "pre-flight FAILED, stop"; exit 1; }
timeout 20 ssh -o BatchMode=yes root@"$IP" "sync; setsid nohup sh -c 'sleep 2; systemctl reboot --reboot-argument=download' >/dev/null 2>&1 < /dev/null &" || true
waitdl 90 || { echo "phone did not reach Download mode by software, stop"; exit 1; }
sleep 3; echo "[$(date +%T)] Download mode; flashing our DT + test BOOT with reboot"
if ! heimdall flash --DTB "$DT" --DTBO "$DTBO" --BOOT "$IMG" 2>&1 | grep -E "upload successful|ERROR|failed"; then
  echo "[$(date +%T)] TEST FLASH FAILED (partitions may be half-written). The phone may show Samsung's 'An error has occurred"
  echo "  while updating the device software' screen: that is a Download-type mode. Re-enter Download mode if needed and run:"
  echo "  heimdall flash --DTB $SDT --DTBO $SDTBO --BOOT $BASE --no-reboot   (then restart, run the pre-flight)"; exit 3; fi
sleep 8
if waitdl "$WAIT"; then echo "[$(date +%T)] 6.18 sent the phone back to Download mode by itself"; else
  echo "[$(date +%T)] NO Download mode within ${WAIT}s: 6.18 did not dump. Manual recovery: Vol Down+Power until black, then"
  echo "  Vol Up+Vol Down while plugging in, Vol Up; then run: heimdall flash --DTB $SDT --DTBO $SDTBO --BOOT $BASE"; exit 2; fi
sleep 3; heimdall flash --DTB "$SDT" --DTBO "$SDTBO" --BOOT "$BASE" 2>&1 | grep -E "upload successful|ERROR|failed"
echo "[$(date +%T)] rolled back (stock DT, baseline BOOT); waiting for UT"
for i in $(seq 1 60); do ssh -o BatchMode=yes -o ConnectTimeout=5 root@"$IP" true 2>/dev/null && break; sleep 4; done
tools/m32_read_618.sh "$IP" "$OUTF"
tools/m24_preflight.sh "$IP" 2>&1 | sed -n '/live phone/,$p'

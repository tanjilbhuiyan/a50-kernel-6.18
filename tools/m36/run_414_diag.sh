#!/bin/bash
# One cycle with the 4.14 diagnostic kernel (owner present, USB-C cable in, phone in UT on the baseline):
#  pre-flight -> software reboot to Download -> flash TEST BOOT only, with reboot -> wait for UT -> confirm the dump file
#  -> read it -> software reboot to Download -> flash baseline BOOT, with reboot -> wait for UT -> pre-flight.
#   tools/m36/run_414_diag.sh TEST_BOOT_IMG OUT_FILE PHONE_IP
set -uo pipefail
IMG=${1:?}; OUTF=${2:?}; IP=${3:?}
R=$(cd "$(dirname "$0")/../.." && pwd); cd "$R"
BASE=baseline/ut-26.04-2026-10-19-aa17rf2/boot.img
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 root@$IP"
RB="heimdall flash --BOOT $BASE"
dl() { lsusb | grep -q "04e8:685d"; }
waitdl() { local t=$1 s=$(date +%s); while [ $(( $(date +%s)-s )) -lt "$t" ]; do dl && return 0; sleep 2; done; return 1; }
settle() { local t=$1 s=$(date +%s) a b; while [ $(( $(date +%s)-s )) -lt "$t" ]; do a=$(lsusb | grep "04e8:685d" | cut -c1-22 || true); sleep 10; b=$(lsusb | grep "04e8:685d" | cut -c1-22 || true); [ -n "$a" ] && [ "$a" = "$b" ] && return 0; done; return 1; }
waitssh() { local i; for i in $(seq 1 "$1"); do timeout 8 $SSH true 2>/dev/null && return 0; sleep 4; done; return 1; }
to_download() { timeout 20 $SSH "sync; setsid nohup sh -c 'sleep 2; systemctl reboot --reboot-argument=download' >/dev/null 2>&1 < /dev/null &" || true; }
flash() { local log rc; log=$(mktemp); heimdall flash --BOOT "$1" >"$log" 2>&1; rc=$?; tr '\r' '\n' <"$log" | grep -E "upload successful|ERROR|failed|Failed"; return $rc; }

[ "$(sha256sum "$BASE" | cut -c1-8)" = "7d5855ef" ] || { echo "baseline hash mismatch, stop"; exit 1; }
tools/m24_preflight.sh "$IP" 2>&1 | tail -1 | grep -q "ALL CHECKS PASSED" || { echo "pre-flight FAILED, stop"; exit 1; }
to_download
waitdl 90 || { echo "phone did not reach Download mode, stop (nothing flashed)"; exit 1; }
settle 60 || { echo "Download connection not steady, stop (nothing flashed)"; exit 1; }
echo "[$(date +%T)] Download mode; flashing test BOOT $(sha256sum "$IMG" | cut -c1-16)"
flash "$IMG" || { echo "TEST FLASH FAILED. Re-enter Download mode with the key combo if needed, then: $RB"; exit 3; }
sleep 10
echo "[$(date +%T)] waiting for UT on the test kernel"
if ! waitssh 60; then
  echo "[$(date +%T)] test kernel not reachable at $IP. It may have another IP (hostname -I on the phone), or not have booted."
  echo "  If it did not boot: Vol Down+Power until black, Vol Up+Vol Down while plugging in, Vol Up, then: $RB"; exit 2; fi
timeout 20 $SSH 'mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug; test -e /sys/kernel/debug/a50_usbdump' || { echo "dump file missing, not the test kernel? Stopping before rollback; run: $RB"; exit 4; }
ok=""; for i in $(seq 1 15); do st=$(timeout 10 $SSH 'cat /sys/class/sec/switch/usb_state; cat /sys/class/udc/*/state' 2>/dev/null | tr '\n' ' '); case "$st" in *CONFIGURED*configured*) ok=1; break;; esac; sleep 4; done
echo "[$(date +%T)] USB state: $st"
if [ -n "$ok" ]; then timeout 30 $SSH 'cat /sys/kernel/debug/a50_usbdump; echo "--- regdump"; grep -E "^(GUCTL|GUSB2PHYCFG\(0\)|GCTL) " /sys/kernel/debug/13200000.dwc3/regdump' > "$OUTF"; echo "[$(date +%T)] saved $OUTF: $(wc -l < "$OUTF") lines"; else echo "USB not configured, dump skipped (PHY clock may be off)"; fi
to_download
waitdl 90 || { echo "no Download mode for the rollback. Enter it with the key combo, then: $RB"; exit 2; }
settle 60 || { echo "Download connection not steady; rollback NOT started. Run: $RB"; exit 3; }
flash "$BASE" || { echo "ROLLBACK FAILED. Re-enter Download mode with the key combo, then: $RB"; exit 3; }
echo "[$(date +%T)] rolled back; waiting for UT"
sleep 10; waitssh 60 || { echo "baseline not reachable at $IP (new IP?)"; exit 5; }
tools/m24_preflight.sh "$IP" 2>&1 | sed -n '/live phone/,$p'

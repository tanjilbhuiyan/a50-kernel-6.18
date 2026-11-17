#!/bin/bash
# M2.4 pre-flight: every image we may flash or roll back to must be present and hash-correct.
#   tools/m24_preflight.sh [PHONE_IP]      (with PHONE_IP also checks the live phone, read-only)
set -u
cd "$(dirname "$0")/.."
fail=0
chk() { # desc expected_sha256 file [max_bytes]
  local d=$1 e=$2 f=$3 m=${4:-}
  if [ ! -f "$f" ]; then printf 'FAIL  %-46s missing %s\n' "$d" "$f"; fail=1; return; fi
  local a; a=$(sha256sum "$f" | cut -c1-64)
  if [ "$a" != "$e" ]; then printf 'FAIL  %-46s sha %s… != %s…\n' "$d" "${a:0:12}" "${e:0:12}"; fail=1; return; fi
  if [ -n "$m" ] && [ "$(stat -c %s "$f")" -gt "$m" ]; then printf 'FAIL  %-46s larger than %s B\n' "$d" "$m"; fail=1; return; fi
  printf 'ok    %-46s %s…\n' "$d" "${e:0:12}"
}
echo "== rollback images (known good)"
chk "baseline boot.img (UT, working)"        7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5 baseline/ut-26.04-2026-10-19-aa17rf2/boot.img 57671680
chk "stock dt.img"                           59209aa52dc3b35e2c7cc025c465ed1cdb48dadaa13cf5d1f50324b3bf503547 reference/stock-images/dt.img 8388608
chk "stock dtbo.img"                         40e47ed1477a8ffb6cbb34e5cb59a1af786c2552544f3b556373f3c553d40d21 reference/stock-images/dtbo.img 8388608
echo "== images to flash for first light"
chk "boot-firstlight.img (M2.2)"             d45d0b6bc681cb56dfa13484c71153491c4c98bd85b6cde31b4839cf6527f43a src/m22/artifacts/boot-firstlight.img 57671680
DTSHA=$(grep ' reference/dt-6.18/images/dt.img\| dt.img' reference/dt-6.18/images/SHA256SUMS | head -1 | cut -c1-64)
chk "A50 dt.img (M2.3 + ramoops move)"       "$DTSHA" reference/dt-6.18/images/dt.img 8388608
chk "A50 dtbo.img (M2.3, no-op overlay)"     6d81cce87faca914d75f024f36e183ae6592e61adc786bbb6c7c47cdd3a151fe reference/dt-6.18/images/dtbo.img 8388608
echo "== snapshot of the phone's current partitions"
for p in dtb dtbo vbmeta; do e=$(grep " $p.img" baseline/m24-pre-flash/SHA256SUMS | cut -c1-64); chk "snapshot $p.img" "$e" baseline/m24-pre-flash/$p.img; done
echo "== deeper rescue (TWRP, vbmeta, firmware)"
( cd ../backup/rescue-images && sha256sum -c SHA256SUMS 2>&1 | sed 's/^/      /' | grep -E "recovery-twrp|vbmeta" ) || true
[ -f ../SAMFW.COM_SM-A505F_BKD_A505FDDS9CWA2_fac.zip ] && echo "ok    stock firmware zip present ($(stat -c %s ../SAMFW.COM_SM-A505F_BKD_A505FDDS9CWA2_fac.zip) B)" || { echo "FAIL  stock firmware zip missing"; fail=1; }
echo "== tools"
for t in heimdall adb; do command -v $t >/dev/null && echo "ok    $t: $($t version 2>&1 | head -1)" || { echo "FAIL  $t not installed"; fail=1; }; done
if [ -n "${1:-}" ]; then
  echo "== live phone $1 (read-only)"
  LIVE=$(ssh -o BatchMode=yes -o ConnectTimeout=15 root@"$1" '
    echo "kernel $(uname -r), up since $(uptime -s), battery $(cat /sys/class/power_supply/battery/capacity)% $(cat /sys/class/power_supply/battery/status)"
    for p in dtb dtbo; do echo "$p $(sha256sum /dev/disk/by-partlabel/$p | cut -c1-64)"; done
    echo "boot $(head -c 53624832 /dev/disk/by-partlabel/boot | sha256sum | cut -c1-64)"' 2>&1) || { echo "FAIL  live phone $1 not readable over ssh: $(echo "$LIVE" | tail -1)"; fail=1; LIVE=""; }
  echo "$LIVE" | while read -r a b c d; do
      case "$a" in
        kernel) echo "      $a $b $c $d";;
        dtb)  [ "$b" = 59209aa52dc3b35e2c7cc025c465ed1cdb48dadaa13cf5d1f50324b3bf503547 ] && echo "ok    live DTB == stock" || echo "FAIL  live DTB differs";;
        dtbo) [ "$b" = 40e47ed1477a8ffb6cbb34e5cb59a1af786c2552544f3b556373f3c553d40d21 ] && echo "ok    live DTBO == stock" || echo "FAIL  live DTBO differs";;
        boot) [ "$b" = 7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5 ] && echo "ok    live BOOT == baseline boot.img" || echo "FAIL  live BOOT differs";;
      esac; done > /tmp/m24-live.out
  cat /tmp/m24-live.out; grep -q '^FAIL' /tmp/m24-live.out && fail=1
  [ -n "$LIVE" ] && [ "$(grep -c '^ok' /tmp/m24-live.out)" -lt 3 ] && { echo "FAIL  fewer than 3 live partition checks passed"; fail=1; }
fi
[ $fail = 0 ] && echo "PRE-FLIGHT: ALL CHECKS PASSED" || { echo "PRE-FLIGHT: FAILED (see above)"; exit 1; }

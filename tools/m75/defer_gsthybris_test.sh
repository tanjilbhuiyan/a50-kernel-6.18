#!/bin/bash
# Host test for tools/m75/defer_gsthybris.sh, run unprivileged in a private user+mount namespace (unshare -rm).
# Cases: correct inputs bind the placeholder read-only; wrong stock file, wrong placeholder and an existing mount refuse
# with nothing mounted and the target unchanged. The stock plugin is not on the host, so a stand-in file with the stock
# hash cannot exist; the hook's stock hash is replaced in a temporary copy by the stand-in's hash (only that constant).
# Usage: bash tools/m75/defer_gsthybris_test.sh
set -u
repo=$(cd "$(dirname "$0")/../.." && pwd)
exec unshare -rm --propagation private bash -s "$repo" <<'EOF'
set -u
repo=$1; adr=$repo/tools/m75/gst/libgsthybris.placeholder
w=$(mktemp -d); stock=$w/libgsthybris.so; printf 'stand-in for the stock ELF plugin\n' > "$stock"
hook=$w/hook.sh; sed "s/^stock_sha=.*/stock_sha=$(sha256sum "$stock" | cut -d' ' -f1)/" "$repo/tools/m75/defer_gsthybris.sh" > "$hook"
[ "$(diff "$repo/tools/m75/defer_gsthybris.sh" "$hook" | grep -c '^[<>]')" = 2 ] || { echo 'FAIL: hook copy differs beyond stock_sha'; exit 1; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
T=usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so
setup() { d=$(mktemp -d); mkdir -p "$d/root/${T%/*}" "$d/run"; cp "$stock" "$d/root/$T"; cp "$adr" "$d/run/ph"; }
run() { ROOT=$d/root A50_GST_PLACEHOLDER=$d/run/ph A50_GST_TEST=1 sh "$hook" >"$d/out" 2>&1; echo $?; }
h() { sha256sum "$1" | cut -d' ' -f1; }
S=$(h "$stock"); A=$(h "$adr")

setup; rc=$(run)
check "good inputs: exit 0" "$rc" 0
check "good inputs: overlay visible" "$(h "$d/root/$T")" "$A"
check "good inputs: read-only" "$(echo x 2>/dev/null >> "$d/root/$T" && echo writable || echo ro)" ro
check "good inputs: no ELF magic (first bytes 'A50 ')" "$(head -c4 "$d/root/$T" | od -An -tx1 | tr -d ' \n')" 41353020
umount "$d/root/$T"
check "good inputs: rootfs file unchanged" "$(h "$d/root/$T")" "$S"

setup; echo '# changed' >> "$d/root/$T"; before=$(h "$d/root/$T"); rc=$(run)
check "modified stock: refuses" "$rc" 1
check "modified stock: not mounted" "$(grep -c " $d/root/$T " /proc/self/mountinfo)" 0
check "modified stock: target unchanged" "$(h "$d/root/$T")" "$before"

setup; echo '# changed' >> "$d/run/ph"; rc=$(run)
check "modified placeholder: refuses" "$rc" 1
check "modified placeholder: target still stock" "$(h "$d/root/$T")" "$S"

setup; run >/dev/null; rc=$(run)
check "second run (already mounted): refuses" "$rc" 1
check "second run: one mount only" "$(grep -c " $d/root/$T " /proc/self/mountinfo)" 1

setup; rc=$(ROOT=$d/root A50_GST_PLACEHOLDER=$d/run/ph sh "$hook" >/dev/null 2>&1; echo $?)
check "non-6.18 kernel without test flag: refuses" "$rc" 1
echo "RESULT: $([ $fails = 0 ] && echo PASS || echo "FAIL ($fails)")"; [ $fails = 0 ]
EOF

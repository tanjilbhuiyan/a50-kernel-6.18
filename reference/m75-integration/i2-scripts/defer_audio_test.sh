#!/bin/bash
# Host test for tools/m75/defer_audio.sh, run unprivileged in a private user+mount namespace (unshare -rm).
# Cases: correct inputs bind the overlay read-only; wrong stock file, wrong overlay and an existing mount refuse
# with nothing mounted and the target unchanged. Usage: bash tools/m75/defer_audio_test.sh
set -u
repo=$(cd "$(dirname "$0")/../.." && pwd)
exec unshare -rm --propagation private bash -s "$repo" <<'EOF'
set -u
repo=$1; hook=$repo/tools/m75/defer_audio.sh; stock=$repo/tools/m75/audio/touch.pa.stock; adr=$repo/tools/m75/audio/touch.pa.adr0005
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
setup() { d=$(mktemp -d); mkdir -p "$d/root/etc/pulse" "$d/run"; cp "$stock" "$d/root/etc/pulse/touch.pa"; cp "$adr" "$d/run/touch.pa"; }
run() { ROOT=$d/root A50_AUDIO_OVERLAY=$d/run/touch.pa A50_AUDIO_TEST=1 sh "$hook" >"$d/out" 2>&1; echo $?; }
h() { sha256sum "$1" | cut -d' ' -f1; }
S=$(h "$stock"); A=$(h "$adr")

setup; rc=$(run)
check "good inputs: exit 0" "$rc" 0
check "good inputs: overlay visible" "$(h "$d/root/etc/pulse/touch.pa")" "$A"
check "good inputs: read-only" "$(echo x 2>/dev/null >> "$d/root/etc/pulse/touch.pa" && echo writable || echo ro)" ro
check "good inputs: no droid module" "$(grep -c '^load-module module-droid-discover' "$d/root/etc/pulse/touch.pa")" 0
umount "$d/root/etc/pulse/touch.pa"
check "good inputs: rootfs file unchanged" "$(h "$d/root/etc/pulse/touch.pa")" "$S"

setup; echo '# changed' >> "$d/root/etc/pulse/touch.pa"; before=$(h "$d/root/etc/pulse/touch.pa"); rc=$(run)
check "modified stock: refuses" "$rc" 1
check "modified stock: not mounted" "$(grep -c " $d/root/etc/pulse/touch.pa " /proc/self/mountinfo)" 0
check "modified stock: target unchanged" "$(h "$d/root/etc/pulse/touch.pa")" "$before"

setup; echo '# changed' >> "$d/run/touch.pa"; rc=$(run)
check "modified overlay: refuses" "$rc" 1
check "modified overlay: target still stock" "$(h "$d/root/etc/pulse/touch.pa")" "$S"

setup; run >/dev/null; rc=$(run)
check "second run (already mounted): refuses" "$rc" 1
check "second run: one mount only" "$(grep -c " $d/root/etc/pulse/touch.pa " /proc/self/mountinfo)" 1

setup; rc=$(ROOT=$d/root A50_AUDIO_OVERLAY=$d/run/touch.pa sh "$hook" >/dev/null 2>&1; echo $?)
check "non-6.18 kernel without test flag: refuses" "$rc" 1
echo "RESULT: $([ $fails = 0 ] && echo PASS || echo "FAIL ($fails)")"; [ $fails = 0 ]
EOF

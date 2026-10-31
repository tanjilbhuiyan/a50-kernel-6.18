#!/bin/sh
# Dump the running phone's merged device tree (compatible + status per node).
# Usage: tools/dump_live_dt.sh <phone-ip> > reference/live-dt-compatibles.tsv
# Output: '#' header lines, then status<TAB>node-path<TAB>compat1|compat2|...
set -e
ssh -o BatchMode=yes "phablet@${1:?phone ip}" '
echo "# model: $(tr -d "\0" < /proc/device-tree/model)"
echo "# root-compatible: $(tr "\0" "|" < /proc/device-tree/compatible)"
echo "# cmdline: $(cat /proc/cmdline)"
echo "# kernel: $(uname -r)"
cd /proc/device-tree && find . -name compatible | sort | while read f; do
  d=$(dirname "$f"); s=okay
  [ -f "$d/status" ] && s=$(tr -d "\0" < "$d/status")
  printf "%s\t%s\t%s\n" "$s" "${d#./}" "$(tr "\0" "|" < "$f" | sed "s/|$//")"
done'

#!/bin/bash
# Read the most recent 6.18 dump (BEGIN/END banners written by the a50_diag DSS readout) from the baseline's
# /proc/last_kmsg, redact device identifiers, save it.      tools/m32_read_618.sh PHONE_IP OUT_FILE
set -euo pipefail
IP=${1:?usage: m32_read_618.sh PHONE_IP OUT_FILE}; OUTF=${2:?}
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
ssh -o BatchMode=yes -o ConnectTimeout=20 root@"$IP" 'cat /proc/last_kmsg' > "$TMP"
python3 -I - "$TMP" "$OUTF" <<'PY'
import sys,re
d=open(sys.argv[1],'rb').read()
b=d.rfind(b"===== A50 6.18 DMESG BEGIN"); e=d.find(b"===== A50 6.18 DMESG END", b if b>=0 else 0)
print("last_kmsg %d bytes; dumps in it: %d"%(len(d), d.count(b"===== A50 6.18 DMESG BEGIN")))
if b<0 or e<0: print("NO complete 6.18 dump found"); sys.exit(1)
t=d[b:e+len(b"===== A50 6.18 DMESG END =====")].replace(b'\0',b'').decode('latin1')+"\n"
pat=re.compile(r'((?:androidboot\.)?(?:serialno|ap_serial|em\.did|uniqueno|bt_?addr|wifi_?mac|macaddr|imei\w*|[\w.]*serial\w*)=)(\S+)',re.I)
t,n=pat.subn(lambda m: m.group(1)+"<redacted>",t)
open(sys.argv[2],'w').write("# 6.18 dump read back from /proc/last_kmsg (identifiers redacted: %d)\n"%n+t)
print("saved %s: %d bytes; header: %s"%(sys.argv[2],len(t),t.splitlines()[0][:80]))
PY

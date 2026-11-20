#!/bin/sh
# Usage: tools/m10/run_audio_contract.sh <phone-ip>. Read-only snapshot + copies of the vendor mixer/audio XMLs.
set -eu
ip=$1; cd "$(dirname "$0")/../.."; raw=src/m10/contract-raw; out=reference/m10-audio; mkdir -p $raw $out/vendor-etc
ssh -o BatchMode=yes -o ConnectTimeout=8 root@$ip 'sh -s' < tools/m10/collect_audio_contract.sh > $raw/snapshot.txt
ssh -o BatchMode=yes root@$ip 'V=/vendor; [ -d $V/etc ] || V=/android/vendor; cd $V/etc && tar cf - $(ls | grep -i -E "^(mixer_|audio_|tfa)" )' > $raw/vendor-etc.tar
tar xf $raw/vendor-etc.tar -C $out/vendor-etc
python3 - "$raw/snapshot.txt" "$out/stock-snapshot.txt" <<'PY'
import re,sys
s=open(sys.argv[1],errors='replace').read()
s=re.sub(r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{2}[_:]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])','<mac>',s)
s=re.sub(r'R28[A-Z0-9]{8,}','<serial>',s)
s=re.sub(r'(androidboot\.(serialno|ap_serial|em\.did)=)\S+',r'\1<redacted>',s)
open(sys.argv[2],'w').write(s)
PY
grep -c '^###' $out/stock-snapshot.txt; ls $out/vendor-etc | head -40

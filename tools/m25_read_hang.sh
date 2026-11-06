#!/bin/bash
# Read the channel-validation marker written by tools/m25_hang_marker.sh (searched anywhere in last_kmsg, since a full
# buffer is exposed rotated).   tools/m25_read_hang.sh PHONE_IP [NONCE]   (NONCE from artifacts-hang/nonce.env)
set -euo pipefail
IP=${1:?usage: m25_read_hang.sh PHONE_IP [NONCE]}; NONCE=${2:-}
ssh -o BatchMode=yes -o ConnectTimeout=20 root@"$IP" 'cat /proc/last_kmsg' | python3 -I -c "
import sys,struct
d=sys.stdin.buffer.read(); n='$NONCE'
full=d.endswith(bytes.fromhex('4675 6c6c 0a00 0000'.replace(' ',''))) or len(d)==2*1024*1024
print('last_kmsg size %d bytes (%s)'%(len(d),'FULL 2 MiB, rotated' if len(d)==2*1024*1024 else 'not full: only head..write pointer'))
i=d.find(b'A50HANG0')
if i<0: print('NO A50HANG0 marker'); sys.exit(1)
q=lambda k: struct.unpack('<Q',d[i+8*k:i+8*k+8])[0]
print('A50HANG0 at snapshot offset %#x'%i)
print('nonce %#x %s'%(q(1),'(matches)' if n and q(1)==int(n,16) else '(expected '+n+')' if n else ''))
print('cave PC %#x -> Image base %#x ; x0 %#x ; CurrentEL %#x'%(q(2),q(2)-0x28d8010-0x24,q(3),q(4)))
"

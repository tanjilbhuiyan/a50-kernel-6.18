#!/bin/bash
# Decode the chain-image shim marker (physical 0xf9030600 = /proc/last_kmsg offset 0x20600) and the diag v2 stage markers.
#   tools/m25_read_chain.sh PHONE_IP [SHIM_ADR_OFF]    (SHIM_ADR_OFF from artifacts-chain/chain.env, default 0x21ff78c)
set -euo pipefail
IP=${1:?usage: m25_read_chain.sh PHONE_IP}; ADR=${2:-0x21ff78c}
ssh -o BatchMode=yes root@"$IP" 'cat /proc/last_kmsg' | python3 -I -c "
import sys,struct
d=sys.stdin.buffer.read(); o=0x20600
q=lambda i: struct.unpack('<Q',d[o+8*i:o+8*i+8])[0]
print('last_kmsg size',len(d))
tag=d[o:o+8]
if tag!=b'A50SHIM0': print('NO shim marker at 0x20600 (found %r): S-Boot did not run the chain image\'s code0'%tag); sys.exit(1)
pc=q(1); print('A50SHIM0 found. shim PC=%#x  x0(DTB)=%#x x1=%#x x2=%#x x3=%#x CurrentEL=%#x'%(pc,q(2),q(3),q(4),q(5),q(6)))
print('Image base = PC - %s = %#x'%('$ADR',pc-int('$ADR',16)))
print('copy finished (A50SHIM1):', d[o+64:o+72]==b'A50SHIM1')
for off,name in ((0x20000,'A50DIAG0'),(0x20020,'A50DIAG6'),(0x20028,'A50DIAG7')):
    print(name, 'present' if d[off:off+8]==name.encode() else 'absent')
"

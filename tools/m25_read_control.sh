#!/bin/bash
# Read the marker left by the CONTROL image (baseline kernel + code cave) from the running baseline phone.
#   tools/m25_read_control.sh PHONE_IP
set -euo pipefail
IP=${1:?usage: m25_read_control.sh PHONE_IP}
ssh -o BatchMode=yes -o ConnectTimeout=20 root@"$IP" 'cat /proc/last_kmsg' > /tmp/lk-control.bin
python3 -I - <<'PY'
import struct
d=open('/tmp/lk-control.bin','rb').read()
print("last_kmsg size",len(d),"bytes")
i=d.find(b"A50DIAG0")
if i<0:
    print("NO marker found: the cave did not run (or the marker channel does not work)"); raise SystemExit(1)
pc,x0,el,x1,x2,x3=struct.unpack('<6Q',d[i+8:i+56])
CAVE_ADR=0x28d8028     # image offset of the cave's `adr` instruction (see tools/m25_control_image.sh)
print("marker found at snapshot offset %#x (expected 0x20000: %s)"%(i,i==0x20000))
print("cave `adr` PC (physical, MMU off): %#x"%pc)
print("  => the Image is loaded at physical %#x"%(pc-CAVE_ADR))
base=pc-CAVE_ADR
print("     2 MiB aligned: %s ; offset from 0x80000000: %#x"%(base%0x200000==0,base-0x80000000))
print("x0 (DTB pointer)  %#x"%x0)
print("x1 %#x  x2 %#x  x3 %#x"%(x1,x2,x3))
print("CurrentEL raw %#x -> EL%d"%(el,(el>>2)&3))
PY
rm -f /tmp/lk-control.bin

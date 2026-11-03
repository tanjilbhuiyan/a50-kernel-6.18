#!/bin/bash
# Read the A50 diagnostic markers back from the BASELINE phone after a diagnostic boot + rollback.
#   tools/m25_read_markers.sh PHONE_IP
# The diagnostic kernel writes markers at physical 0xf9030000 (= offset 0x20000 in the debug-snapshot
# log_kernel buffer); the baseline exposes that buffer as /proc/last_kmsg (a snapshot taken early in the boot).
set -euo pipefail
IP=${1:?usage: m25_read_markers.sh PHONE_IP}
ssh -o BatchMode=yes -o ConnectTimeout=20 root@"$IP" 'cat /proc/last_kmsg' > /tmp/lk-markers.bin
python3 -I - <<'PY'
import struct
d=open('/tmp/lk-markers.bin','rb').read()
print("last_kmsg size", len(d), "bytes")
names={b"A50DIAG1 setup_arch":"stage 1 (setup_arch, early_ioremap)",
       b"A50DIAG2 arch_initcall":"stage 2 (arch_initcall)",
       b"A50DIAG3 late_initcall":"stage 3 (late_initcall, before heartbeat)",
       b"A50DIAG4 trying PSCI SYSTEM_RESET":"stage 4 (heartbeat done, trying PSCI SYSTEM_RESET)",
       b"A50DIAG5 SYSTEM_RESET returned":"stage 5 (PSCI SYSTEM_RESET returned = not supported or ignored)"}
found=False
i=d.find(b"A50DIAG0")
if i>=0:
    found=True
    pc,dtb,el=struct.unpack('<QQQ',d[i+8:i+32])
    print("stage 0 (head.S, MMU off): reached. offset %#x in dump"%i)
    print("   kernel ran at physical address %#x  (2MiB-aligned: %s)"%(pc, pc%0x200000==0))
    print("   DTB pointer from the bootloader %#x"%dtb)
    print("   CurrentEL raw %#x -> EL%d"%(el,(el>>2)&3))
for k,v in names.items():
    j=d.find(k)
    if j>=0: found=True; print(v+": reached (offset %#x)"%j)
if not found: print("NO A50DIAG markers found: the diagnostic kernel did not run any stage, or the markers were overwritten")
PY
rm -f /tmp/lk-markers.bin

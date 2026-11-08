#!/usr/bin/env python3
"""M3.5: host unit test of the A50_UFS_SAFE guard.

Extracts the real decision code and self-test (A50-GUARD-BEGIN..END) from the kernel source, takes the constants from the
kernel headers, compiles natively and runs it unmodified and with deliberate faults. The self-test must report 0 errors on the
real code and >0 on every mutant, otherwise the self-test would not protect anything.
Usage: python3 -I tools/m35/guard_unittest.py KERNEL_TREE
"""
import os, re, subprocess, sys, tempfile
tree = sys.argv[1]
src = open(os.path.join(tree, 'drivers/ufs/core/ufshcd.c')).read()
code = src[src.index('/* A50-GUARD-BEGIN'):src.index('/* A50-GUARD-END */')]
proto = open(os.path.join(tree, 'include/scsi/scsi_proto.h')).read()
ufs = open(os.path.join(tree, 'include/ufs/ufs.h')).read()
defs = []
for n in 'TEST_UNIT_READY REQUEST_SENSE READ_6 INQUIRY MODE_SENSE START_STOP READ_CAPACITY READ_10 MODE_SENSE_10 READ_16 REPORT_LUNS SERVICE_ACTION_IN_16 SAI_READ_CAPACITY_16 WRITE_10 WRITE_16 SYNCHRONIZE_CACHE UNMAP WRITE_BUFFER FORMAT_UNIT'.split():
    defs.append('#define %s %s' % (n, re.search(r'#define\s+%s\s+(0x[0-9a-fA-F]+)' % n, proto).group(1)))
e = ufs[ufs.index('enum query_opcode {'):]; e = e[:e.index('};')]
for n, v in re.findall(r'(UPIU_QUERY_OPCODE_\w+)\s*=\s*(0x[0-9a-fA-F]+)', e): defs.append('#define %s %s' % (n, v))
defs.append('#define QUERY_FLAG_IDN_FDEVICEINIT %s' % re.search(r'QUERY_FLAG_IDN_FDEVICEINIT\s*=\s*(0x[0-9a-fA-F]+)', ufs).group(1))
head = '#include <stdio.h>\n#include <stdbool.h>\ntypedef unsigned char u8;\n#define noinline\n' + '\n'.join(defs) + '\n'
tail = '\nint main(void){printf("%d\\n",a50_ufs_guard_selftest());return 0;}\n'
A = '\tcase READ_10:\n'
Q = '\tcase UPIU_QUERY_OPCODE_READ_DESC:\n'
muts = [
 ('allow WRITE(10)', lambda c: c.replace(A, A + '\tcase WRITE_10:\n', 1)),
 ('allow WRITE(16)', lambda c: c.replace(A, A + '\tcase WRITE_16:\n', 1)),
 ('allow SYNCHRONIZE_CACHE', lambda c: c.replace(A, A + '\tcase SYNCHRONIZE_CACHE:\n', 1)),
 ('allow UNMAP', lambda c: c.replace(A, A + '\tcase UNMAP:\n', 1)),
 ('allow WRITE_BUFFER', lambda c: c.replace(A, A + '\tcase WRITE_BUFFER:\n', 1)),
 ('allow FORMAT_UNIT', lambda c: c.replace(A, A + '\tcase FORMAT_UNIT:\n', 1)),
 ('SCSI default allows', lambda c: c.replace('\tdefault:\n\t\treturn false;', '\tdefault:\n\t\treturn true;', 1)),
 ('any service action allowed', lambda c: c.replace('return (cdb[1] & 0x1f) == SAI_READ_CAPACITY_16;', 'return true;', 1)),
 ('drop READ_10 (over-strict)', lambda c: c.replace(A, '', 1)),
 ('allow WRITE_ATTR', lambda c: c.replace(Q, Q + '\tcase UPIU_QUERY_OPCODE_WRITE_ATTR:\n', 1)),
 ('allow WRITE_DESC', lambda c: c.replace(Q, Q + '\tcase UPIU_QUERY_OPCODE_WRITE_DESC:\n', 1)),
 ('allow CLEAR_FLAG', lambda c: c.replace(Q, Q + '\tcase UPIU_QUERY_OPCODE_CLEAR_FLAG:\n', 1)),
 ('any flag may be set', lambda c: c.replace('return idn == QUERY_FLAG_IDN_FDEVICEINIT;', 'return true;', 1)),
 ('query default allows', lambda c: c[::-1].replace('\tdefault:\n\t\treturn false;'[::-1], '\tdefault:\n\t\treturn true;'[::-1], 1)[::-1]),
]
def run(c):
    with tempfile.TemporaryDirectory() as d:
        s, x = d + '/t.c', d + '/t'
        open(s, 'w').write(head + c + tail)
        subprocess.check_call(['gcc', '-std=gnu11', '-w', '-o', x, s])
        return int(subprocess.check_output([x]).strip())
base = run(code)
print('real guard code: %d wrong decisions' % base)
bad = base != 0
for name, f in muts:
    m = f(code)
    if m == code: print('MUTANT NOT APPLIED: ' + name); bad = True; continue
    n = run(m)
    print('mutant %-30s -> %6d wrong decisions  %s' % (name, n, 'caught' if n else 'MISSED'))
    bad |= n == 0
print('RESULT: ' + ('FAIL' if bad else 'PASS'))
sys.exit(1 if bad else 0)

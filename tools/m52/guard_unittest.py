#!/usr/bin/env python3
"""M5.2: host unit test of the A50_UFS_SAFE guard with the userdata write allow-list.

Extracts the real decision code and self-tests (A50-GUARD-BEGIN..END) from the kernel source, takes the constants from
the kernel headers, compiles natively and runs the self-tests (read guard, invalid range, synthetic range, the real
userdata range) on the unmodified code and on deliberate faults. Real code must give 0 wrong decisions; every mutant > 0.
Usage: python3 -I tools/m52/guard_unittest.py KERNEL_TREE FIRST LAST   (FIRST/LAST: userdata blocks, e.g. 0x1234)
"""
import os, re, subprocess, sys, tempfile
tree, first, last = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(os.path.join(tree, 'drivers/ufs/core/ufshcd.c')).read()
code = src[src.index('/* A50-GUARD-BEGIN'):src.index('/* A50-GUARD-END */')]
proto = open(os.path.join(tree, 'include/scsi/scsi_proto.h')).read()
ufs = open(os.path.join(tree, 'include/ufs/ufs.h')).read()
defs = []
for n in ('TEST_UNIT_READY REQUEST_SENSE READ_6 INQUIRY MODE_SENSE START_STOP READ_CAPACITY READ_10 MODE_SENSE_10 READ_16 '
          'REPORT_LUNS SERVICE_ACTION_IN_16 SAI_READ_CAPACITY_16 WRITE_6 WRITE_10 WRITE_16 SYNCHRONIZE_CACHE SYNCHRONIZE_CACHE_16 '
          'UNMAP WRITE_SAME_16 WRITE_BUFFER FORMAT_UNIT').split():
    defs.append('#define %s %s' % (n, re.search(r'#define\s+%s\s+(0x[0-9a-fA-F]+)' % n, proto).group(1)))
e = ufs[ufs.index('enum query_opcode {'):]; e = e[:e.index('};')]
for n, v in re.findall(r'(UPIU_QUERY_OPCODE_\w+)\s*=\s*(0x[0-9a-fA-F]+)', e): defs.append('#define %s %s' % (n, v))
defs.append('#define QUERY_FLAG_IDN_FDEVICEINIT %s' % re.search(r'QUERY_FLAG_IDN_FDEVICEINIT\s*=\s*(0x[0-9a-fA-F]+)', ufs).group(1))
head = ('#include <stdio.h>\n#include <stdbool.h>\ntypedef unsigned char u8;typedef unsigned int u32;typedef unsigned long long u64;\n'
        '#define noinline\n#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))\n' + '\n'.join(defs) + '\n')
tail = ('\nint main(void){printf("%%d %%d %%d %%d\\n",a50_ufs_guard_selftest(),a50_ufs_write_selftest(0,0),'
        'a50_ufs_write_selftest(0x1000,0x1fff),a50_ufs_write_selftest(%sULL,%sULL));return 0;}\n' % (first, last))
W = '\tcase WRITE_10:\n\t\tlba'
muts = [
 ('any LUN may write', lambda c: c.replace('if (lun != 0 || first == 0', 'if (first == 0', 1)),
 ('start off by one', lambda c: c.replace('lba >= first && lba <= last', 'lba >= first - 1 && lba <= last', 1)),
 ('end off by one', lambda c: c.replace('len - 1 <= last - lba;', 'len - 1 <= last - lba + 1;', 1)),
 ('length ignored', lambda c: c.replace('len - 1 <= last - lba;', '1;', 1)),
 ('upper bound ignored', lambda c: c.replace('lba >= first && lba <= last &&', 'lba >= first &&', 1)),
 ('invalid range allowed', lambda c: c.replace('|| first == 0 || last < first)', ')', 1)),
 ('allow WRITE(6)', lambda c: c.replace(W, '\tcase WRITE_6: return true;\n' + W, 1)),
 ('allow UNMAP', lambda c: c.replace(W, '\tcase UNMAP: return true;\n' + W, 1)),
 ('allow WRITE SAME(16)', lambda c: c.replace(W, '\tcase WRITE_SAME_16: return true;\n' + W, 1)),
 ('write default allows', lambda c: c.replace('\tdefault:\n\t\treturn false;\n\t}\n\treturn len', '\tdefault:\n\t\treturn true;\n\t}\n\treturn len', 1)),
 ('WRITE(10) LBA bytes swapped', lambda c: c.replace('((u64)cdb[4] << 8) | cdb[5];', '((u64)cdb[5] << 8) | cdb[4];', 1)),
 ('WRITE(10) length byte wrong', lambda c: c.replace('len = ((u32)cdb[7] << 8) | cdb[8];', 'len = cdb[8];', 1)),
 ('no flush (over-strict)', lambda c: c.replace('\tcase SYNCHRONIZE_CACHE:\n\tcase SYNCHRONIZE_CACHE_16:\n\t\treturn true;\n', '', 1)),
 ('read guard: allow WRITE(10)', lambda c: c.replace('\tcase READ_10:\n', '\tcase READ_10:\n\tcase WRITE_10:\n', 1)),
]
def run(c):
    with tempfile.TemporaryDirectory() as d:
        s, x = d + '/t.c', d + '/t'
        open(s, 'w').write(head + c + tail)
        subprocess.check_call(['gcc', '-std=gnu11', '-w', '-o', x, s])
        return [int(v) for v in subprocess.check_output([x]).split()]
base = run(code)
print('real guard code: read guard %d, invalid range %d, synthetic range %d, userdata %s-%s %d wrong decisions' % (base[0], base[1], base[2], first, last, base[3]))
bad = sum(base) != 0
for name, f in muts:
    m = f(code)
    if m == code: print('MUTANT NOT APPLIED: ' + name); bad = True; continue
    n = sum(run(m))
    print('mutant %-30s -> %6d wrong decisions  %s' % (name, n, 'caught' if n else 'MISSED'))
    bad |= n == 0
print('RESULT: ' + ('FAIL' if bad else 'PASS'))
sys.exit(1 if bad else 0)

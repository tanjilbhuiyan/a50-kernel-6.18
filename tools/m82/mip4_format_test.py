#!/usr/bin/env python3
"""M8.2 host check: melfas_mip4 touch-packet decoding for event formats 3 and 8.

Extracts the event_format switch from mip4_report_touch() in KERNEL_TREE/drivers/input/touchscreen/melfas_mip4.c,
compiles it natively, and decodes packets built from Samsung's MSS100 field layout (4.14 melfas_mss100.h,
EVENT_FORMAT_WITH_PRESSURE = 3 and EVENT_FORMAT_WITH_PRESSURE_2BYTE = 8). Every decoded field must match. Two broken
copies (format 8 decoded with the format-3 offsets; X/Y nibbles swapped) must fail.
Usage: python3 -I tools/m82/mip4_format_test.py KERNEL_TREE
"""
import os, re, subprocess, sys, tempfile

src = open(os.path.join(sys.argv[1], 'drivers/input/touchscreen/melfas_mip4.c')).read()
fn = src[src.index('static void mip4_report_touch('):]
sw_start = fn.index('\tswitch (ts->event_format) {')
depth, i = 0, sw_start
while True:
    if fn[i] == '{': depth += 1
    elif fn[i] == '}':
        depth -= 1
        if depth == 0: break
    i += 1
switch = fn[sw_start:i + 1]

def harness(sw):
    return r'''#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#define BIT(n) (1u << (n))
typedef uint8_t u8; typedef uint16_t u16;
struct ts_s { int event_format; };
static void decode(struct ts_s *ts, const u8 *packet) {
	int id; bool hover; bool palm; bool state; u16 x, y; u8 pressure_stage = 0; u8 pressure; u8 size;
	u8 touch_major; u8 touch_minor;
''' + sw + r'''
	printf("%d %d %d %d %d %d %d %d %d %d %d\n", id, hover, palm, state, x, y, size, pressure_stage, pressure,
	       touch_major, touch_minor);
}
int main(void) {
	unsigned v[12]; int fmt; struct ts_s ts; u8 p[12]; int i;
	while (scanf("%d", &fmt) == 1) {
		for (i = 0; i < 12; i++) { scanf("%u", &v[i]); p[i] = v[i]; }
		ts.event_format = fmt; decode(&ts, p);
	}
	return 0;
}
'''

def samsung(fmt, f):
    """Build a packet with Samsung's layout from field dict f; return packet and the fields mainline reports."""
    p = [0] * 12
    p[0] = (1 << 4) | (f['id'] + 1)           # type SCREEN (1) in the high nibble, slot+1 in the low nibble
    p[1] = (f['hover'] << 2) | (f['palm'] << 1) | f['state']
    p[2] = ((f['y'] >> 8) << 4) | (f['x'] >> 8); p[3] = f['x'] & 0xff; p[4] = f['y'] & 0xff
    if fmt == 3:
        p[5] = f['z'] & 0xff; p[6] = f['size']; p[7] = (f['stage'] << 4) | (f['pressure'] >> 8)
        p[8] = f['pressure'] & 0xff; p[9] = f['major']; p[10] = f['minor']
    else:
        p[5] = f['z'] & 0xff; p[6] = f['z'] >> 8; p[7] = f['size']; p[8] = (f['stage'] << 4) | (f['pressure'] >> 8)
        p[9] = f['pressure'] & 0xff; p[10] = f['major']; p[11] = f['minor']
    exp = [f['id'], f['hover'], f['palm'], f['state'], f['x'], f['y'], f['size'], f['stage'], f['pressure'] & 0xff,
           f['major'], f['minor']]                 # mainline stores pressure in a u8 (existing format-3 behaviour)
    return p, exp

cases = [dict(id=0, hover=0, palm=0, state=1, x=540, y=1170, z=0x1234, size=9, stage=2, pressure=0x0abc, major=11, minor=7),
         dict(id=9, hover=1, palm=1, state=0, x=4095, y=4095, z=0xffff, size=255, stage=15, pressure=0x0fff, major=255, minor=0),
         dict(id=4, hover=0, palm=1, state=1, x=1, y=2339, z=0, size=0, stage=0, pressure=0, major=0, minor=255)]

def run(sw):
    with tempfile.TemporaryDirectory() as d:
        c, x = d + '/t.c', d + '/t'
        open(c, 'w').write(harness(sw))
        subprocess.check_call(['gcc', '-std=gnu11', '-w', '-o', x, c])
        inp, exps = '', []
        for fmt in (3, 8):
            for f in cases:
                p, e = samsung(fmt, f); inp += '%d %s\n' % (fmt, ' '.join(map(str, p))); exps.append((fmt, e))
        out = subprocess.run([x], input=inp, capture_output=True, text=True, check=True).stdout.split('\n')
        bad = 0
        for (fmt, e), line in zip(exps, out):
            got = list(map(int, line.split()))
            if got != e:
                bad += 1; print('  format %d: got %s want %s' % (fmt, got, e))
        return bad

bad = run(switch)
print('real decoder: %d wrong packets' % bad)

# Real format-8 events captured from the A50 in M8.2 P2 (reference/m82-touch/p2-*), decoded by hand from Samsung's layout.
real = [('11 01 96 20 6a 42 03 30 00 00 03 02', [0, 0, 0, 1, 0x620, 0x96a, 0x30, 0, 0, 3, 2]),
        ('12 01 68 4c c2 42 03 30 00 00 03 02', [1, 0, 0, 1, 0x84c, 0x6c2, 0x30, 0, 0, 3, 2]),
        ('12 00 b9 c6 d8 00 00 00 00 00 00 00', [1, 0, 0, 0, 0x9c6, 0xbd8, 0, 0, 0, 0, 0])]
with tempfile.TemporaryDirectory() as d:
    c, x = d + '/t.c', d + '/t'
    open(c, 'w').write(harness(switch)); subprocess.check_call(['gcc', '-std=gnu11', '-w', '-o', x, c])
    out = subprocess.run([x], input=''.join('8 %s\n' % ' '.join(str(int(b, 16)) for b in p.split()) for p, _ in real),
                         capture_output=True, text=True, check=True).stdout.split('\n')
    rbad = sum(1 for (p, e), line in zip(real, out) if list(map(int, line.split())) != e)
    print('captured A50 packets: %d of %d decoded as expected' % (len(real) - rbad, len(real)))
    bad += rbad
fail = bad != 0
muts = [('format 8 with format-3 offsets', lambda s: s.replace('size = packet[7];', 'size = packet[6];', 1)),
        ('X/Y nibbles swapped in format 8', lambda s: s.replace('case 8:', 'case 8: /*m*/', 1).replace(
            "x = ((packet[2] & 0x0F) << 8) | packet[3];\n\t\ty = (((packet[2] >> 4) & 0x0F) << 8) |\n\t\t\tpacket[4];\n\t\tsize = packet[7];",
            "x = (((packet[2] >> 4) & 0x0F) << 8) | packet[3];\n\t\ty = ((packet[2] & 0x0F) << 8) |\n\t\t\tpacket[4];\n\t\tsize = packet[7];", 1))]
for name, m in muts:
    ms = m(switch)
    if ms == switch:
        print('MUTANT NOT APPLIED: ' + name); fail = True; continue
    k = run(ms)
    print('mutant %-34s -> %d wrong packets  %s' % (name, k, 'caught' if k else 'MISSED'))
    fail |= k == 0
print('RESULT: ' + ('FAIL' if fail else 'PASS'))
sys.exit(1 if fail else 0)

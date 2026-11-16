#!/usr/bin/env python3
"""M7.3 G2c: host check of the a50-decon WIN_CONFIG format translation.

Extracts a50_abi_to_dpp() and a50_to_argb() from drivers/video/fbdev/a50-decon.c, compiles them natively and checks
every ABI 8888 format: one known colour (R=0xf0 G=0x11 B=0x22 A=0x80) is written in the format's Android byte order
(RGBA_8888 = bytes R,G,B,A; ARGB_8888 = A,R,G,B; ...; X = ignored byte), read as a little-endian word as the CPU
bridge does, translated and converted. Every format must give the boot framebuffer's ARGB word 0x80f01122 (alpha
0xff for X formats). Deliberately broken copies (old pass-through mapping, swapped RGBA/ABGR entries, missing alpha
fill) must fail. Usage: python3 -I tools/m73/format_unittest.py KERNEL_TREE
"""
import os, re, subprocess, sys, tempfile

src = open(os.path.join(sys.argv[1], 'drivers/video/fbdev/a50-decon.c')).read()
start = src.index('#define DPP_ARGB_8888')
end = src.index('\n}\n', src.index('static u32 a50_to_argb(')) + 3
code = src[start:end]
head = ('#include <stdio.h>\n#include <stdint.h>\ntypedef uint32_t u32; typedef int8_t s8;\n'
        '#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))\n#define swab32 __builtin_bswap32\n')
tail = r'''
int main(void) {
	/* byte order per ABI format, A R G B X as 'A','R','G','B','X' */
	const char *order[8] = { "ARGB", "ABGR", "RGBA", "BGRA", "XRGB", "XBGR", "RGBX", "BGRX" };
	unsigned char val[256] = { 0 };
	int fails = 0, f, i;
	val['A'] = 0x80; val['R'] = 0xf0; val['G'] = 0x11; val['B'] = 0x22; val['X'] = 0x00;
	for (f = 0; f < 8; f++) {
		unsigned char b[4]; u32 w, got, want = (order[f][0] == 'X' || order[f][3] == 'X') ? 0xfff01122 : 0x80f01122;
		for (i = 0; i < 4; i++) b[i] = val[(unsigned char)order[f][i]];
		w = b[0] | b[1] << 8 | b[2] << 16 | (u32)b[3] << 24;
		got = a50_to_argb(w, a50_abi_to_dpp(f));
		if (got != want) { fails++; printf("format %d %s: dpp %d got 0x%08x want 0x%08x\n", f, order[f], a50_abi_to_dpp(f), got, want); }
	}
	printf("%d\n", fails);
	return 0;
}
'''

def run(c):
    with tempfile.TemporaryDirectory() as d:
        s, x = d + '/t.c', d + '/t'
        open(s, 'w').write(head + c + tail)
        subprocess.check_call(['gcc', '-std=gnu11', '-w', '-o', x, s])
        out = subprocess.check_output([x]).decode().strip().splitlines()
        return int(out[-1]), out[:-1]

bad = False
n, detail = run(code)
print('real translation: %d wrong formats' % n)
for line in detail:
    print('  ' + line)
bad |= n != 0
muts = [
    ('pass-through (M7.2 behaviour)', lambda c: re.sub(r'return abi < ARRAY_SIZE\(map\) \? map\[abi\] : -1;', 'return abi < 8 ? (int)abi : -1;', c)),
    ('RGBA/ABGR entries swapped', lambda c: c.replace('[1] = DPP_RGBA_8888,', '[1] = DPP_ABGR_8888,').replace('[2] = DPP_ABGR_8888,', '[2] = DPP_RGBA_8888,')),
    ('no alpha fill for X formats', lambda c: c.replace('case DPP_XRGB_8888:\treturn v | 0xff000000;', 'case DPP_XRGB_8888:\treturn v;')),
]
for name, f in muts:
    m = f(code)
    if m == code:
        print('MUTANT NOT APPLIED: ' + name)
        bad = True
        continue
    k, _ = run(m)
    print('mutant %-32s -> %d wrong formats  %s' % (name, k, 'caught' if k else 'MISSED'))
    bad |= k == 0
print('RESULT: ' + ('FAIL' if bad else 'PASS'))
sys.exit(1 if bad else 0)

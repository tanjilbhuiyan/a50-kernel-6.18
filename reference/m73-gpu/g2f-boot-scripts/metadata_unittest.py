#!/usr/bin/env python3
"""Compile the real metadata ABI/helper/dispatcher; inject user-copy failures."""
from pathlib import Path
import subprocess
import sys
import tempfile

source = (Path(sys.argv[1]) / 'drivers/video/fbdev/a50-decon.c').read_text()
abi = source[source.index('/* G2f metadata ABI:'):source.index('/* HWC power modes')]
start = source.index('static int a50_display_info(')
code = source[start:source.index('static const struct fb_ops', start)]
head = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>
typedef uint32_t u32; typedef uint8_t u8; typedef uint32_t __u32;
#define __user
#define S3CFB_SET_VSYNC_INT _IOW('F', 206, __u32)
#define S3CFB_WIN_CONFIG 0x441046d1U
#define S3CFB_POWER_MODE _IOW('F', 223, __u32)
#define DECON_POWER_MODE_OFF 0
#define DECON_POWER_MODE_DOZE_SUSPEND 3
struct a50_decon { bool vsync_on; int hw_lock; };
struct fb_info { struct a50_decon *par; };
static unsigned from_calls, to_calls;
static int from_fault, to_fault;
static unsigned long copy_from_user(void *d, const void *s, size_t n) {
 from_calls++; if (from_fault) return n; memcpy(d,s,n); return 0;
}
static unsigned long copy_to_user(void *d, const void *s, size_t n) {
 to_calls++; if (to_fault) return n; memcpy(d,s,n); return 0;
}
#define get_user(v,p) ((v)=*(p),0)
static void mutex_lock(int *p) { (void)p; }
static void mutex_unlock(int *p) { (void)p; }
static int a50_win_config(struct a50_decon *d, void *p) { (void)d; (void)p; return -999; }
static void a50_set_blank_locked(struct a50_decon *d, int p) { (void)d; (void)p; }
'''
tail = r'''
int main(void) {
 struct a50_decon dev = {0}; struct fb_info fb = {.par=&dev};
 struct { unsigned char pre[16]; struct a50_disp_info data; unsigned char post[16]; } b;
 memset(&b,0xa5,sizeof(b)); b.data.ver=0x12345678;
 assert(a50_fb_ioctl(&fb,EXYNOS_DISP_INFO,(unsigned long)&b.data)==0);
 assert(from_calls==1 && to_calls==1);
 assert(b.data.ver==0x12345678 && b.data.psr_mode==2 && b.data.chip_ver==9610);
 assert(b.data.mres_info.mres_en==0 && b.data.mres_info.mres_number==1);
 assert(b.data.mres_info.res_info[0].width==68 && b.data.mres_info.res_info[0].height==147);
 assert(!b.data.mres_info.res_info[0].dsc_en && !b.data.mres_info.res_info[0].dsc_width && !b.data.mres_info.res_info[0].dsc_height);
 for (unsigned i=1;i<5;i++) {
  const unsigned char *p=(void *)&b.data.mres_info.res_info[i];
  for (size_t j=0;j<sizeof(b.data.mres_info.res_info[i]);j++) assert(p[j]==0);
 }
 for(unsigned i=0;i<128;i++) assert(b.data.reserved[i]==0xa5);
 for(unsigned i=0;i<16;i++) assert(b.pre[i]==0xa5 && b.post[i]==0xa5);
 from_fault=1; from_calls=to_calls=0;
 assert(a50_fb_ioctl(&fb,EXYNOS_DISP_INFO,0)==-EFAULT && from_calls==1 && to_calls==0);
 from_fault=0; to_fault=1; from_calls=to_calls=0;
 assert(a50_fb_ioctl(&fb,EXYNOS_DISP_INFO,(unsigned long)&b.data)==-EFAULT && from_calls==1 && to_calls==1);
 assert(a50_fb_ioctl(&fb,0xdeadbeef,0)==-ENOTTY);
 assert(a50_fb_ioctl(&fb,0x400446bc,0)==-ENOTTY);
 puts("PASS: actual dispatcher, 248-byte ABI, metadata, canaries, preserved caller data and copy faults");
 return 0;
}
'''
mutants = {
    'old missing ioctl': code.replace('case EXYNOS_DISP_INFO:', 'case 0xdead1234:'),
    'reserved bytes lost': code.replace('data.psr_mode = 2;', 'memset(data.reserved, 0, sizeof(data.reserved)); data.psr_mode = 2;'),
    'copyout failure ignored': code.replace('if (copy_to_user(arg, &data, sizeof(data)))\n\t\treturn -EFAULT;', 'if (copy_to_user(arg, &data, sizeof(data)))\n\t\treturn 0;'),
    'pixel dimensions in mres': code.replace('.width = 68, .height = 147', '.width = 1080, .height = 2340'),
}
with tempfile.TemporaryDirectory(prefix='a50-metadata-') as temporary:
    path = Path(temporary)
    for name, candidate in [('real source', code), *mutants.items()]:
        assert name == 'real source' or candidate != code, name
        (path/'test.c').write_text(head + abi + candidate + tail)
        subprocess.run(['gcc','-std=gnu11','-O2','-Wall','-Wextra','-Werror',
                        str(path/'test.c'),'-o',str(path/'test')],check=True)
        result = subprocess.run(['sh','-c','ulimit -c 0; exec "$1"','sh',str(path/'test')],capture_output=True,text=True)
        print(name + ': ' + ('PASS' if result.returncode == 0 else 'rejected'))
        assert (name == 'real source') == (result.returncode == 0), name
print('RESULT: PASS (original missing-handler and three broken-handler controls caught)')

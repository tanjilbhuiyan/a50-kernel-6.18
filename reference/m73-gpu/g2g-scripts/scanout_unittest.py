#!/usr/bin/env python3
"""Exercise real stride eligibility, SG mapping and register/fallback code."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

s = (Path(sys.argv[1])/'drivers/video/fbdev/a50-decon.c').read_text()
names = ['a50_set_scanout','a50_dma_bytes','a50_dma_eligible',
         'a50_scan_range_ok','a50_scan_map','a50_show_bootfb_locked']
parts = []
for name in names:
    m = re.search(r'^static (?:void|bool|u32|u64) '+name+r'\([^;]+?\n\{', s, re.M)
    assert m, name
    parts.append(s[m.start():s.index('\n}\n',m.end())+3])
constants = '\n'.join(l for l in s.splitlines() if re.match(
    r'#define (?:IDMA_(?:IN_CON|IMG_FORMAT_SHIFT|IMG_FORMAT_MASK|SRC_SIZE|SRC_OFFSET|IMG_SIZE|IN_BASE_ADDR_Y)|A50_SRC_FULL_[WH]_MAX)\s',l))
head = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32; typedef uint64_t u64; typedef uint64_t dma_addr_t;
#define U32_MAX UINT32_MAX
#define U64_MAX UINT64_MAX
#define FB_W 1080
#define FB_H 2340
#define FMT_ARGB_8888 0
#define WRITE_ONCE(x,v) ((x)=(v))
#define dev_info_ratelimited(...) ((void)0)
#define IS_ERR(x) ((uintptr_t)(x)>=(uintptr_t)-4095)
struct frame { int32_t x,y; u32 w,h,f_w,f_h; };
struct dma_buf { uint64_t size; };
struct dma_buf_attachment { int dummy; };
struct scatterlist { dma_addr_t addr; u32 len; };
struct sg_table { struct scatterlist *sgl; unsigned nents; };
struct a50_layer { struct dma_buf *buf; int dpp; bool linear; struct frame src,dst; };
struct a50_decon { void *idma; u32 scan_full_w,scan_full_h; u32 fb_base; void *dev;
 struct dma_buf *scan_buf; struct dma_buf_attachment *scan_att; struct sg_table *scan_sgt; };
static struct scatterlist segments[3];
static struct sg_table table={segments,1};
static struct dma_buf_attachment attachment;
static unsigned attached,mapped,unmapped,detached,waited,framed,released;
#define DMA_TO_DEVICE 1
#define for_each_sgtable_dma_sg(t,sg,i) for((i)=0;(i)<(t)->nents && ((sg)=&(t)->sgl[i],1);(i)++)
#define sg_dma_address(sg) ((sg)->addr)
#define sg_dma_len(sg) ((sg)->len)
static struct dma_buf_attachment *dma_buf_attach(struct dma_buf *b,void *d) {(void)b;(void)d;attached++;return &attachment;}
static struct sg_table *dma_buf_map_attachment_unlocked(struct dma_buf_attachment *a,int d) {(void)a;(void)d;mapped++;return &table;}
static void dma_buf_unmap_attachment_unlocked(struct dma_buf_attachment *a,struct sg_table *t,int d) {(void)a;(void)t;(void)d;unmapped++;}
static void dma_buf_detach(struct dma_buf *b,struct dma_buf_attachment *a) {(void)b;(void)a;detached++;}
static u32 readl(const void *p) {return *(const u32 *)p;}
static void writel(u32 v,void *p) {*(u32 *)p=v;}
static void a50_wait_shadow(struct a50_decon *d) {(void)d;waited++;}
static void a50_frame_sync(struct a50_decon *d) {(void)d;assert(waited==1);framed++;}
static void a50_scan_release(struct dma_buf *b,struct dma_buf_attachment *a,struct sg_table *t) {(void)b;(void)a;(void)t;assert(framed==1);released++;}
'''
tail = r'''
int main(void) {
 struct dma_buf buf={UINT64_MAX};
 struct a50_layer l={.buf=&buf,.dpp=1,.linear=true,.src={0,0,FB_W,FB_H,1088,2352},.dst={0,0,FB_W,FB_H,FB_W,FB_H}};
 const u64 bytes=1088ULL*2352*4;
 assert(a50_dma_eligible(&l) && a50_dma_bytes(&l)==bytes);
 buf.size=bytes-1; assert(!a50_dma_eligible(&l));
 buf.size=FB_W*FB_H*4; assert(!a50_dma_eligible(&l));
 buf.size=UINT64_MAX;
 l.src.f_w=FB_W;l.src.f_h=FB_H;assert(a50_dma_bytes(&l)==(u64)FB_W*FB_H*4);
 l.src.f_w=1088;l.src.f_h=2352;
 struct a50_layer good=l;
 l.linear=false;assert(!a50_dma_eligible(&l));l=good;
 l.dpp=-1;assert(!a50_dma_eligible(&l));l=good;
 l.src.x=-1;assert(!a50_dma_eligible(&l));l=good;
 l.dst.x=1;assert(!a50_dma_eligible(&l));l=good;
 l.src.w=1079;assert(!a50_dma_eligible(&l));l=good;
 l.src.f_w=1079;assert(!a50_dma_eligible(&l));l=good;
 l.src.f_h=2339;assert(!a50_dma_eligible(&l));l=good;
 l.src.f_w=65535;assert(!a50_dma_eligible(&l));l=good;
 l.src.f_h=8191;assert(!a50_dma_eligible(&l));l=good;
 l.src.f_w=UINT32_MAX;l.src.f_h=UINT32_MAX;assert(!a50_dma_eligible(&l));l=good;
 assert(a50_scan_range_ok(0x100000,0x100000+bytes,bytes));
 assert(!a50_scan_range_ok(0,bytes,bytes));
 assert(!a50_scan_range_ok(0x100000,0x100000+bytes-1,bytes));
 assert(!a50_scan_range_ok(0x100000,0x100000+bytes,0));
 assert(!a50_scan_range_ok(0xfff00000,0xfff00000ULL+bytes,bytes));
 assert(!a50_scan_range_ok(0x100000000ULL,0x100000000ULL+bytes,bytes));
 assert(!a50_scan_range_ok(0xfffffffffffff000ULL,0x1000,bytes));
 assert(a50_scan_range_ok(0x100000000ULL-bytes,0x100000000ULL,bytes));
 u32 regs[64]={0};struct a50_decon d={.idma=regs,.fb_base=0xca000000};
 struct dma_buf_attachment *a=NULL;struct sg_table *t=NULL;
 segments[0]=(struct scatterlist){0x100000,4096};
 segments[1]=(struct scatterlist){0x101000,(u32)bytes-4096};table.nents=2;
 assert(a50_scan_map(&d,&l,&a,&t)==0x100000 && a==&attachment && t==&table);
 assert(attached==1 && mapped==1 && !unmapped && !detached);
 segments[0].len=FB_W*FB_H*4;segments[1].addr=0x100000+segments[0].len+4096;
 assert(a50_scan_map(&d,&l,&a,&t)==0 && unmapped==1 && detached==1);
 segments[0]=(struct scatterlist){0xfff00000,(u32)bytes};table.nents=1;
 assert(a50_scan_map(&d,&l,&a,&t)==0 && unmapped==2 && detached==2);
 segments[0]=(struct scatterlist){0,(u32)bytes};
 assert(a50_scan_map(&d,&l,&a,&t)==0 && unmapped==3 && detached==3);
 regs[IDMA_SRC_OFFSET/4]=0x12345678;
 a50_set_scanout(&d,0x100000,1,1088,2352);
 assert(regs[IDMA_SRC_SIZE/4]==0x09300440 && regs[IDMA_SRC_OFFSET/4]==0);
 assert(regs[IDMA_IMG_SIZE/4]==0x09240438 && regs[IDMA_IN_BASE_ADDR_Y/4]==0x100000);
 assert(d.scan_full_w==1088 && d.scan_full_h==2352);
 d.scan_buf=&buf;d.scan_att=&attachment;d.scan_sgt=&table;
 a50_show_bootfb_locked(&d);
 assert(regs[IDMA_SRC_SIZE/4]==0x09240438 && regs[IDMA_IMG_SIZE/4]==0x09240438);
 assert(regs[IDMA_IN_BASE_ADDR_Y/4]==0xca000000 && !d.scan_buf);
 assert(d.scan_full_w==1080 && d.scan_full_h==2340 && waited==1 && framed==1 && released==1);
 puts("PASS: padded/tight geometry, buffer/IOVA bounds, SG gaps/cleanup, register encoding and fallback restore");
 return 0;
}
'''
code='\n'.join(parts)
mutants={
    'old fixed pitch': code.replace('l->src.f_w < FB_W','l->src.f_w != FB_W'),
    'tight-size bound': code.replace('(u64)l->src.f_w * l->src.f_h * 4','(u64)FB_W * FB_H * 4'),
    'omit source geometry': code.replace('writel((full_h << 16) | full_w, d->idma + IDMA_SRC_SIZE);',''),
    'bad fallback pitch': code.replace('FMT_ARGB_8888, FB_W, FB_H','FMT_ARGB_8888, 1088, 2352'),
    'tight SG span': code.replace('a50_scan_range_ok(start, next, bytes)','a50_scan_range_ok(start, next, (u64)FB_W * FB_H * 4)'),
    '32-bit end unchecked': code.replace('bytes <= (u64)U32_MAX - start + 1','true'),
    'nonlinear DMA allowed': code.replace(' || !l->linear',''),
}
with tempfile.TemporaryDirectory(prefix='a50-stride-') as temp:
    p=Path(temp)
    for name,body in [('real source',code),*mutants.items()]:
        assert name=='real source' or body!=code,name
        (p/'test.c').write_text(head+constants+'\n'+body+tail)
        subprocess.run(['gcc','-std=gnu11','-O2','-Wall','-Wextra','-Werror',str(p/'test.c'),'-o',str(p/'test')],check=True)
        r=subprocess.run(['sh','-c','ulimit -c 0; exec "$1"','sh',str(p/'test')],capture_output=True,text=True)
        print(name+': '+('PASS' if r.returncode==0 else 'rejected'))
        if name=='real source' and r.returncode:print(r.stderr)
        assert (name=='real source')==(r.returncode==0),name
assert 'l->linear = !c->protection && !c->compression && !c->dpp_parm.rot;' in s
assert 'u->layer[0].src.f_w, u->layer[0].src.f_h' in s
print('RESULT: PASS (real functions and seven regression controls)')

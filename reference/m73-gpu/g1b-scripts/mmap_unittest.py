#!/usr/bin/env python3
"""Exercise the actual ported gap search with synthetic VMAs; no GPU access.

This checks address/guard/boundary behavior, not live mmap/MMU integration.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

kernel = Path(sys.argv[1])
source = (kernel / 'drivers/gpu/arm/midgard/thirdparty/mali_kbase_mmap.c').read_text()
start = source.index('static bool align_and_check(')
end = source.index('\n}\n', start) + 3
alignment = source[start:end]
start = source.index('/*\n * A50 6.18 port: since 6.1')
search = source[start:source.index('\n#else', start)]
head = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#define U32_MAX UINT32_MAX
#define BASE_MEM_MASK_4GB 0xffffffffUL
#define ALIGN(x, a) (((x) + (a) - 1) & ~((a) - 1))
#define WARN_ON(x) ((void)(x))
#define max(a, b) ((a) > (b) ? (a) : (b))
#define PAGE 4096UL
struct vm_unmapped_area_info {
    unsigned long length, align_mask, align_offset, low_limit, high_limit;
};
struct vm_area_struct { unsigned long vm_start, vm_end, guard; };
struct mm_struct { struct vm_area_struct vmas[8]; unsigned count; } mm;
struct task_struct { struct mm_struct *mm; } task = { &mm }, *current = &task;
static inline unsigned long vm_start_gap(struct vm_area_struct *vma) {
    return vma->vm_start > vma->guard ? vma->vm_start - vma->guard : 0;
}
static inline unsigned long vm_end_gap(struct vm_area_struct *vma) { return vma->vm_end; }
#define VMA_ITERATOR(i, mm, start) unsigned i
#define for_each_vma(i, vma) \
    for ((i) = 0; (i) < mm->count && ((vma) = &mm->vmas[i], 1); (i)++)
'''
tail = r'''
static void check(unsigned long got, unsigned long expected, const char *label) {
    if (got != expected) {
        fprintf(stderr, "%s: got %#lx expected %#lx\n", label, got, expected);
        exit(1);
    }
}
int main(void) {
    struct vm_unmapped_area_info info = { .length = PAGE, .high_limit = 16*PAGE,
                                         .low_limit = PAGE };
    check(kbase_unmapped_area_topdown(&info, false, false), 15*PAGE, "empty map");
    mm.vmas[0] = (struct vm_area_struct){4*PAGE, 6*PAGE, 0};
    mm.vmas[1] = (struct vm_area_struct){10*PAGE, 16*PAGE, 0}; mm.count = 2;
    check(kbase_unmapped_area_topdown(&info, false, false), 9*PAGE, "highest interior gap");
    info.high_limit = 9*PAGE;
    check(kbase_unmapped_area_topdown(&info, false, false), 8*PAGE, "high limit inside gap");
    info.high_limit = 16*PAGE;
    mm.vmas[1].guard = 2*PAGE;
    check(kbase_unmapped_area_topdown(&info, false, false), 7*PAGE, "stack guard");
    info.high_limit = 9*PAGE;
    check(kbase_unmapped_area_topdown(&info, false, false), 7*PAGE, "guard from VMA above limit");
    info.low_limit = 8*PAGE;
    check(kbase_unmapped_area_topdown(&info, false, false), -ENOMEM, "low limit");
    mm.count = 0; info.low_limit = PAGE; info.high_limit = 1UL<<32;
    check(kbase_unmapped_area_topdown(&info, true, false), (1UL<<32)-2*PAGE, "shader boundary");
    info.length = 2*PAGE; info.high_limit = (1UL<<32)+PAGE;
    check(kbase_unmapped_area_topdown(&info, false, true), (1UL<<32)-2*PAGE, "same 4GB chunk");
    info.length = ~0UL; info.align_mask = PAGE-1;
    check(kbase_unmapped_area_topdown(&info, false, false), -ENOMEM, "length overflow");
    info.length = PAGE; info.align_mask = (2UL<<20)-1; info.high_limit = 8UL<<20;
    check(kbase_unmapped_area_topdown(&info, false, false), 6UL<<20, "2MB alignment");
    puts("PASS: empty/interior gaps, stack guards, limits, shader/4GB rules, overflow, alignment");
    return 0;
}
'''

mutations = {
    'ignore stack guards': search.replace('vm_start_gap(vma)', 'vma->vm_start'),
    'keep lowest gap': search.replace('*best = gap_end;', 'if (*best == (unsigned long)-ENOMEM) *best = gap_end;'),
    'omit high limit': search.replace('if (gap_end > info->high_limit)', 'if (false)'),
}
with tempfile.TemporaryDirectory(prefix='a50-mmap-') as temporary:
    path = Path(temporary)
    for name, code in [('real allocator', search), *mutations.items()]:
        if name != 'real allocator' and code == search:
            raise SystemExit(f'Mutation not applied: {name}')
        (path / 'test.c').write_text(head + alignment + code + tail)
        subprocess.run(['gcc', '-std=gnu11', '-O2', '-Wall', '-Wextra',
                        '-Werror', str(path / 'test.c'), '-o', str(path / 'test')], check=True)
        result = subprocess.run([str(path / 'test')], text=True, capture_output=True)
        print(name + ': ' + (result.stdout.strip() or result.stderr.strip()))
        if (name == 'real allocator') != (result.returncode == 0):
            raise SystemExit('Unexpected test/mutation result')
print('RESULT: PASS (real source passes; all three regression controls fail)')

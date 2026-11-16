#!/usr/bin/env python3
"""Run the real soft-job cancellation dispatcher with a dying/empty process mm.

Checks cancellation dispatch, not the kernel fence implementation. The original
vendor dispatcher must reproduce the NULL walk; an early-return fix must fail.
"""
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile

kernel = Path(sys.argv[1])
relative = 'drivers/gpu/arm/midgard/mali_kbase_softjobs.c'
fix = Path(__file__).resolve().parents[2] / 'reference/m73-gpu/g2b-cancel.patch'


def extract(source):
    start = source.index('void kbase_cancel_soft_job(')
    return source[start:source.index('\nint kbase_prepare_soft_job(', start)]


fixed = extract((kernel / relative).read_text())
head = r'''
#include <stdio.h>
#include <stdlib.h>
#define CONFIG_SYNC_FILE 1
#define BASE_JD_REQ_SOFT_JOB_TYPE 255
#define BASE_JD_REQ_SOFT_FENCE_WAIT 1
#define BASE_JD_REQ_SOFT_EVENT_WAIT 2
#define KBASE_DEBUG_ASSERT(x) do { if (!(x)) abort(); } while (0)
#define printk(...) ((void)0)
typedef unsigned long pgd_t;
struct mm_struct { pgd_t *pgd; };
struct kbase_context { struct mm_struct *process_mm; int tgid; };
struct kbase_jd_atom { unsigned core_req; struct kbase_context *kctx; };
static unsigned fence_cancels, event_cancels;
static inline pgd_t *pgd_offset(struct mm_struct *mm, unsigned long addr) {
    (void)addr; return mm->pgd;
}
static inline int pgd_none(pgd_t pgd) { return pgd == 0; }
static inline int pgd_bad(pgd_t pgd) { return pgd == ~0UL; }
static inline void kbase_sync_fence_in_cancel_wait(struct kbase_jd_atom *a) {
    (void)a; fence_cancels++;
}
static inline void kbasep_soft_event_cancel_job(struct kbase_jd_atom *a) {
    (void)a; event_cancels++;
}
'''
tail = r'''
int main(void) {
    pgd_t empty = 0;
    struct mm_struct mm = { .pgd = &empty };
    struct kbase_context ctx = { .process_mm = NULL };
    struct kbase_jd_atom atom = { .core_req = BASE_JD_REQ_SOFT_FENCE_WAIT, .kctx = &ctx };
    kbase_cancel_soft_job(&atom);
    atom.core_req = BASE_JD_REQ_SOFT_EVENT_WAIT;
    kbase_cancel_soft_job(&atom);
    ctx.process_mm = &mm;
    kbase_cancel_soft_job(&atom);
    atom.core_req = BASE_JD_REQ_SOFT_FENCE_WAIT;
    kbase_cancel_soft_job(&atom);
    if (fence_cancels != 2 || event_cancels != 2) {
        fprintf(stderr, "lost cancellation: fences=%u events=%u\n", fence_cancels, event_cancels);
        return 1;
    }
    puts("PASS: fence/event cancellation with NULL mm and empty user page table");
    return 0;
}
'''
mutants = {
    'early return on NULL mm': fixed.replace('{', '{\n if (!katom->kctx->process_mm) return;', 1),
    'omit fence cancellation': fixed.replace('kbase_sync_fence_in_cancel_wait(katom);', '(void)katom;'),
}
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
with tempfile.TemporaryDirectory(prefix='a50-cancel-') as temporary:
    path = Path(temporary)
    # Revert only the published fix in a temporary copy; no historical Git
    # objects are needed when reproducing this from the exported source.
    baseline = path / 'original-softjobs.c'
    baseline.write_bytes((kernel / relative).read_bytes())
    subprocess.run(['patch', '--batch', '--fuzz=0', '--reverse', str(baseline), str(fix)],
                   check=True, capture_output=True, text=True)
    old = extract(baseline.read_text())
    for name, code in [('fixed real source', fixed), ('original vendor source', old), *mutants.items()]:
        if name in mutants and code == fixed:
            raise SystemExit('Mutation not applied: ' + name)
        (path / 'test.c').write_text(head + code + tail)
        subprocess.run(['gcc', '-std=gnu11', '-O2', '-Wall', '-Wextra',
                        str(path / 'test.c'), '-o', str(path / 'test')], check=True)
        result = subprocess.run([str(path / 'test')], capture_output=True, text=True)
        print(name + ': ' + (result.stdout.strip() or result.stderr.strip() or f'signal {-result.returncode}'))
        if name == 'original vendor source':
            assert result.returncode == -signal.SIGSEGV, 'Original NULL walk did not reproduce'
        elif (name == 'fixed real source') != (result.returncode == 0):
            raise SystemExit('Unexpected test/mutation result')
print('RESULT: PASS (original crash reproduced; both lost-cleanup regressions caught)')

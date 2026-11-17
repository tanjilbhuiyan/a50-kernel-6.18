#!/usr/bin/env python3
"""Build both userspace ABIs from the actual r26p0 ioctl declarations/constants."""
from pathlib import Path
import hashlib
import re
import subprocess
import sys

root=Path(__file__).resolve().parents[2]
kernel=Path(sys.argv[1]).resolve()
out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
headers=kernel/'drivers/gpu/arm/midgard'
jm=(headers/'jm/mali_base_jm_kernel.h').read_text()
priv=(headers/'mali_base_mem_priv.h').read_text()
base=(headers/'mali_base_kernel.h').read_text()
names=['BASE_MEM_PROT_CPU_RD','BASE_MEM_PROT_CPU_WR','BASE_MEM_PROT_GPU_RD',
       'BASE_MEM_PROT_GPU_WR','BASE_MEM_CACHED_CPU','BASE_MEM_SAME_VA','BASE_MEM_NEED_MMAP',
       'BASE_MEM_IMPORT_SHARED','BASEP_MEM_PERMANENT_KERNEL_MAPPING','BASE_MEM_MAP_TRACKING_HANDLE',
       'BASE_CONTEXT_SYSTEM_MONITOR_SUBMIT_DISABLED','BASE_SYNCSET_OP_MSYNC','BASE_SYNCSET_OP_CSYNC']
text='#include <stdint.h>\ntypedef uint64_t u64;\ntypedef uint64_t base_mem_alloc_flags;\ntypedef uint32_t base_context_create_flags;\n'
for name in names:
    match=re.search(r'^#define '+name+r'\b(?:[^\n]*\\\n)*[^\n]*',jm+'\n'+priv,re.M)
    assert match,name
    text+=match.group(0)+'\n'
for name in ['base_mem_import_type','base_mem_import_user_buffer']:
    kind='enum' if name=='base_mem_import_type' else 'struct'
    match=re.search(kind+' '+name+r'\s*\{.*?\};',base,re.S);assert match,name
    text+=match.group(0)+'\n'
(out/'memory_constants.h').write_text(text)
ndk=root/'src/ack-6.18/prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin'
for bits,compiler in [(64,'aarch64-linux-android30-clang'),(32,'armv7a-linux-androideabi30-clang')]:
    binary=out/f'kbase-memory{bits}'
    subprocess.run([str(ndk/compiler),'-std=gnu11','-static','-O2','-Wall','-Wextra','-Werror',
                    '-I',str(out),'-I',str(headers),'-I',str(kernel/'drivers/staging/android/uapi'),
                    str(root/'tools/m73/kbase_memory_probe.c'),'-o',str(binary)],check=True)
    print(hashlib.sha256(binary.read_bytes()).hexdigest(),binary)

#include <stdint.h>
typedef uint64_t u64;
typedef uint64_t base_mem_alloc_flags;
typedef uint32_t base_context_create_flags;
#define BASE_MEM_PROT_CPU_RD ((base_mem_alloc_flags)1 << 0)
#define BASE_MEM_PROT_CPU_WR ((base_mem_alloc_flags)1 << 1)
#define BASE_MEM_PROT_GPU_RD ((base_mem_alloc_flags)1 << 2)
#define BASE_MEM_PROT_GPU_WR ((base_mem_alloc_flags)1 << 3)
#define BASE_MEM_CACHED_CPU ((base_mem_alloc_flags)1 << 12)
#define BASE_MEM_SAME_VA ((base_mem_alloc_flags)1 << 13)
#define BASE_MEM_NEED_MMAP ((base_mem_alloc_flags)1 << 14)
#define BASE_MEM_IMPORT_SHARED ((base_mem_alloc_flags)1 << 18)
#define BASEP_MEM_PERMANENT_KERNEL_MAPPING ((base_mem_alloc_flags)1 << 5)
#define BASE_MEM_MAP_TRACKING_HANDLE           (3ull  << 12)
#define BASE_CONTEXT_SYSTEM_MONITOR_SUBMIT_DISABLED \
	((base_context_create_flags)1 << 1)
#define BASE_SYNCSET_OP_MSYNC	(1U << 0)
#define BASE_SYNCSET_OP_CSYNC	(1U << 1)
enum base_mem_import_type {
	BASE_MEM_IMPORT_TYPE_INVALID = 0,
	/**
	 * Import type with value 1 is deprecated.
	 */
	BASE_MEM_IMPORT_TYPE_UMM = 2,
	BASE_MEM_IMPORT_TYPE_USER_BUFFER = 3
};
struct base_mem_import_user_buffer {
	u64 ptr;
	u64 length;
};

/* SPDX-License-Identifier: Apache-2.0 */
/* G2e: replay the two rejected gralloc requests and check zeroing/protection. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <linux/dma-buf.h>
#include "ion.h"

#define CHECK(x) do { if (!(x)) { \
 fprintf(stderr, "FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); \
 exit(1); } } while (0)
_Static_assert(sizeof(struct ion_allocation_data) == 24, "ION allocation ABI");

static void positive(int ion, uint64_t len, uint32_t flags)
{
 struct ion_allocation_data a = { .len = len, .heap_id_mask = 1, .flags = flags };
 struct dma_buf_sync sync = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_RW };
 CHECK(ioctl(ion, ION_IOC_ALLOC, &a) == 0);
 CHECK(fcntl(a.fd, F_GETFD) & FD_CLOEXEC);
 unsigned char *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, a.fd, 0);
 CHECK(p != MAP_FAILED);
 CHECK(ioctl(a.fd, DMA_BUF_IOCTL_SYNC, &sync) == 0);
 for (size_t i = 0; i < len; i++) CHECK(p[i] == 0);
 p[0] = 0xa5; p[len - 1] = 0x5a;
 sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_RW;
 CHECK(ioctl(a.fd, DMA_BUF_IOCTL_SYNC, &sync) == 0);
 CHECK(munmap(p, len) == 0);
 CHECK(close(a.fd) == 0);
 printf("PASS alloc/zero/map/sync/close len=%llu flags=0x%x\n",
        (unsigned long long)len, flags);
}

static void negative(int ion, uint32_t mask, uint32_t flags, int error)
{
 struct ion_allocation_data a = { .len = 4096, .heap_id_mask = mask, .flags = flags };
 errno = 0;
 CHECK(ioctl(ion, ION_IOC_ALLOC, &a) == -1 && errno == error);
 printf("PASS expected rejection heap=0x%x flags=0x%x errno=%d\n", mask, flags, error);
}

int main(void)
{
 int ion = open("/dev/ion", O_RDWR | O_CLOEXEC);
 CHECK(ion >= 0);
 positive(ion, 17050368, 0x48);
 positive(ion, 17152, 0x43);
 positive(ion, 4096, 0x0b);
 negative(ion, 1, ION_FLAG_PROTECTED | 0x48, EOPNOTSUPP);
 negative(ion, 1, 0x80000000, EOPNOTSUPP);
 negative(ion, 2, 0x48, ENODEV);
 CHECK(close(ion) == 0);
 puts("RESULT: PASS (expected rejection logs above are intentional)");
 return 0;
}

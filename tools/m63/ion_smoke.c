/* SPDX-License-Identifier: Apache-2.0 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#include <linux/dma-buf.h>
#include "ion.h"
#include "replay.h"

#define TRACK _IO('b', 8)
#define UNTRACK _IO('b', 9)
#define CHECK(expression) do { \
	if (!(expression)) { \
		fprintf(stderr, "line %d: %s failed (errno %d)\n", __LINE__, #expression, errno); \
		exit(1); \
	} \
} while (0)

_Static_assert(sizeof(struct ion_allocation_data) == 24, "allocation ABI");
_Static_assert(sizeof(struct ion_heap_query) == 24, "query ABI");
_Static_assert(sizeof(struct ion_heap_data) == 52, "heap ABI");
_Static_assert(ION_IOC_ALLOC == 0xc0184900, "allocation ioctl");
_Static_assert(ION_IOC_HEAP_QUERY == 0xc0184908, "query ioctl");

static int allocate(int ion, uint64_t length, uint32_t mask, uint32_t flags)
{
	struct ion_allocation_data request = {
		.len = length, .heap_id_mask = mask, .flags = flags,
	};
	CHECK(ioctl(ion, ION_IOC_ALLOC, &request) == 0);
	CHECK(fcntl(request.fd, F_GETFD) & FD_CLOEXEC);
	return request.fd;
}

static int fd_count(void)
{
	DIR *directory = opendir("/proc/self/fd");
	CHECK(directory != NULL);
	int count = 0;
	while (readdir(directory))
		count++;
	CHECK(closedir(directory) == 0);
	return count;
}

static void check_child(pid_t pid)
{
	int status;
	CHECK(waitpid(pid, &status, 0) == pid);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

static void check_fresh_tracking(int fd)
{
	errno = 0;
	CHECK(ioctl(fd, UNTRACK) == -1 && errno == ENOENT);
	CHECK(ioctl(fd, TRACK) == 0);
	CHECK(ioctl(fd, UNTRACK) == 0);
}

static void check_lifetime(int ion)
{
	int fd = allocate(ion, 4096, 1, ION_FLAG_CACHED);
	CHECK(ioctl(fd, TRACK) == 0);
	CHECK(ioctl(fd, TRACK) == 0);
	int duplicate = dup(fd);
	CHECK(duplicate >= 0);
	CHECK(close(fd) == 0);
	CHECK(ioctl(duplicate, UNTRACK) == 0);
	CHECK(ioctl(duplicate, UNTRACK) == 0);
	check_fresh_tracking(duplicate);
	CHECK(ioctl(duplicate, TRACK) == 0);
	pid_t child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		check_fresh_tracking(duplicate);
		_exit(0);
	}
	check_child(child);
	CHECK(ioctl(duplicate, UNTRACK) == 0);
	CHECK(fcntl(duplicate, F_SETFD, 0) == 0);
	child = fork();
	CHECK(child >= 0);
	if (child == 0) {
		char argument[32];
		snprintf(argument, sizeof(argument), "%d", duplicate);
		execl("/proc/self/exe", "ion-smoke", "--inherited", argument, (char *)NULL);
		_exit(1);
	}
	check_child(child);
	CHECK(close(duplicate) == 0);
	puts("PASS: tracking balance, dup/close, fork and exec lifetime");
}

static void check_boundaries(int ion)
{
	struct ion_heap_data heap = { 0 };
	struct ion_heap_query query = { .reserved0 = 1 };
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == -1 && errno == EINVAL);
	query = (struct ion_heap_query){ .heaps = (uintptr_t)&heap };
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == -1 && errno == EINVAL);
	query = (struct ion_heap_query){ .cnt = 1, .heaps = 1 };
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == -1 && errno == EFAULT);
	query = (struct ion_heap_query){ .cnt = UINT32_MAX, .heaps = (uintptr_t)&heap };
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == 0 && query.cnt == 1);
	struct ion_allocation_data request = { .heap_id_mask = 1 };
	CHECK(ioctl(ion, ION_IOC_ALLOC, &request) == -1 && errno == EINVAL);
	request.len = UINT64_MAX;
	CHECK(ioctl(ion, ION_IOC_ALLOC, &request) == -1 && errno == EOVERFLOW);
	request.len = 4096;
	request.heap_id_mask = 2;
	CHECK(ioctl(ion, ION_IOC_ALLOC, &request) == -1 && errno == ENODEV);
	request.heap_id_mask = 1;
	request.flags = ION_FLAG_PROTECTED;
	CHECK(ioctl(ion, ION_IOC_ALLOC, &request) == -1 && errno == EOPNOTSUPP);

	int before = fd_count();
	long page_size = sysconf(_SC_PAGESIZE);
	CHECK(page_size > 0);
	void *page = mmap(NULL, page_size, PROT_READ | PROT_WRITE,
			 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK(page != MAP_FAILED);
	*(struct ion_allocation_data *)page = (struct ion_allocation_data){
		.len = 4096, .heap_id_mask = 1, .flags = ION_FLAG_CACHED,
	};
	CHECK(mprotect(page, page_size, PROT_READ) == 0);
	for (int attempt = 0; attempt < 8; attempt++)
		CHECK(ioctl(ion, ION_IOC_ALLOC, page) == -1 && errno == EFAULT);
	CHECK(munmap(page, page_size) == 0);
	CHECK(fd_count() == before);
	puts("PASS: query validation, allocation bounds and copyout fd cleanup");
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "--inherited") == 0) {
		check_fresh_tracking(atoi(argv[2]));
		return 0;
	}
	int ion = open("/dev/ion", O_RDWR | O_CLOEXEC);
	CHECK(ion >= 0);
	struct ion_heap_query query = { 0 };
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == 0 && query.cnt == 1);
	struct ion_heap_data heap = { 0 };
	query.heaps = (uintptr_t)&heap;
	CHECK(ioctl(ion, ION_IOC_HEAP_QUERY, &query) == 0);
	CHECK(heap.heap_id == 0 && heap.type == ION_HEAP_TYPE_SYSTEM);
	CHECK(strcmp(heap.name, "ion_system_heap") == 0 && heap.heap_flags == 0);
	printf("heap query: %s id=%u flags=%u\n", heap.name, heap.heap_id, heap.heap_flags);
	int before = fd_count();
	for (size_t index = 0; index < sizeof(replay) / sizeof(replay[0]); index++) {
		const struct captured_allocation *sample = &replay[index];
		int fd = allocate(ion, sample->length, sample->mask, sample->flags);
		struct dma_buf_sync sync = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_RW };
		CHECK(ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync) == 0);
		unsigned char *mapping = mmap(NULL, sample->length, PROT_READ | PROT_WRITE,
					     MAP_SHARED, fd, 0);
		CHECK(mapping != MAP_FAILED);
		for (size_t offset = 0; offset < sample->length; offset += 4096)
			CHECK(mapping[offset] == 0);
		CHECK(mapping[sample->length - 1] == 0);
		mapping[0] = 0xa5;
		mapping[sample->length - 1] = 0x5a;
		const unsigned char *alias = mmap(NULL, sample->length, PROT_READ, MAP_SHARED, fd, 0);
		CHECK(alias != MAP_FAILED);
		CHECK(alias[0] == 0xa5 && alias[sample->length - 1] == 0x5a);
		CHECK(ioctl(fd, TRACK) == 0 && ioctl(fd, UNTRACK) == 0);
		sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_RW;
		CHECK(ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync) == 0);
		CHECK(munmap((void *)alias, sample->length) == 0);
		CHECK(munmap(mapping, sample->length) == 0);
		CHECK(close(fd) == 0);
		printf("replay[%zu] len=%llu mask=%u flags=%u PASS\n", index,
		       (unsigned long long)sample->length, sample->mask, sample->flags);
	}
	CHECK(fd_count() == before);
	check_boundaries(ion);
	check_lifetime(ion);
	CHECK(close(ion) == 0);
	puts("PASS: captured ION allocations and native DMA-BUF behavior");
	return 0;
}

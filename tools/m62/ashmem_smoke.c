/* SPDX-License-Identifier: Apache-2.0 */
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ashmem.h"

int main(void)
{
	const char path[] = "/dev/ashmem";
	const char marker[] = "a50 ashmem shared mapping";
	long page_size = sysconf(_SC_PAGESIZE);
	if (page_size < (long)sizeof(marker)) {
		fprintf(stderr, "Unexpected page size %ld\n", page_size);
		return 1;
	}

	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror(path);
		return 1;
	}
	struct stat device;
	if (fstat(fd, &device) < 0) {
		perror("fstat /dev/ashmem");
		return 1;
	}
	if (!S_ISCHR(device.st_mode)) {
		fprintf(stderr, "%s is not a character device\n", path);
		return 1;
	}
	if (ioctl(fd, ASHMEM_SET_SIZE, (unsigned long)page_size) < 0) {
		perror("ASHMEM_SET_SIZE");
		return 1;
	}
	int size = ioctl(fd, ASHMEM_GET_SIZE);
	if (size != page_size) {
		fprintf(stderr, "ASHMEM_GET_SIZE returned %d, expected %ld\n", size, page_size);
		return 1;
	}
	printf("ASHMEM_SET_SIZE / ASHMEM_GET_SIZE: %d bytes\n", size);

	char *writer = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (writer == MAP_FAILED) {
		perror("mmap writer");
		return 1;
	}
	const char *reader = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
	if (reader == MAP_FAILED) {
		perror("mmap reader");
		return 1;
	}
	memcpy(writer, marker, sizeof(marker));
	if (memcmp(reader, marker, sizeof(marker)) != 0) {
		fprintf(stderr, "Second shared mapping did not see the write\n");
		return 1;
	}
	if (munmap(writer, size) < 0 || munmap((void *)reader, size) < 0 || close(fd) < 0) {
		perror("ashmem cleanup");
		return 1;
	}
	puts("PASS: ashmem size ioctls and shared mmap");
	return 0;
}

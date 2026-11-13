/* SPDX-License-Identifier: Apache-2.0 */
/* Probe device-cgroup access with an absent SCSI minor, without issuing I/O. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

int main(void)
{
	const char *path = "/dev/a50-block-policy-probe";
	struct stat st;
	if (stat(path, &st) || !S_ISBLK(st.st_mode) ||
	    major(st.st_rdev) != 8 || minor(st.st_rdev) != 255) {
		fputs("FAIL: synthetic probe node absent or incorrect\n", stderr);
		return 1;
	}
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd >= 0) {
		close(fd);
		fputs("FAIL: unused SCSI minor unexpectedly exists\n", stderr);
		return 1;
	}
	if (errno != ENXIO && errno != ENODEV) {
		perror("FAIL: read-only probe did not reach absent device");
		return 1;
	}
	fd = open(path, O_WRONLY | O_CLOEXEC);
	if (fd >= 0) {
		close(fd);
		fputs("FAIL: raw block write open allowed\n", stderr);
		return 1;
	}
	if (errno != EPERM) {
		perror("FAIL: raw block write open not denied by device policy");
		return 1;
	}
	if (mknod("/dev/a50-forbidden-block", S_IFBLK | 0600, makedev(8, 255)) == 0) {
		unlink("/dev/a50-forbidden-block");
		fputs("FAIL: raw block mknod allowed\n", stderr);
		return 1;
	}
	if (errno != EPERM) {
		perror("FAIL: block mknod not denied by device policy");
		return 1;
	}
	puts("PASS: raw block write opens and mknod denied; no block I/O issued");
	return 0;
}

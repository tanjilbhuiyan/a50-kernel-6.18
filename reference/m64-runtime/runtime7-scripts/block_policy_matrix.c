/* SPDX-License-Identifier: Apache-2.0 */
/* Check every open mode against an absent SCSI minor; never issue block I/O. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

int main(void)
{
	struct stat st;
	const char *node = "/dev/a50-block-policy-probe";
	if (stat(node, &st) || !S_ISBLK(st.st_mode) ||
	    major(st.st_rdev) != 8 || minor(st.st_rdev) != 255)
		return 2;
	int bad = 0, fd = open("/dev/null", O_RDWR | O_CLOEXEC);
	printf("character /dev/null O_RDWR: %s\n", fd >= 0 ? "PASS" : "FAIL");
	if (fd >= 0) close(fd); else bad++;
	const int modes[] = {O_RDONLY, O_WRONLY, O_RDWR};
	const char *names[] = {"O_RDONLY", "O_WRONLY", "O_RDWR"};
	for (unsigned int i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
		errno = 0;
		fd = open(node, modes[i] | O_CLOEXEC);
		int error = errno;
		printf("block %s: fd=%d errno=%d %s\n", names[i], fd, error,
		       fd < 0 && error == EPERM ? "PASS" : "FAIL");
		if (fd >= 0) close(fd);
		if (fd >= 0 || error != EPERM) bad++;
	}
	int result = mknod("/dev/a50-forbidden-block", S_IFBLK | 0600, makedev(8, 255));
	int error = errno;
	printf("block mknod: result=%d errno=%d %s\n", result, error,
	       result < 0 && error == EPERM ? "PASS" : "FAIL");
	if (!result) unlink("/dev/a50-forbidden-block");
	if (result >= 0 || error != EPERM) bad++;
	printf("%s: all block open modes and mknod denied; no block I/O issued\n", bad ? "FAIL" : "PASS");
	return bad != 0;
}

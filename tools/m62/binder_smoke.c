/* SPDX-License-Identifier: Apache-2.0 */
#include <fcntl.h>
#include <linux/android/binder.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

_Static_assert(BINDER_CURRENT_PROTOCOL_VERSION == 8, "Use the AArch64 Binder ABI");

int main(int argc, char **argv)
{
	struct stat devices[3];

	if (argc != 4) {
		fprintf(stderr, "Usage: %s BINDER HWBINDER VNDBINDER\n", argv[0]);
		return 2;
	}

	for (int i = 0; i < 3; i++) {
		const char *path = argv[i + 1];
		struct binder_version version = { 0 };
		int fd = open(path, O_RDWR | O_CLOEXEC);

		if (fd < 0) {
			perror(path);
			return 1;
		}
		if (fstat(fd, &devices[i]) < 0 || ioctl(fd, BINDER_VERSION, &version) < 0) {
			perror(path);
			close(fd);
			return 1;
		}
		close(fd);
		if (!S_ISCHR(devices[i].st_mode) || version.protocol_version != 8) {
			fprintf(stderr, "%s: unexpected node type or protocol %d\n",
				path, version.protocol_version);
			return 1;
		}
		for (int previous = 0; previous < i; previous++) {
			if (devices[previous].st_rdev == devices[i].st_rdev) {
				fprintf(stderr, "%s: shares a device number with %s\n",
					path, argv[previous + 1]);
				return 1;
			}
		}
		printf("%s: BINDER_VERSION=%d\n", path, version.protocol_version);
	}
	return 0;
}

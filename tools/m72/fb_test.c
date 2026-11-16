// SPDX-License-Identifier: Apache-2.0
/*
 * M7.2 D2a: userspace check of the a50-decon fbdev driver.
 * 1. FBIOGET_FSCREENINFO/VSCREENINFO on the given fb device.
 * 2. mmap it and draw a pattern: 8 vertical colour bars over a top-to-bottom
 *    brightness ramp (distinct from D1's horizontal bands), then FBIOPAN_DISPLAY.
 * 3. S3CFB_SET_VSYNC_INT 1, count POLLPRI notifications of the sysfs vsync
 *    attribute for one second (expect about 60), S3CFB_SET_VSYNC_INT 0.
 * 4. S3CFB_POWER_MODE 2 and FBIOBLANK 0 must return 0 (accepted no-ops).
 * Usage: fb_test /dev/fb0 /sys/devices/platform/148b0000.decon_f/vsync
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define S3CFB_SET_VSYNC_INT _IOW('F', 206, uint32_t)
#define S3CFB_POWER_MODE _IOW('F', 223, uint32_t)

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	static const uint32_t bar[8] = { 0xffffff, 0xffff00, 0x00ffff, 0x00ff00,
					 0xff00ff, 0xff0000, 0x0000ff, 0x000000 };
	struct fb_fix_screeninfo fix;
	struct fb_var_screeninfo var;
	uint32_t on = 1, off = 0, mode = 2, *fb;
	char buf[64];
	int fd, vfd, n = 0, fails = 0;
	unsigned int x, y;
	double t0;

	if (argc != 3) {
		fprintf(stderr, "usage: %s FBDEV VSYNC_ATTR\n", argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	if (fd < 0 || ioctl(fd, FBIOGET_FSCREENINFO, &fix) || ioctl(fd, FBIOGET_VSCREENINFO, &var)) {
		perror("fb open/info");
		return 1;
	}
	printf("id=%s smem=0x%lx len=%u line=%u %ux%u bpp=%u r%u g%u b%u a%u\n", fix.id,
	       fix.smem_start, fix.smem_len, fix.line_length, var.xres, var.yres,
	       var.bits_per_pixel, var.red.offset, var.green.offset, var.blue.offset,
	       var.transp.offset);
	fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	for (y = 0; y < var.yres; y++) {
		uint32_t level = 64 + 191 * y / var.yres;

		for (x = 0; x < var.xres; x++) {
			uint32_t c = bar[x * 8 / var.xres];
			uint32_t r = ((c >> 16) & 0xff) * level / 255;
			uint32_t g = ((c >> 8) & 0xff) * level / 255;
			uint32_t b = (c & 0xff) * level / 255;

			fb[y * (fix.line_length / 4) + x] = 0xff000000 | r << 16 | g << 8 | b;
		}
	}
	var.xoffset = var.yoffset = 0;
	printf("FBIOPAN_DISPLAY: %s\n", ioctl(fd, FBIOPAN_DISPLAY, &var) ? strerror(errno) : "ok");

	vfd = open(argv[2], O_RDONLY);
	if (vfd < 0) {
		perror("vsync attr");
		fails++;
	} else if (ioctl(fd, S3CFB_SET_VSYNC_INT, &on)) {
		perror("S3CFB_SET_VSYNC_INT 1");
		fails++;
	} else {
		struct pollfd p = { .fd = vfd, .events = POLLPRI | POLLERR };

		pread(vfd, buf, sizeof(buf) - 1, 0);
		t0 = now();
		while (now() - t0 < 1.0) {
			if (poll(&p, 1, 200) > 0) {
				n++;
				pread(vfd, buf, sizeof(buf) - 1, 0);
			}
		}
		ioctl(fd, S3CFB_SET_VSYNC_INT, &off);
		buf[strcspn(buf, "\n")] = 0;
		printf("vsync notifications in 1 s: %d (last timestamp %s ns)\n", n, buf);
		if (n < 30)
			fails++;
	}
	if (ioctl(fd, S3CFB_POWER_MODE, &mode)) {
		perror("S3CFB_POWER_MODE");
		fails++;
	}
	if (ioctl(fd, FBIOBLANK, 0)) {
		perror("FBIOBLANK");
		fails++;
	}
	printf("RESULT: %s\n", fails ? "FAIL" : "PASS");
	return fails ? 1 : 0;
}

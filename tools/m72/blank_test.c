// SPDX-License-Identifier: Apache-2.0
/*
 * M7.2 D4a: blank/unblank check of the a50-decon fbdev driver.
 * Draws 8 vertical colour bars through the fb device and pans, then cycles the panel:
 *   FBIOBLANK POWERDOWN -> 3 s -> FBIOBLANK UNBLANK -> 3 s -> S3CFB_POWER_MODE OFF -> 3 s -> POWER_MODE NORMAL,
 * counting vsync (TE) notifications for one second in each state. TE should stop while the
 * panel sleeps and return after unblank. Expected screen: bars, black, bars, black, bars.
 * Usage: blank_test /dev/fb0 /sys/devices/platform/148b0000.decon_f/vsync
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

static int count_vsync(int vfd)
{
	struct pollfd p = { .fd = vfd, .events = POLLPRI | POLLERR };
	char buf[64];
	double t0;
	int n = 0;

	pread(vfd, buf, sizeof(buf), 0);
	t0 = now();
	while (now() - t0 < 1.0)
		if (poll(&p, 1, 200) > 0) {
			n++;
			pread(vfd, buf, sizeof(buf), 0);
		}
	return n;
}

static int step(int fd, int vfd, const char *what, unsigned long cmd, uintptr_t arg, int expect_te)
{
	double t0 = now();
	int ret = ioctl(fd, cmd, arg), n;

	printf("%-22s ret=%d (%.0f ms)", what, ret, (now() - t0) * 1e3);
	n = count_vsync(vfd);
	printf(", vsync in 1 s: %d\n", n);
	fflush(stdout);
	sleep(2);
	if (ret)
		return 1;
	return expect_te ? n < 30 : n > 5;
}

int main(int argc, char **argv)
{
	static const uint32_t bar[8] = { 0xffffff, 0xffff00, 0x00ffff, 0x00ff00,
					 0xff00ff, 0xff0000, 0x0000ff, 0x000000 };
	struct fb_fix_screeninfo fix;
	struct fb_var_screeninfo var;
	uint32_t on = 1, off = 0, normal = 2, *fb;
	unsigned int x, y;
	int fd, vfd, fails = 0;

	if (argc != 3) {
		fprintf(stderr, "usage: %s FBDEV VSYNC_ATTR\n", argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	vfd = open(argv[2], O_RDONLY);
	if (fd < 0 || vfd < 0 || ioctl(fd, FBIOGET_FSCREENINFO, &fix) || ioctl(fd, FBIOGET_VSCREENINFO, &var)) {
		perror("open/info");
		return 1;
	}
	fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	for (y = 0; y < var.yres; y++)
		for (x = 0; x < var.xres; x++)
			fb[y * (fix.line_length / 4) + x] = 0xff000000 | bar[x * 8 / var.xres];
	var.xoffset = var.yoffset = 0;
	if (ioctl(fd, FBIOPAN_DISPLAY, &var) || ioctl(fd, S3CFB_SET_VSYNC_INT, &on)) {
		perror("pan/vsync");
		return 1;
	}
	printf("%-22s vsync in 1 s: %d\n", "bars shown", count_vsync(vfd));
	sleep(2);
	fails += step(fd, vfd, "FBIOBLANK POWERDOWN", FBIOBLANK, FB_BLANK_POWERDOWN, 0);
	fails += step(fd, vfd, "FBIOBLANK UNBLANK", FBIOBLANK, FB_BLANK_UNBLANK, 1);
	fails += step(fd, vfd, "POWER_MODE OFF", S3CFB_POWER_MODE, (uintptr_t)&off, 0);
	fails += step(fd, vfd, "POWER_MODE NORMAL", S3CFB_POWER_MODE, (uintptr_t)&normal, 1);
	ioctl(fd, S3CFB_SET_VSYNC_INT, &off);
	printf("RESULT: %s\n", fails ? "FAIL" : "PASS");
	return fails ? 1 : 0;
}

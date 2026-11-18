/*
 * M8.1 T2: one read-only I2C transaction per call: a single I2C_RDWR read message of N bytes from ADDR on /dev/i2c-BUS.
 * Never writes (no write message, no SMBus quick/write, no register-pointer write). Prints the bytes or the errno.
 * Usage: i2c_read BUS ADDR N   (ADDR 0x03..0x77, N 1..4)
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	char dev[32];
	unsigned char buf[4] = { 0 };
	struct i2c_msg msg;
	struct i2c_rdwr_ioctl_data x = { &msg, 1 };
	struct timespec a, b;
	long bus, addr, n;
	int fd, r, e, i;

	if (argc != 4)
		return 2;
	bus = strtol(argv[1], NULL, 0); addr = strtol(argv[2], NULL, 0); n = strtol(argv[3], NULL, 0);
	if (bus < 0 || bus > 15 || addr < 0x03 || addr > 0x77 || n < 1 || n > 4)
		return 2;
	snprintf(dev, sizeof(dev), "/dev/i2c-%ld", bus);
	fd = open(dev, O_RDWR);
	if (fd < 0) {
		printf("open %s: %s\n", dev, strerror(errno));
		return 1;
	}
	msg.addr = addr; msg.flags = I2C_M_RD; msg.len = n; msg.buf = buf;
	clock_gettime(CLOCK_MONOTONIC, &a);
	r = ioctl(fd, I2C_RDWR, &x);
	e = errno;
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("bus %ld addr 0x%02lx read %ld: ", bus, addr, n);
	if (r < 0)
		printf("rc=%d errno=%d (%s)", r, e, strerror(e));
	else
		for (printf("rc=%d data", r), i = 0; i < n; i++)
			printf(" %02x", buf[i]);
	printf(" in %.3f ms\n", (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6);
	close(fd);
	return r < 0 ? 1 : 0;
}

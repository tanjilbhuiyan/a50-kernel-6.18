/*
 * M8.2: passive capture of a touchscreen's input events. Finds /dev/input/eventN whose name contains NAME, reads
 * events for SECONDS without EVIOCGRAB (the compositor keeps receiving them), prints the device's ABS ranges, the
 * first 60 events and a summary (contacts, X/Y min/max, event counts). Never writes to the device.
 * Usage: evcap NAME SECONDS
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

int main(int argc, char **argv)
{
	char path[64], name[256];
	int fd = -1, i, secs, printed = 0, contacts = 0, xs = 0, ys = 0, syns = 0, other = 0;
	int minx = 1 << 30, maxx = -1, miny = 1 << 30, maxy = -1;
	struct input_event ev;
	double end;

	if (argc != 3)
		return 2;
	secs = atoi(argv[2]);
	if (secs < 1 || secs > 300)
		return 2;
	for (i = 0; i < 32 && fd < 0; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		int f = open(path, O_RDONLY | O_NONBLOCK);
		if (f < 0)
			continue;
		name[0] = 0;
		ioctl(f, EVIOCGNAME(sizeof(name)), name);
		if (strstr(name, argv[1])) {
			fd = f;
			printf("device %s name \"%s\"\n", path, name);
		} else
			close(f);
	}
	if (fd < 0) {
		printf("no input device matching \"%s\"\n", argv[1]);
		return 1;
	}
	{
		int codes[] = { ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_SLOT, ABS_MT_PRESSURE, ABS_MT_TOUCH_MAJOR };
		const char *n[] = { "MT_X", "MT_Y", "MT_SLOT", "MT_PRESSURE", "MT_TOUCH_MAJOR" };
		for (i = 0; i < 5; i++) {
			struct input_absinfo a;
			if (ioctl(fd, EVIOCGABS(codes[i]), &a) == 0)
				printf("abs %s min %d max %d res %d\n", n[i], a.minimum, a.maximum, a.resolution);
		}
	}
	end = now() + secs;
	printf("capturing %d s (no grab)\n", secs);
	fflush(stdout);
	while (now() < end) {
		struct pollfd p = { fd, POLLIN, 0 };
		int r = poll(&p, 1, 250);
		if (r <= 0)
			continue;
		while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
			if (printed < 60) {
				printf("%ld.%06ld type %u code %u value %d\n", (long)ev.input_event_sec, (long)ev.input_event_usec,
				       ev.type, ev.code, ev.value);
				printed++;
			}
			if (ev.type == EV_SYN) syns++;
			else if (ev.type == EV_ABS && ev.code == ABS_MT_TRACKING_ID && ev.value >= 0) contacts++;
			else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_X) {
				xs++; if (ev.value < minx) minx = ev.value; if (ev.value > maxx) maxx = ev.value;
			} else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y) {
				ys++; if (ev.value < miny) miny = ev.value; if (ev.value > maxy) maxy = ev.value;
			} else other++;
		}
	}
	printf("summary contacts=%d x_events=%d y_events=%d syn=%d other=%d x_range=%d..%d y_range=%d..%d\n",
	       contacts, xs, ys, syns, other, xs ? minx : -1, maxx, ys ? miny : -1, maxy);
	close(fd);
	return 0;
}

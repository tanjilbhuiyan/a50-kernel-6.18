// SPDX-License-Identifier: Apache-2.0
/*
 * M7.2 D2b: userspace check of S3CFB_WIN_CONFIG on the a50-decon fbdev driver.
 * 1. Allocate a full-screen buffer from /dev/ion (heap 0, the M6.3 ABI), draw a pattern in
 *    Android byte order R,G,B,A (DECON format ABGR_8888), submit it as one BUFFER window,
 *    and wait for the retire fence. Expect retire_fence >= 0, rel_fence >= 0, signalled < 500 ms.
 *    Pattern: top half a horizontal gradient magenta -> cyan, bottom half a black/white
 *    checkerboard of 135-pixel squares.
 * 2. Submit a configuration without windows: expect retire_fence == -1.
 * 3. Submit the same buffer with an unsignalled sw_sync acquire fence: the retire fence must stay
 *    unsignalled for 300 ms, then signal after the acquire fence is signalled (needs debugfs).
 * Usage: winconfig_test /dev/fb0 [/sys/kernel/debug/sync/sw_sync]
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define W 1080
#define H 2340

struct win_rect { int32_t x, y; uint32_t w, h; };
struct frame { int32_t x, y; uint32_t w, h, f_w, f_h; };
struct dpp_params { uint64_t addr[3]; uint32_t rot, eq_mode, comp_src, hdr_std, min_lum, max_lum; };
struct win_config {
	uint32_t state;
	union {
		uint32_t color;
		struct {
			int32_t fd_idma[3], acq_fence, rel_fence, plane_alpha;
			uint32_t blending, idma_type, format;
			struct dpp_params dpp;
			struct win_rect block, transparent, opaque;
			struct frame src;
		};
	};
	struct frame dst;
	_Bool protection, compression;
};
struct win_config_data {
	int32_t retire_fence, fd_odma;
	struct win_config config[5];
	struct { int32_t remained_frames; uint32_t reserved[7]; } extra;
};
_Static_assert(sizeof(struct win_config_data) == 1040, "S3CFB_WIN_CONFIG size");
#define S3CFB_WIN_CONFIG _IOW('F', 209, struct win_config_data)
_Static_assert(S3CFB_WIN_CONFIG == 0x441046d1, "captured ioctl number");

struct ion_allocation_data { uint64_t len; uint32_t heap_id_mask, flags, fd, unused; };
#define ION_IOC_ALLOC _IOWR('I', 0, struct ion_allocation_data)

struct sw_sync_create_fence_data { uint32_t value; char name[32]; int32_t fence; };
#define SW_SYNC_IOC_CREATE_FENCE _IOWR('W', 0, struct sw_sync_create_fence_data)
#define SW_SYNC_IOC_INC _IOW('W', 1, uint32_t)

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* 1 if signalled within ms, 0 if not */
static int wait_fence(int fd, int ms)
{
	struct pollfd p = { .fd = fd, .events = POLLIN };

	return poll(&p, 1, ms) > 0;
}

static void fill(struct win_config_data *wd, int buf, int acq)
{
	struct win_config *c = &wd->config[0];

	memset(wd, 0, sizeof(*wd));
	wd->retire_fence = -1;
	wd->fd_odma = -1;
	c->state = 2;			/* BUFFER */
	c->fd_idma[0] = buf;
	c->fd_idma[1] = c->fd_idma[2] = -1;
	c->acq_fence = acq;
	c->rel_fence = -1;
	c->plane_alpha = 255;
	c->format = 1;			/* ABGR_8888: bytes R,G,B,A */
	c->src = (struct frame){ 0, 0, W, H, W, H };
	c->dst = (struct frame){ 0, 0, W, H, W, H };
}

int main(int argc, char **argv)
{
	struct ion_allocation_data a = { .len = W * H * 4, .heap_id_mask = 1, .flags = 0 };
	struct win_config_data wd;
	uint8_t *px;
	int fb, ion, fails = 0;
	unsigned int x, y;
	double t0;

	if (argc < 2) {
		fprintf(stderr, "usage: %s FBDEV [SW_SYNC]\n", argv[0]);
		return 2;
	}
	fb = open(argv[1], O_RDWR);
	ion = open("/dev/ion", O_RDONLY);
	if (fb < 0 || ion < 0 || ioctl(ion, ION_IOC_ALLOC, &a)) {
		perror("open fb/ion or ION_IOC_ALLOC");
		return 1;
	}
	px = mmap(NULL, a.len, PROT_READ | PROT_WRITE, MAP_SHARED, a.fd, 0);
	if (px == MAP_FAILED) {
		perror("mmap ion buffer");
		return 1;
	}
	for (y = 0; y < H; y++)
		for (x = 0; x < W; x++) {
			uint8_t *p = px + 4 * ((size_t)y * W + x);

			if (y < H / 2) {	/* magenta -> cyan */
				p[0] = 255 - 255 * x / (W - 1);
				p[1] = 255 * x / (W - 1);
				p[2] = 255;
			} else {		/* checkerboard */
				uint8_t v = ((x / 135) + (y / 135)) & 1 ? 255 : 0;

				p[0] = p[1] = p[2] = v;
			}
			p[3] = 255;
		}

	/* 1: one BUFFER window */
	fill(&wd, a.fd, -1);
	if (ioctl(fb, S3CFB_WIN_CONFIG, &wd)) {
		perror("S3CFB_WIN_CONFIG");
		return 1;
	}
	t0 = now();
	printf("test1: retire_fence=%d rel_fence=%d remained=%d\n", wd.retire_fence,
	       wd.config[0].rel_fence, wd.extra.remained_frames);
	if (wd.retire_fence < 0 || wd.config[0].rel_fence < 0) {
		fails++;
	} else {
		int ok = wait_fence(wd.retire_fence, 500);

		printf("test1: retire %s after %.1f ms; rel %s\n", ok ? "signalled" : "NOT signalled",
		       (now() - t0) * 1e3, wait_fence(wd.config[0].rel_fence, 0) ? "signalled" : "NOT signalled");
		fails += !ok;
		close(wd.retire_fence);
		close(wd.config[0].rel_fence);
	}

	/* 2: no windows */
	memset(&wd, 0, sizeof(wd));
	wd.retire_fence = -1;
	wd.fd_odma = -1;
	if (ioctl(fb, S3CFB_WIN_CONFIG, &wd)) {
		perror("S3CFB_WIN_CONFIG (empty)");
		fails++;
	} else {
		printf("test2: empty config retire_fence=%d (expect -1)\n", wd.retire_fence);
		fails += wd.retire_fence != -1;
	}

	/* 3: acquire fence */
	if (argc > 2) {
		struct sw_sync_create_fence_data f = { .value = 1, .name = "a50-acq" };
		int tl = open(argv[2], O_RDWR);
		uint32_t one = 1;

		if (tl < 0 || ioctl(tl, SW_SYNC_IOC_CREATE_FENCE, &f)) {
			perror("sw_sync");
			fails++;
		} else {
			fill(&wd, a.fd, f.fence);
			if (ioctl(fb, S3CFB_WIN_CONFIG, &wd)) {
				perror("S3CFB_WIN_CONFIG (acq)");
				fails++;
			} else {
				int early = wait_fence(wd.retire_fence, 300), late;

				ioctl(tl, SW_SYNC_IOC_INC, &one);
				t0 = now();
				late = wait_fence(wd.retire_fence, 500);
				printf("test3: before acquire signal: %s; after: %s in %.1f ms\n",
				       early ? "SIGNALLED (wrong)" : "unsignalled", late ? "signalled" : "NOT signalled",
				       (now() - t0) * 1e3);
				fails += early || !late;
				close(wd.retire_fence);
				close(wd.config[0].rel_fence);
			}
			close(f.fence);
			close(tl);
		}
	}
	printf("RESULT: %s\n", fails ? "FAIL" : "PASS");
	return fails ? 1 : 0;
}

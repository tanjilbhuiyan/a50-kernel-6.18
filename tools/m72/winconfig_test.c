// SPDX-License-Identifier: Apache-2.0
/*
 * M7.2 D2b: userspace check of S3CFB_WIN_CONFIG on the a50-decon fbdev driver.
 * 1. Allocate a full-screen buffer from /dev/ion (heap 0, the M6.3 ABI), draw a pattern in
 *    Android byte order R,G,B,A (ABI format RGBA_8888, value 2: M7.3 G2c follows the stock driver's
 *    ABI-to-DPP translation; M7.2 used value 1 with a pass-through driver), submit it as one BUFFER window,
 *    and wait for the retire fence. Expect retire_fence >= 0, rel_fence >= 0, signalled < 500 ms.
 *    Pattern: top half a horizontal gradient magenta -> cyan, bottom half a black/white
 *    checkerboard of 135-pixel squares.
 * 2. Submit a configuration without windows: expect retire_fence == -1.
 * 3. Submit the same buffer with an unsignalled sw_sync acquire fence: the retire fence must stay
 *    unsignalled for 300 ms, then signal after the acquire fence is signalled (needs debugfs).
 * 4. (M7.2 D3b) Flip between that buffer and a second one (left half yellow, right half blue) 30 times,
 *    waiting for each retire fence; report the average time per frame. Ends on the second buffer.
 * 5. (M7.3 G2c) Known colours: four horizontal bands (red, green, blue, white) encoded in turn as ABI
 *    ARGB_8888, RGBA_8888, BGRA_8888 and ABGR_8888 (byte orders A,R,G,B / R,G,B,A / B,G,R,A / A,B,G,R),
 *    2 s each. A correct translation shows the same bands throughout.
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
	c->format = 2;			/* ABI RGBA_8888: bytes R,G,B,A */
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
	/* 4: flip between two buffers */
	{
		struct ion_allocation_data b = { .len = W * H * 4, .heap_id_mask = 1, .flags = 0 };
		uint8_t *q;
		int n, slow = 0;
		double t;

		if (ioctl(ion, ION_IOC_ALLOC, &b) ||
		    (q = mmap(NULL, b.len, PROT_READ | PROT_WRITE, MAP_SHARED, b.fd, 0)) == MAP_FAILED) {
			perror("second buffer");
			fails++;
		} else {
			for (y = 0; y < H; y++)
				for (x = 0; x < W; x++) {
					uint8_t *p = q + 4 * ((size_t)y * W + x);

					p[0] = x < W / 2 ? 255 : 0;	/* yellow | blue */
					p[1] = x < W / 2 ? 255 : 0;
					p[2] = x < W / 2 ? 0 : 255;
					p[3] = 255;
				}
			t0 = now();
			for (n = 0; n < 30; n++) {
				fill(&wd, n & 1 ? b.fd : a.fd, -1);
				if (n == 29)
					fill(&wd, b.fd, -1);
				t = now();
				if (ioctl(fb, S3CFB_WIN_CONFIG, &wd) || wd.retire_fence < 0) {
					perror("flip");
					fails++;
					break;
				}
				if (!wait_fence(wd.retire_fence, 500))
					slow++;
				if (now() - t > 0.1)
					slow++;
				close(wd.retire_fence);
				close(wd.config[0].rel_fence);
			}
			printf("test4: %d flips in %.1f ms, %.1f ms per frame, %d over 100 ms\n", n,
			       (now() - t0) * 1e3, (now() - t0) * 1e3 / n, slow);
			fails += n != 30;
		}
	}
	/* 5: known colours in four byte orders */
	{
		static const char *order[4] = { "ARGB", "RGBA", "BGRA", "ABGR" };
		static const uint32_t abi[4] = { 0, 2, 3, 1 };
		static const uint8_t band[4][3] = { { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 255, 255, 255 } };
		int k;

		for (k = 0; k < 4; k++) {
			for (y = 0; y < H; y++) {
				const uint8_t *c = band[y * 4 / H];

				for (x = 0; x < W; x++) {
					uint8_t *p = px + 4 * ((size_t)y * W + x);
					int j;

					for (j = 0; j < 4; j++)
						p[j] = order[k][j] == 'A' ? 255 : order[k][j] == 'R' ? c[0] :
						       order[k][j] == 'G' ? c[1] : c[2];
				}
			}
			fill(&wd, a.fd, -1);
			wd.config[0].format = abi[k];
			if (ioctl(fb, S3CFB_WIN_CONFIG, &wd) || wd.retire_fence < 0) {
				perror("known colours");
				fails++;
				break;
			}
			printf("test5: ABI %u (%s bytes) retire %s\n", abi[k], order[k],
			       wait_fence(wd.retire_fence, 500) ? "signalled" : "NOT signalled");
			fflush(stdout);
			close(wd.retire_fence);
			close(wd.config[0].rel_fence);
			sleep(2);
		}
	}
	printf("RESULT: %s\n", fails ? "FAIL" : "PASS");
	return fails ? 1 : 0;
}

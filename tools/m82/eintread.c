/*
 * M8.2 P2: read-only samples of the touch interrupt line (gpa0-0) and its wake-up interrupt configuration.
 * /dev/mem O_RDONLY, single-page PROT_READ maps, allow-list: pinctrl ALIVE page 0x11850000 (always clocked) and the
 * GIC distributor page 0x12301000. 20 samples, 100 ms apart. Usage: eintread
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define ALIVE 0x11850000u
#define GICD 0x12301000u

static int rd(int fd, uint32_t a, uint32_t *v)
{
	void *m;

	if (!((a >= ALIVE && a < ALIVE + 0x1000) || (a >= GICD && a < GICD + 0x1000)) || (a & 3))
		return -EINVAL;
	m = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, a & ~0xfffu);
	if (m == MAP_FAILED)
		return -errno;
	*v = *(volatile uint32_t *)((char *)m + (a & 0xfff));
	munmap(m, 4096);
	return 0;
}

int main(void)
{
	static const struct { const char *n; uint32_t a; } r[] = {
		{ "GPA0_CON", ALIVE + 0x020 }, { "GPA0_DAT", ALIVE + 0x024 }, { "GPA0_PUD", ALIVE + 0x028 },
		{ "WKUP_ECON_gpa0", ALIVE + 0x700 }, { "WKUP_FLTCON_gpa0", ALIVE + 0x800 },
		{ "WKUP_EMASK_gpa0", ALIVE + 0x900 }, { "WKUP_EPEND_gpa0", ALIVE + 0xa00 },
		{ "GICD_ISENABLER1", GICD + 0x104 }, { "GICD_ISPENDR1", GICD + 0x204 }, { "GICD_ISACTIVER1", GICD + 0x304 },
		{ "GICD_ICFGR2", GICD + 0xc08 },
	};
	int fd = open("/dev/mem", O_RDONLY | O_SYNC), s, i;
	uint32_t v;

	if (fd < 0) { printf("open /dev/mem: %s\n", strerror(errno)); return 1; }
	for (i = 0; i < (int)(sizeof(r) / sizeof(r[0])); i++) {
		if (rd(fd, r[i].a, &v)) { printf("%-18s 0x%08x ERROR\n", r[i].n, r[i].a); continue; }
		printf("%-18s 0x%08x 0x%08x\n", r[i].n, r[i].a, v);
	}
	for (s = 0; s < 20; s++) {
		uint32_t dat = 0, pend = 0, con = 0, ispend = 0;
		rd(fd, ALIVE + 0x024, &dat); rd(fd, ALIVE + 0xa00, &pend); rd(fd, ALIVE + 0x020, &con); rd(fd, GICD + 0x204, &ispend);
		printf("sample %2d: gpa0-0 level=%u con_func=0x%x epend=%u gic_spi0_pending=%u\n", s, dat & 1, con & 0xf,
		       pend & 1, ispend & 1);
		usleep(100000);
	}
	rd(fd, ALIVE + 0x700, &v);
	printf("WKUP_ECON gpa0-0 type=%u (0=level low,1=level high,2=falling,3=rising,4=both)\n", v & 0x7);
	printf("refuse_other=%s\n", rd(fd, 0x13870000u, &v) == -EINVAL ? "ok" : "FAIL");
	close(fd);
	return 0;
}

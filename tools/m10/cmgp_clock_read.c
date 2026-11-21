/* B2: read-only, fixed-list CMU observations. No I2C/controller access.
 * Bases from stock cmucal-sfr.c; offsets from clk-exynos9610.c.
 * /dev/mem O_RDONLY; PROT_READ; no caller-supplied addresses. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

struct reg { const char *name; uint32_t addr; };
static const struct reg regs[] = {
	{ "TOP_SHARED0_PLL_CON0", 0x12100120 },
	{ "TOP_SHARED1_PLL_CON0", 0x12100140 },
	{ "TOP_MUX_APM_BUS", 0x12101000 },
	{ "TOP_DIV_APM_BUS", 0x12101808 },
	{ "TOP_DIV_SHARED0_DIV4", 0x121018b0 },
	{ "TOP_DIV_SHARED1_DIV4", 0x121018bc },
	{ "APM_MUX_BUS_USER", 0x11800100 },
	{ "APM_MUX_BUS", 0x11801004 },
	{ "APM_DIV_BUS", 0x11801804 },
	{ "APM_GATE_CMGP_BUS", 0x11802000 },
	{ "CMGP_MUX_I2C", 0x11c01004 },
	{ "CMGP_DIV_I2C", 0x11c01804 },
	{ "CMGP_GATE_I2C00_IPCLK", 0x11c02018 },
	{ "CMGP_GATE_I2C00_PCLK", 0x11c0201c },
	{ "CMGP_GATE_I2C_CLK", 0x11c02044 },
	{ "CMGP_QCH_I2C00", 0x11c03014 },
};

int main(void)
{
	long page = sysconf(_SC_PAGESIZE);
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	unsigned i;
	if (fd < 0) { perror("/dev/mem"); return 1; }
	if (page <= 0) { close(fd); return 1; }
	for (i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
		uint32_t base = regs[i].addr & ~((uint32_t)page - 1);
		void *map = mmap(NULL, page, PROT_READ, MAP_SHARED, fd, base);
		uint32_t value;
		if (map == MAP_FAILED) {
			fprintf(stderr, "%s: %s\n", regs[i].name, strerror(errno));
			close(fd); return 1;
		}
		value = *(volatile uint32_t *)((char *)map + regs[i].addr - base);
		printf("%s 0x%08x 0x%08x\n", regs[i].name, regs[i].addr, value);
		fflush(stdout);
		munmap(map, page);
	}
	close(fd);
	return 0;
}

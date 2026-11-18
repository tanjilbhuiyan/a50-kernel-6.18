/*
 * M8.1 R1: read-only dump of the CMU_PERI clock and GIC registers that an Exynos 9610 I2C probe depends on.
 * Opens /dev/mem O_RDONLY, maps single pages PROT_READ, and refuses any address outside a fixed allow-list:
 * CMU_PERI (0x10030000-0x10033fff: CMU registers, always clocked) and the GIC distributor page (0x12301000).
 * It never touches the I2C controllers themselves (their registers can hang the bus while their clock is gated).
 * Usage: regread  (prints "name addr value" lines and a decoded summary)
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define CMU_PERI 0x10030000u
#define GICD 0x12301000u

struct reg { const char *name; uint32_t addr; };
static const struct reg regs[] = {
	{ "PLL_CON0_MUX_CLKCMU_PERI_BUS_USER", CMU_PERI + 0x0100 }, { "PLL_CON2_MUX_CLKCMU_PERI_BUS_USER", CMU_PERI + 0x0108 },
	{ "PLL_CON0_MUX_CLKCMU_PERI_IP_USER", CMU_PERI + 0x0120 }, { "PLL_CON2_MUX_CLKCMU_PERI_IP_USER", CMU_PERI + 0x0128 },
	{ "PLL_CON0_MUX_CLKCMU_PERI_UART_USER", CMU_PERI + 0x0140 },
	{ "CMU_PERI_CONTROLLER_OPTION", CMU_PERI + 0x0800 },
	{ "CLK_CON_DIV_DIV_CLK_PERI_I2C", CMU_PERI + 0x1800 },
	{ "CLK_CON_GAT_GATE_CLK_PERI_I2C", CMU_PERI + 0x2008 },
	{ "CLK_CON_GAT_GOUT_PERI_GPIO_PCLK", CMU_PERI + 0x2048 },
	{ "CLK_CON_GAT_GOUT_PERI_I2C_0_PCLK", CMU_PERI + 0x204c }, { "CLK_CON_GAT_GOUT_PERI_I2C_1_PCLK", CMU_PERI + 0x2050 },
	{ "CLK_CON_GAT_GOUT_PERI_I2C_2_PCLK", CMU_PERI + 0x2054 }, { "CLK_CON_GAT_GOUT_PERI_I2C_3_PCLK", CMU_PERI + 0x2058 },
	{ "CLK_CON_GAT_GOUT_PERI_I2C_4_PCLK", CMU_PERI + 0x205c }, { "CLK_CON_GAT_GOUT_PERI_I2C_5_PCLK", CMU_PERI + 0x2060 },
	{ "CLK_CON_GAT_GOUT_PERI_I2C_6_PCLK", CMU_PERI + 0x2064 },
	{ "CLK_CON_GAT_GOUT_PERI_MCT_PCLK", CMU_PERI + 0x206c },
	{ "CLK_CON_GAT_GOUT_PERI_PWM_MOTOR_PCLK_S0", CMU_PERI + 0x2074 },
	{ "CLK_CON_GAT_GOUT_PERI_BUS_CLK", CMU_PERI + 0x2078 },
	{ "CLK_CON_GAT_GOUT_PERI_I2C_CLK", CMU_PERI + 0x207c },
	{ "CLK_CON_GAT_GOUT_PERI_WDT_CLUSTER0_PCLK", CMU_PERI + 0x20cc }, { "CLK_CON_GAT_GOUT_PERI_WDT_CLUSTER1_PCLK", CMU_PERI + 0x20d0 },
	{ "QCH_CON_I2C_0_QCH", CMU_PERI + 0x301c }, { "QCH_CON_I2C_1_QCH", CMU_PERI + 0x3020 },
	{ "QCH_CON_I2C_2_QCH", CMU_PERI + 0x3024 }, { "QCH_CON_I2C_3_QCH", CMU_PERI + 0x3028 },
	{ "QCH_CON_I2C_4_QCH", CMU_PERI + 0x302c }, { "QCH_CON_I2C_5_QCH", CMU_PERI + 0x3030 },
	{ "QCH_CON_I2C_6_QCH", CMU_PERI + 0x3034 },
	{ "QCH_CON_PERI_CMU_PERI_QCH", CMU_PERI + 0x3044 }, { "QCH_CON_PWM_MOTOR_QCH", CMU_PERI + 0x3048 },
	{ "GICD_CTLR", GICD + 0x000 },
	{ "GICD_ISENABLER8 (ids 256-287)", GICD + 0x120 },
	{ "GICD_ISPENDR8 (ids 256-287)", GICD + 0x220 },
	{ "GICD_ISACTIVER8 (ids 256-287)", GICD + 0x320 },
	{ "GICD_ICFGR17 (ids 272-287)", GICD + 0xc44 },
	{ "GICD_ITARGETSR (ids 276-279)", GICD + 0x914 }, { "GICD_ITARGETSR (ids 280-283)", GICD + 0x918 },
	{ "GICD_ITARGETSR (ids 284-287)", GICD + 0x91c },
};

static int allowed(uint32_t a)
{
	return (a >= CMU_PERI && a < CMU_PERI + 0x4000) || (a >= GICD && a < GICD + 0x1000);
}

static int rd(int fd, uint32_t addr, uint32_t *val)
{
	long pg = sysconf(_SC_PAGESIZE);
	uint32_t base = addr & ~(uint32_t)(pg - 1);
	void *m;

	if (!allowed(addr) || (addr & 3))
		return -EINVAL;
	m = mmap(NULL, pg, PROT_READ, MAP_SHARED, fd, base);
	if (m == MAP_FAILED)
		return -errno;
	*val = *(volatile uint32_t *)((char *)m + (addr - base));
	munmap(m, pg);
	return 0;
}

int main(void)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	unsigned i, bad = 0;
	uint32_t v, pend = 0, en = 0, act = 0;

	if (fd < 0) {
		printf("open /dev/mem: %s\n", strerror(errno));
		return 1;
	}
	for (i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
		int r = rd(fd, regs[i].addr, &v);

		if (r) {
			printf("%-42s 0x%08x ERROR %s\n", regs[i].name, regs[i].addr, strerror(-r));
			bad++;
			continue;
		}
		printf("%-42s 0x%08x 0x%08x\n", regs[i].name, regs[i].addr, v);
		if (regs[i].addr == GICD + 0x120) en = v;
		if (regs[i].addr == GICD + 0x220) pend = v;
		if (regs[i].addr == GICD + 0x320) act = v;
		if (regs[i].addr >= CMU_PERI + 0x2000 && regs[i].addr < CMU_PERI + 0x3000)
			printf("    gate: manual=%u value=%u hwacg=%u\n", (v >> 20) & 1, (v >> 21) & 1, (v >> 28) & 1);
		if (regs[i].addr >= CMU_PERI + 0x3000 && regs[i].addr < CMU_PERI + 0x4000)
			printf("    qch: enable=%u clock_req=%u ignore_force_pm=%u\n", v & 1, (v >> 1) & 1, (v >> 2) & 1);
	}
	for (i = 247; i <= 253; i++) {
		unsigned bit = (32 + i) - 256;
		printf("SPI %u (id %u): enabled=%u pending=%u active=%u\n", i, 32 + i, (en >> bit) & 1, (pend >> bit) & 1, (act >> bit) & 1);
	}
	/* refusal self-check: an I2C controller address must be rejected without mapping */
	printf("refuse_i2c_controller=%s\n", rd(fd, 0x13830000u, &v) == -EINVAL ? "ok" : "FAIL");
	close(fd);
	return bad ? 2 : 0;
}

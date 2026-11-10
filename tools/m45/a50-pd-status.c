// SPDX-License-Identifier: GPL-2.0
/*
 * TEST ONLY (M4.5), do not merge: log the power-domain configuration and
 * status registers (read-only). Offsets from 4.14
 * drivers/soc/samsung/cal-if/exynos9610/pmucal_local_exynos9610.h:
 * STATUS = CONFIGURATION + 4, bits 3:0 = 0xF on, 0 off.
 */
#include <linux/init.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/printk.h>

static const struct {
	const char *name;
	u16 off;
} pds[] = {
	{ "dispaud", 0x4000 }, { "cam", 0x4020 }, { "g2d", 0x4040 }, { "g3d", 0x4060 },
	{ "isp", 0x4080 }, { "mfc", 0x40a0 }, { "vipx1", 0x40e0 },
};

static int __init a50_pd_status(void)
{
	void __iomem *pmu = ioremap(0x11860000, 0x5000);
	unsigned int i;
	u32 st;

	if (!pmu)
		return 0;
	for (i = 0; i < ARRAY_SIZE(pds); i++) {
		st = readl(pmu + pds[i].off + 4);
		pr_info("a50-pd: %s conf=0x%08x status=0x%08x -> %s\n", pds[i].name,
			readl(pmu + pds[i].off), st,
			(st & 0xf) == 0xf ? "on" : (st & 0xf) ? "transition" : "off");
	}
	iounmap(pmu);
	return 0;
}
late_initcall(a50_pd_status);

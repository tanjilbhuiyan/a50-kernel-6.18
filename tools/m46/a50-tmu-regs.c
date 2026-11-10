// SPDX-License-Identifier: GPL-2.0
/*
 * TEST ONLY (M4.6), do not merge: log the thermal unit's registers at
 * 0x10070000 (read-only), three times one second apart, to see whether the
 * sensors run under 6.18 without the firmware's thermal handling.
 * Offsets from 4.14 drivers/thermal/samsung/exynos_tmu.c.
 */
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/printk.h>

static const struct {
	const char *name;
	u16 off;
} regs[] = {
	{ "TRIMINFO0", 0x00 }, { "TRIMINFO1", 0x04 }, { "TRIMINFO2", 0x08 }, { "TRIMINFO3", 0x0c },
	{ "CONTROL", 0x20 }, { "CONTROL1", 0x24 }, { "STATUS", 0x28 },
	{ "COUNTER0", 0x30 }, { "COUNTER1", 0x34 }, { "AVG_CON", 0x38 }, { "TRIM0", 0x3c },
	{ "CURRENT_TEMP1_0", 0x40 }, { "CURRENT_TEMP4_2", 0x44 }, { "CURRENT_TEMP7_5", 0x48 },
};

static int __init a50_tmu_regs(void)
{
	void __iomem *p = ioremap(0x10070000, 0x800);
	unsigned int i, n;

	if (!p)
		return 0;
	for (n = 0; n < 3; n++) {
		for (i = 0; i < ARRAY_SIZE(regs); i++)
			pr_info("a50-tmureg: pass %u %s +0x%02x = 0x%08x\n", n, regs[i].name,
				regs[i].off, readl(p + regs[i].off));
		msleep(1000);
	}
	iounmap(p);
	return 0;
}
late_initcall(a50_tmu_regs);

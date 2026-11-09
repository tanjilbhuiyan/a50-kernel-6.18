// SPDX-License-Identifier: GPL-2.0
/*
 * M3.6 diagnostic for the BASELINE 4.14 kernel: log the USB PHY, CMU_USB and
 * PMU isolation registers of a working phone, for comparison with 6.18.
 *
 * Read-only: readl() on registers defined in the sources (regs.h, generated
 * by gen_regs.py). There is no write in this file. Init deliberately returns
 * an error, so the module never stays loaded; the values are in dmesg.
 *
 * Load only with USB attached and configured, so that the PHY clock is on.
 */
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/types.h>

struct a50_reg {
	const char *name;
	u32 off;
};

#include "regs.h"

#define PHY_BASE	0x131d0000
#define PHY_SIZE	0x200
#define CMU_USB_BASE	0x13030000
#define CMU_USB_SIZE	0x8000
#define PMU_BASE	0x11860000
#define PMU_SIZE	0x1000

static const struct a50_reg pmu_regs[] = {
	{ "PMU_USB_ISOLATION", 0x704 },
};

static void __init a50_dump(const char *block, phys_addr_t base, size_t size,
			    const struct a50_reg *regs, unsigned int n)
{
	void __iomem *p = ioremap(base, size);
	unsigned int i;

	if (!p) {
		pr_err("a50-usbdump: ioremap of %s failed\n", block);
		return;
	}
	for (i = 0; i < n; i++) {
		if (regs[i].off >= size)
			continue;
		pr_info("a50-usbdump: %s %s +0x%04x = 0x%08x\n", block,
			regs[i].name, regs[i].off, readl(p + regs[i].off));
	}
	iounmap(p);
}

static int __init a50_usbdump_init(void)
{
	pr_info("a50-usbdump: BEGIN\n");
	a50_dump("PMU", PMU_BASE, PMU_SIZE, pmu_regs, ARRAY_SIZE(pmu_regs));
	a50_dump("PHY", PHY_BASE, PHY_SIZE, phy_regs, ARRAY_SIZE(phy_regs));
	a50_dump("CMU_USB", CMU_USB_BASE, CMU_USB_SIZE, cmu_usb_regs,
		 ARRAY_SIZE(cmu_usb_regs));
	pr_info("a50-usbdump: END\n");
	return -EAGAIN;
}
module_init(a50_usbdump_init);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A50 M3.6: read-only USB register dump");

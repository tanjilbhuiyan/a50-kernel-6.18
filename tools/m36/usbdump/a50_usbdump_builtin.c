// SPDX-License-Identifier: GPL-2.0
/*
 * M3.6 diagnostic, built into a 4.14 TEST kernel only (the baseline refuses
 * modules). Reading /sys/kernel/debug/a50_usbdump prints the USB PMU, PHY and
 * CMU_USB registers of a working phone, for comparison with 6.18.
 *
 * Read-only: readl() on registers defined in the sources (regs.h, generated
 * by gen_regs.py). There is no write in this file.
 *
 * Read the file only with USB attached and configured, so the PHY clock is on.
 */
#include <linux/debugfs.h>
#include <linux/errno.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/seq_file.h>
#include <linux/types.h>

struct a50_reg {
	const char *name;
	u32 off;
};

#include "a50_usbdump_regs.h"

#define PHY_BASE	0x131d0000
#define PHY_SIZE	0x200
#define CMU_USB_BASE	0x13030000
#define CMU_USB_SIZE	0x8000
#define PMU_BASE	0x11860000
#define PMU_SIZE	0x1000

static const struct a50_reg pmu_regs[] = {
	{ "PMU_USB_ISOLATION", 0x704 },
};

static void a50_dump(struct seq_file *s, const char *block, phys_addr_t base,
		     size_t size, const struct a50_reg *regs, unsigned int n)
{
	void __iomem *p = ioremap(base, size);
	unsigned int i;

	if (!p) {
		seq_printf(s, "%s: ioremap failed\n", block);
		return;
	}
	for (i = 0; i < n; i++) {
		if (regs[i].off >= size)
			continue;
		seq_printf(s, "%s %s +0x%04x = 0x%08x\n", block, regs[i].name,
			   regs[i].off, readl(p + regs[i].off));
	}
	iounmap(p);
}

static int a50_usbdump_show(struct seq_file *s, void *unused)
{
	a50_dump(s, "PMU", PMU_BASE, PMU_SIZE, pmu_regs, ARRAY_SIZE(pmu_regs));
	a50_dump(s, "PHY", PHY_BASE, PHY_SIZE, phy_regs, ARRAY_SIZE(phy_regs));
	a50_dump(s, "CMU_USB", CMU_USB_BASE, CMU_USB_SIZE, cmu_usb_regs,
		 ARRAY_SIZE(cmu_usb_regs));
	return 0;
}

static int a50_usbdump_open(struct inode *inode, struct file *file)
{
	return single_open(file, a50_usbdump_show, NULL);
}

static const struct file_operations a50_usbdump_fops = {
	.open		= a50_usbdump_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init a50_usbdump_init(void)
{
	debugfs_create_file("a50_usbdump", 0400, NULL, NULL, &a50_usbdump_fops);
	return 0;
}
late_initcall(a50_usbdump_init);

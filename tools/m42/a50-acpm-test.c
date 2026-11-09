// SPDX-License-Identifier: GPL-2.0
/*
 * TEST ONLY (M4.2), do not merge: read S2MPU09 registers through the mainline
 * ACPM driver and compare with the baseline. Only pmic_ops.read_reg is called,
 * so nothing is written to the PMIC.
 */
#include <linux/err.h>
#include <linux/firmware/samsung/exynos-acpm-protocol.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/platform_device.h>

#define PMIC_CHANNEL	2
#define PMIC_TYPE	1
#define REPEATS		1000

static const struct {
	const char *name;
	u8 reg;
	u8 baseline;
} regs[] = {
	{ "LDO12", 0x45, 0xcc },
	{ "LDO13", 0x46, 0xec },
	{ "LDO14", 0x47, 0xf0 },
};

static int a50_acpm_test_probe(struct platform_device *pdev)
{
	const struct acpm_pmic_ops *ops;
	struct acpm_handle *handle;
	struct device_node *np;
	unsigned int i, n, errors = 0, wrong = 0;
	u8 v = 0;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "samsung,exynos9610-acpm-ipc");
	if (!np)
		return -ENODEV;
	handle = devm_acpm_get_by_node(&pdev->dev, np);
	of_node_put(np);
	if (IS_ERR(handle))
		return PTR_ERR(handle);
	ops = &handle->ops.pmic_ops;

	for (i = 0; i < ARRAY_SIZE(regs); i++) {
		ret = ops->read_reg(handle, PMIC_CHANNEL, PMIC_TYPE, regs[i].reg, 0, &v);
		pr_info("a50-acpm-test: %s reg 0x%02x = 0x%02x (baseline 0x%02x) ret=%d\n",
			regs[i].name, regs[i].reg, v, regs[i].baseline, ret);
	}

	for (n = 0; n < REPEATS; n++) {
		for (i = 0; i < ARRAY_SIZE(regs); i++) {
			ret = ops->read_reg(handle, PMIC_CHANNEL, PMIC_TYPE, regs[i].reg, 0, &v);
			if (ret)
				errors++;
			else if (v != regs[i].baseline)
				wrong++;
		}
	}
	pr_info("a50-acpm-test: RESULT %u x %zu reads, errors=%u, wrong=%u\n",
		REPEATS, ARRAY_SIZE(regs), errors, wrong);
	return 0;
}

static struct platform_driver a50_acpm_test_driver = {
	.probe	= a50_acpm_test_probe,
	.driver	= { .name = "a50-acpm-test" },
};

static int __init a50_acpm_test_init(void)
{
	int ret = platform_driver_register(&a50_acpm_test_driver);

	if (ret)
		return ret;
	return PTR_ERR_OR_ZERO(platform_device_register_simple("a50-acpm-test", -1, NULL, 0));
}
late_initcall(a50_acpm_test_init);

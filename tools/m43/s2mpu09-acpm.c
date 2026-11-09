// SPDX-License-Identifier: GPL-2.0
/*
 * Samsung S2MPU09 PMIC regulators, read through the ACPM firmware.
 *
 * Read-only for now: the operations can report whether a regulator is on and
 * its voltage, but cannot change either. There are no enable, disable or
 * set_voltage operations, and this driver never calls an ACPM write, so the
 * regulator core cannot change the state the bootloader left.
 */
#include <linux/err.h>
#include <linux/firmware/samsung/exynos-acpm-protocol.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/regulator/driver.h>
#include <linux/slab.h>

#define S2MPU09_ACPM_CHANNEL	2	/* "acpm-ipc-channel" of the stock s2mpu09mfd node */
#define S2MPU09_TYPE_PMIC	1	/* I2C_ADDR_PMIC in the 4.14 driver */
#define S2MPU09_ENABLE_MASK	0xc0
#define S2MPU09_LDO_VSEL_MASK	0x3f
#define S2MPU09_LDO_N_VOLTAGES	0x40
#define S2MPU09_BUCK_VSEL_MASK	0xff
#define S2MPU09_BUCK_N_VOLTAGES	0x100

struct s2mpu09_acpm_reg {
	const char *name;
	bool buck;
	unsigned int min_uV;
	unsigned int uV_step;
	u8 vsel_reg;
	u8 enable_reg;
};

#include "s2mpu09-acpm-regs.h"

struct s2mpu09_acpm {
	struct acpm_handle *handle;
};

static int s2mpu09_acpm_read(struct s2mpu09_acpm *pmic, u8 reg, u8 *val)
{
	return pmic->handle->ops.pmic_ops.read_reg(pmic->handle, S2MPU09_ACPM_CHANNEL,
						   S2MPU09_TYPE_PMIC, reg, 0, val);
}

static int s2mpu09_acpm_is_enabled(struct regulator_dev *rdev)
{
	u8 val;
	int ret = s2mpu09_acpm_read(rdev_get_drvdata(rdev), rdev->desc->enable_reg, &val);

	if (ret)
		return ret;
	return !!(val & rdev->desc->enable_mask);
}

static int s2mpu09_acpm_get_voltage_sel(struct regulator_dev *rdev)
{
	u8 val;
	int ret = s2mpu09_acpm_read(rdev_get_drvdata(rdev), rdev->desc->vsel_reg, &val);

	if (ret)
		return ret;
	return val & rdev->desc->vsel_mask;
}

static const struct regulator_ops s2mpu09_acpm_ops = {
	.is_enabled	= s2mpu09_acpm_is_enabled,
	.get_voltage_sel = s2mpu09_acpm_get_voltage_sel,
	.list_voltage	= regulator_list_voltage_linear,
};

static int s2mpu09_acpm_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct regulator_config cfg = { .dev = dev };
	struct regulator_desc *descs;
	struct s2mpu09_acpm *pmic;
	unsigned int i;

	pmic = devm_kzalloc(dev, sizeof(*pmic), GFP_KERNEL);
	if (!pmic)
		return -ENOMEM;
	descs = devm_kcalloc(dev, ARRAY_SIZE(s2mpu09_regs), sizeof(*descs), GFP_KERNEL);
	if (!descs)
		return -ENOMEM;

	pmic->handle = devm_acpm_get_by_node(dev, dev->parent->of_node);
	if (IS_ERR(pmic->handle))
		return dev_err_probe(dev, PTR_ERR(pmic->handle), "no ACPM handle\n");

	cfg.driver_data = pmic;
	for (i = 0; i < ARRAY_SIZE(s2mpu09_regs); i++) {
		const struct s2mpu09_acpm_reg *r = &s2mpu09_regs[i];
		struct regulator_dev *rdev;

		descs[i].name = r->name;
		descs[i].of_match = r->name;
		descs[i].regulators_node = "regulators";
		descs[i].id = i;
		descs[i].ops = &s2mpu09_acpm_ops;
		descs[i].type = REGULATOR_VOLTAGE;
		descs[i].owner = THIS_MODULE;
		descs[i].min_uV = r->min_uV;
		descs[i].uV_step = r->uV_step;
		descs[i].n_voltages = r->buck ? S2MPU09_BUCK_N_VOLTAGES : S2MPU09_LDO_N_VOLTAGES;
		descs[i].vsel_reg = r->vsel_reg;
		descs[i].vsel_mask = r->buck ? S2MPU09_BUCK_VSEL_MASK : S2MPU09_LDO_VSEL_MASK;
		descs[i].enable_reg = r->enable_reg;
		descs[i].enable_mask = S2MPU09_ENABLE_MASK;

		rdev = devm_regulator_register(dev, &descs[i], &cfg);
		if (IS_ERR(rdev))
			return dev_err_probe(dev, PTR_ERR(rdev), "%s\n", r->name);
	}
	return 0;
}

static const struct of_device_id s2mpu09_acpm_match[] = {
	{ .compatible = "samsung,s2mpu09-pmic" },
	{},
};
MODULE_DEVICE_TABLE(of, s2mpu09_acpm_match);

static struct platform_driver s2mpu09_acpm_driver = {
	.probe	= s2mpu09_acpm_probe,
	.driver	= {
		.name = "s2mpu09-acpm",
		.of_match_table = s2mpu09_acpm_match,
	},
};
module_platform_driver(s2mpu09_acpm_driver);

MODULE_DESCRIPTION("Samsung S2MPU09 regulators over ACPM (read-only)");
MODULE_LICENSE("GPL");

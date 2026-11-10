// SPDX-License-Identifier: GPL-2.0
/*
 * Exynos 9610 TMU, read-only temperature sensor.
 *
 * The bootloader leaves the TMU running (CONTROL core enable set). This
 * driver only reads the trim and current-temperature registers; it never
 * writes the TMU and sets no thresholds. Register offsets and calibration
 * follow 4.14 drivers/thermal/samsung/exynos_tmu.c; the per-sensor field
 * positions in CURRENT_TEMP were inferred from readings on the phone
 * (log/2026-11-10-M4.6-thermal.md).
 */
#include <linux/err.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/thermal.h>

#define TMU_TRIMINFO(s)		((s) * 4)
#define TMU_CURRENT_TEMP1_0	0x40
#define TMU_CURRENT_TEMP4_2	0x44
#define TMU_CODE_MASK		0x1ff
#define TMU_TRIM_85_SHIFT	9
#define TMU_CALIB_SEL_SHIFT	23
#define TMU_FIRST_POINT		25	/* samsung,tmu_first_point_trim in the stock DT */
#define TMU_SECOND_POINT	85	/* samsung,tmu_second_point_trim */
#define TMU_SENSORS		3

/* Zone id -> sensor, from the stock DT: BIG 0x4, LITTLE 0x2, G3D 0x1, ISP 0x2. */
static const u8 zone_sensor[] = { 2, 1, 0, 1 };

struct tmu_sensor {
	u16 e1, e2;
	bool two_point;
};

struct tmu_zone {
	struct tmu *tmu;
	unsigned int sensor;
};

struct tmu {
	void __iomem *base;
	struct tmu_sensor s[TMU_SENSORS];
	struct tmu_zone zones[ARRAY_SIZE(zone_sensor)];
};

static u16 tmu_code(struct tmu *tmu, unsigned int sensor)
{
	switch (sensor) {
	case 0:
		return readl(tmu->base + TMU_CURRENT_TEMP1_0) & TMU_CODE_MASK;
	case 1:
		return (readl(tmu->base + TMU_CURRENT_TEMP1_0) >> 9) & TMU_CODE_MASK;
	default:
		return readl(tmu->base + TMU_CURRENT_TEMP4_2) & TMU_CODE_MASK;
	}
}

static int tmu_get_temp(struct thermal_zone_device *tz, int *temp)
{
	struct tmu_zone *z = thermal_zone_device_priv(tz);
	const struct tmu_sensor *s = &z->tmu->s[z->sensor];
	int code = tmu_code(z->tmu, z->sensor);

	if (s->two_point)
		*temp = (code - s->e1) * (TMU_SECOND_POINT - TMU_FIRST_POINT) * 1000 /
			(s->e2 - s->e1) + TMU_FIRST_POINT * 1000;
	else
		*temp = (code - s->e1 + TMU_FIRST_POINT) * 1000;
	return 0;
}

static const struct thermal_zone_device_ops tmu_ops = {
	.get_temp = tmu_get_temp,
};

static int tmu_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct tmu *tmu;
	unsigned int i;

	tmu = devm_kzalloc(dev, sizeof(*tmu), GFP_KERNEL);
	if (!tmu)
		return -ENOMEM;
	tmu->base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(tmu->base))
		return PTR_ERR(tmu->base);

	for (i = 0; i < TMU_SENSORS; i++) {
		u32 trim = readl(tmu->base + TMU_TRIMINFO(i));
		struct tmu_sensor *s = &tmu->s[i];

		s->e1 = trim & TMU_CODE_MASK;
		s->e2 = (trim >> TMU_TRIM_85_SHIFT) & TMU_CODE_MASK;
		s->two_point = ((trim >> TMU_CALIB_SEL_SHIFT) & 1) && s->e2 > s->e1;
		if (!s->e1)
			return dev_err_probe(dev, -ENODEV, "sensor %u has no trim data\n", i);
		dev_info(dev, "sensor %u: trim %u/%u, %s-point\n", i, s->e1, s->e2,
			 s->two_point ? "two" : "one");
	}

	for (i = 0; i < ARRAY_SIZE(zone_sensor); i++) {
		struct thermal_zone_device *tz;

		tmu->zones[i].tmu = tmu;
		tmu->zones[i].sensor = zone_sensor[i];
		tz = devm_thermal_of_zone_register(dev, i, &tmu->zones[i], &tmu_ops);
		if (IS_ERR(tz))
			return dev_err_probe(dev, PTR_ERR(tz), "zone %u\n", i);
	}
	return 0;
}

static const struct of_device_id tmu_match[] = {
	{ .compatible = "samsung,exynos9610-tmu" },
	{},
};
MODULE_DEVICE_TABLE(of, tmu_match);

static struct platform_driver tmu_driver = {
	.probe	= tmu_probe,
	.driver	= {
		.name = "exynos9610-tmu",
		.of_match_table = tmu_match,
	},
};
module_platform_driver(tmu_driver);

MODULE_DESCRIPTION("Exynos 9610 TMU, read-only");
MODULE_LICENSE("GPL");

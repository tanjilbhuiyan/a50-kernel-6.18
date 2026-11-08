// SPDX-License-Identifier: GPL-2.0
/*
 * TEST ONLY (M3.6), do not merge: read S2MPU09 registers through the ACPM
 * firmware to learn whether the USB LDOs (12, 13, 14) are on under 6.18.
 *
 * READ-ONLY towards the PMIC: every request sent is FUNC_READ, and the
 * request builder takes no function argument. The only hardware this code
 * writes is the AP<->APM IPC queue in shared SRAM and the mailbox doorbell,
 * as Samsung's 4.14 driver does for a read. The SPEEDY bus is not touched.
 *
 * Layout and protocol from the 4.14 tree:
 *   drivers/soc/samsung/acpm/acpm_ipc.c   (send, check_response, channel_init)
 *   drivers/soc/samsung/acpm/acpm_mfd.c   (exynos_acpm_read_reg)
 *   drivers/soc/samsung/acpm/fw_header/framework.h
 *   include/soc/samsung/acpm_mfd.h
 * Addresses from the stock DT node acpm_ipc, PMIC channel from s2mpu09mfd.
 */
#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/printk.h>
#include <linux/types.h>

#define MBOX_PHYS	0x11900000
#define MBOX_SIZE	0x1000
#define SRAM_PHYS	0x02039000
#define SRAM_SIZE	0x15000
#define INITDATA_OFF	0x6f00
#define PMIC_CHANNEL	2

#define INTGR0		0x08
#define INTGR1		0x1c
#define INTCR1		0x20

/* struct acpm_framework */
#define FW_IPC_CHANNELS	0x08
#define FW_NUM_IPC	0x0c
#define FW_IPC_AP_MAX	0x18

/* struct ipc_channel, including its struct channel_info */
#define CH_ID		0x00
#define CH_TO_APM_REAR	0x10	/* ch.rx_rear: the firmware's receive queue */
#define CH_TO_APM_FRONT	0x14
#define CH_TO_APM_BASE	0x18
#define CH_TO_AP_REAR	0x28	/* ch.tx_rear: the firmware's send queue */
#define CH_TO_AP_FRONT	0x2c
#define CH_TO_AP_BASE	0x30
#define CH_Q_LEN	0x34
#define CH_Q_ELEM	0x38
#define CH_AP_POLL	0x44
#define CH_SIZE		0x48

#define ELEM_SIZE	16	/* exynos_acpm_read_reg() sends four 32-bit words */
#define SEQ_SHIFT	16
#define SEQ_MASK	0x3f
#define PMIC_FUNC_READ	0
#define POLL_US		20000

struct acpm_q {
	void __iomem *rear, *front, *base;
};

static void __iomem *mbox, *sram;
static struct acpm_q to_apm, to_ap;
static u32 q_len, ch_id, seq;

static bool in_sram(u32 off, u32 len)
{
	return off < SRAM_SIZE && len <= SRAM_SIZE - off;
}

/* Only reads exist here: there is deliberately no way to pass another function. */
static int pmic_read(u8 type, u8 reg, u8 *val)
{
	u32 front, rear, next, i, n, w0, w1, sent_seq;
	int t;

	front = readl(to_apm.front);
	rear = readl(to_apm.rear);
	if (front >= q_len || rear >= q_len) {
		pr_err("a50-acpm: queue index out of range f=%u r=%u\n", front, rear);
		return -EIO;
	}
	next = (front + 1) % q_len;
	if (next == rear) {
		pr_err("a50-acpm: request queue full, not sending\n");
		return -EBUSY;
	}

	seq = seq % 63 + 1;
	sent_seq = seq;
	writel(((type & 0xf) << 8) | reg | (sent_seq << SEQ_SHIFT),
	       to_apm.base + ELEM_SIZE * front);
	writel(PMIC_FUNC_READ, to_apm.base + ELEM_SIZE * front + 4);
	writel(0, to_apm.base + ELEM_SIZE * front + 8);
	writel(0, to_apm.base + ELEM_SIZE * front + 12);
	writel(next, to_apm.front);
	writel(BIT(ch_id) << 16, mbox + INTGR0);

	for (t = 0; t < POLL_US; t++) {
		front = readl(to_ap.front);
		rear = readl(to_ap.rear);
		if (front >= q_len || rear >= q_len) {
			pr_err("a50-acpm: reply index out of range f=%u r=%u\n", front, rear);
			return -EIO;
		}
		for (i = rear, n = 0; i != front && n < q_len; i = (i + 1) % q_len, n++) {
			w0 = readl(to_ap.base + ELEM_SIZE * i);
			if (((w0 >> SEQ_SHIFT) & SEQ_MASK) != sent_seq)
				continue;

			w1 = readl(to_ap.base + ELEM_SIZE * i + 4);
			if (i != rear) {
				for (n = 0; n < ELEM_SIZE; n += 4)
					writel(readl(to_ap.base + ELEM_SIZE * rear + n),
					       to_ap.base + ELEM_SIZE * i + n);
			}
			rear = (rear + 1) % q_len;
			writel(rear, to_ap.rear);
			if (rear == readl(to_ap.front)) {
				writel(BIT(ch_id), mbox + INTCR1);
				if (rear != readl(to_ap.front))
					writel(BIT(ch_id), mbox + INTGR1);
			}
			if ((w1 >> 24) & 0xff) {
				pr_err("a50-acpm: firmware error 0x%x (reply word1 0x%08x)\n",
				       (w1 >> 24) & 0xff, w1);
				return -EIO;
			}
			*val = (w1 >> 8) & 0xff;
			return 0;
		}
		udelay(1);
	}

	pr_err("a50-acpm: no reply in %d us (seq %u); stopping\n", POLL_US, sent_seq);
	return -ETIMEDOUT;
}

static const struct {
	const char *name;
	u8 reg;
	u8 baseline;
} ldos[] = {
	{ "LDO12 (0.85 V)", 0x45, 0xcc },
	{ "LDO13 (1.8 V)",  0x46, 0xec },
	{ "LDO14 (3.0 V)",  0x47, 0xf0 },
};

static int __init a50_acpm_probe(void)
{
	u32 chans, ap_max, num, off = 0, i, base_ap, base_apm, elem;
	bool found = false;
	void __iomem *c = NULL;
	u8 v = 0;
	int ret;

	mbox = ioremap(MBOX_PHYS, MBOX_SIZE);
	sram = ioremap(SRAM_PHYS, SRAM_SIZE);
	if (!mbox || !sram) {
		pr_err("a50-acpm: ioremap failed\n");
		goto out;
	}

	chans = readl(sram + INITDATA_OFF + FW_IPC_CHANNELS);
	num = readl(sram + INITDATA_OFF + FW_NUM_IPC);
	ap_max = readl(sram + INITDATA_OFF + FW_IPC_AP_MAX);
	pr_info("a50-acpm: framework ipc_channels=0x%x num=%u ap_max=%u\n", chans, num, ap_max);
	if (ap_max < 1 || ap_max > 16 || !in_sram(chans, ap_max * CH_SIZE)) {
		pr_err("a50-acpm: framework data not plausible, sending nothing\n");
		goto out;
	}

	for (i = 0; i < ap_max; i++) {
		off = chans + i * CH_SIZE;
		if (readl(sram + off + CH_ID) == PMIC_CHANNEL) {
			c = sram + off;
			found = true;
			break;
		}
	}
	if (!found) {
		pr_err("a50-acpm: channel %d not found, sending nothing\n", PMIC_CHANNEL);
		goto out;
	}

	ch_id = PMIC_CHANNEL;
	q_len = readl(c + CH_Q_LEN);
	elem = readl(c + CH_Q_ELEM);
	base_apm = readl(c + CH_TO_APM_BASE);
	base_ap = readl(c + CH_TO_AP_BASE);
	if (q_len < 1 || q_len > 128 || elem != ELEM_SIZE ||
	    !in_sram(base_apm, q_len * ELEM_SIZE) || !in_sram(base_ap, q_len * ELEM_SIZE) ||
	    !in_sram(readl(c + CH_TO_APM_REAR), 4) || !in_sram(readl(c + CH_TO_APM_FRONT), 4) ||
	    !in_sram(readl(c + CH_TO_AP_REAR), 4) || !in_sram(readl(c + CH_TO_AP_FRONT), 4)) {
		pr_err("a50-acpm: channel data not plausible (qlen=%u elem=%u), sending nothing\n",
		       q_len, elem);
		goto out;
	}
	to_apm.rear = sram + readl(c + CH_TO_APM_REAR);
	to_apm.front = sram + readl(c + CH_TO_APM_FRONT);
	to_apm.base = sram + base_apm;
	to_ap.rear = sram + readl(c + CH_TO_AP_REAR);
	to_ap.front = sram + readl(c + CH_TO_AP_FRONT);
	to_ap.base = sram + base_ap;

	pr_info("a50-acpm: ch%u ap_poll=%u qlen=%u to-apm f/r=%u/%u to-ap f/r=%u/%u\n", ch_id,
		readl(c + CH_AP_POLL), q_len, readl(to_apm.front), readl(to_apm.rear),
		readl(to_ap.front), readl(to_ap.rear));

	/* Same register the baseline read back as 0x0c: proves the path before the LDOs. */
	ret = pmic_read(1, 0x00, &v);
	if (ret) {
		pr_err("a50-acpm: PMIC page reg 0x00 read failed (%d), stopping\n", ret);
		goto out;
	}
	pr_info("a50-acpm: PMIC page reg 0x00 = 0x%02x (baseline 0x0c)\n", v);

	for (i = 0; i < ARRAY_SIZE(ldos); i++) {
		ret = pmic_read(1, ldos[i].reg, &v);
		if (ret) {
			pr_err("a50-acpm: %s read failed (%d), stopping\n", ldos[i].name, ret);
			goto out;
		}
		pr_info("a50-acpm: %s CTRL reg 0x%02x = 0x%02x, enable bits %u (%s); baseline 0x%02x\n",
			ldos[i].name, ldos[i].reg, v, v >> 6, (v >> 6) ? "ON" : "OFF",
			ldos[i].baseline);
	}
out:
	if (sram)
		iounmap(sram);
	if (mbox)
		iounmap(mbox);
	return 0;
}
late_initcall(a50_acpm_probe);

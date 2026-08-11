// SPDX-License-Identifier: GPL-2.0
/*
 * Driver for GalaxyCore GC5035 image sensor
 *
 * Copyright (C) 2026 <TODO: real name and email before upstream submission>
 *
 * NOT YET TESTED ON HARDWARE. See the TODO comments marked "BLOCKING".
 *
 * The structure follows drivers/media/i2c/gc05a2.c (Zhi Mao, MediaTek), a
 * driver for a sensor from the same vendor. The x86/ACPI parts follow
 * drivers/media/i2c/ov2740.c, which runs on the same IPU6 chain.
 *
 * The register tables come from the out-of-tree Alder Lake-M patch in
 * intel/ipu6-drivers, which in turn derives from the ChromeOS series by
 * Tomasz Figa. Attribution has to be agreed with the original authors
 * before any submission.
 */
#include <linux/acpi.h>
#include <linux/array_size.h>
#include <linux/bits.h>
#include <linux/clk.h>
#include <linux/container_of.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/math64.h>
#include <linux/pm_runtime.h>
#include <linux/property.h>
#include <linux/regulator/consumer.h>
#include <linux/types.h>
#include <linux/units.h>

#include <media/v4l2-cci.h>
#include <media/v4l2-common.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

/*
 * The GC5035 uses 8 bit register addresses with banked pages: register
 * 0xfe selects the page. Every register below is on page 0 unless noted
 * otherwise.
 */
#define GC5035_REG_PAGE_SELECT		CCI_REG8(0xfe)
#define GC5035_PAGE_0			0x00
#define GC5035_PAGE_1			0x01

/* readable on any page */
#define GC5035_REG_CHIP_ID		CCI_REG16(0xf0)
#define GC5035_CHIP_ID			0x5035

#define GC5035_REG_EXPOSURE		CCI_REG16(0x03)
#define GC5035_REG_ANALOGUE_GAIN	CCI_REG8(0xb6)
#define GC5035_REG_DIGITAL_GAIN_INT	CCI_REG8(0xb1)
#define GC5035_REG_DIGITAL_GAIN_FRAC	CCI_REG8(0xb2)
#define GC5035_REG_FRAME_LENGTH		CCI_REG16(0x41)
#define GC5035_REG_STREAM		CCI_REG8(0x3e)
#define GC5035_STREAM_ON		0x91
#define GC5035_STREAM_OFF		0x01

/* page 1 */
#define GC5035_REG_TEST_PATTERN		CCI_REG8(0x8c)
#define GC5035_TEST_PATTERN_ON		0x11
#define GC5035_TEST_PATTERN_OFF		0x10

#define GC5035_NATIVE_WIDTH		2592
#define GC5035_NATIVE_HEIGHT		1944

#define GC5035_EXP_MIN			4
#define GC5035_EXP_STEP			1
#define GC5035_EXP_MARGIN		16
#define GC5035_VTS_MAX			0x3fff

/*
 * BLOCKING TODO: to be confirmed on hardware. The 438 MHz and the two lanes
 * come from the Intel patch for Alder Lake-M, a different platform. That this
 * value can be machine specific has precedent: commit fb16c04a538e changes the
 * ov2740 link frequency to 180 MHz on machines using ipu-bridge, against the
 * 360 MHz used on Chromebooks.
 *
 * V4L2_CID_LINK_FREQ is the DDR clock, half the per lane bit rate:
 * 876 Mbps/lane / 2 = 438 MHz.
 */
#define GC5035_LINK_FREQ_438MHZ		(438 * HZ_PER_MHZ)
#define GC5035_DATA_LANES		2
#define GC5035_RGB_DEPTH		10

/*
 * The IMGCLKOUT of an Alder Lake PCH can be switched between 24 MHz and
 * 19.2 MHz, but the INT3472 clock driver always selects 19.2 MHz and does not
 * implement .set_rate, so that is what the sensor receives. The vendor tables
 * this driver carries were computed for that rate.
 */
#define GC5035_MCLK_DEFAULT		(19200 * HZ_PER_KHZ)

#define GC5035_SLEEP_US			(5 * USEC_PER_MSEC)

#define GC5035_MBUS_CODE		MEDIA_BUS_FMT_SGRBG10_1X10

static const char * const gc5035_test_pattern_menu[] = {
	"No Pattern",
	"Color Bar",
};

static const s64 gc5035_link_freq_menu_items[] = {
	GC5035_LINK_FREQ_438MHZ,
};

/*
 * On x86 these regulators are provided by INT3472 when the corresponding
 * pins are described in the ACPI _DSM. When they are not, the regulator core
 * hands out dummies and the bulk get still succeeds.
 */
static const char * const gc5035_supply_name[] = {
	"avdd",
	"dvdd",
	"dovdd",
};

/*
 * Register 0xb6 does not take a multiplier, it takes an INDEX into this
 * table. The first column is the gain the entry stands for, in Q8 fixed point
 * where 256 is 1.00x, the second is the code to write. The remainder of the
 * requested gain is compensated digitally in 0xb1/0xb2.
 */
static const u16 gc5035_again_level[][2] = {
	{  256,  0 },	/*  1.000x */
	{  302,  1 },	/*  1.180x */
	{  358,  2 },	/*  1.398x */
	{  425,  3 },	/*  1.660x */
	{  502,  8 },	/*  1.961x */
	{  599,  9 },	/*  2.340x */
	{  717, 10 },	/*  2.801x */
	{  845, 11 },	/*  3.301x */
	{  998, 12 },	/*  3.898x */
	{ 1203, 13 },	/*  4.699x */
	{ 1434, 14 },	/*  5.602x */
	{ 1710, 15 },	/*  6.680x */
	{ 1997, 16 },	/*  7.801x */
	{ 2355, 17 },	/*  9.199x */
	{ 2816, 18 },	/* 11.000x */
	{ 3318, 19 },	/* 12.961x */
	{ 3994, 20 },	/* 15.602x */
};

#define GC5035_AGAIN_MIN		256	/* 1.00x in Q8 */
#define GC5035_AGAIN_MAX		4096	/* 16.00x in Q8 */
#define GC5035_DGAIN_UNITY		256	/* 1.00x in Q8 */

struct gc5035 {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;

	struct clk *xclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(gc5035_supply_name)];
	struct gpio_desc *reset_gpio;
	struct gpio_desc *powerdown_gpio;

	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;

	struct regmap *regmap;
	unsigned long link_freq_bitmap;
	u8 data_lanes;

	bool identified;
	const struct gc5035_mode *cur_mode;
};

struct gc5035_reg_list {
	u32 num_of_regs;
	const struct cci_reg_sequence *regs;
};

/*
 * Register sequences below are reproduced verbatim from the vendor code.
 *
 * Origin: the ChromeOS series posted by Tomasz Figa <tfiga@chromium.org>,
 * later carried in Intel's ipu6-drivers tree with copyrights from Bitland
 * Inc., Google LLC and Intel Corporation.
 *
 * The PLL and D-PHY timing registers are undocumented vendor blobs. There is
 * no public register guide for this sensor, so they cannot be recomputed for
 * a different link frequency or lane count; they are kept unmodified.
 */
static const struct cci_reg_sequence gc5035_init_regs[] = {
	/* init */
	{ CCI_REG8(0xfc), 0x01 },
	{ CCI_REG8(0xf4), 0x40 },
	{ CCI_REG8(0xf5), 0xe9 },
	{ CCI_REG8(0xf6), 0x14 },
	{ CCI_REG8(0xf8), 0x49 },
	{ CCI_REG8(0xf9), 0x82 },
	{ CCI_REG8(0xfa), 0x00 },
	{ CCI_REG8(0xfc), 0x81 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x36), 0x01 },
	{ CCI_REG8(0xd3), 0x87 },
	{ CCI_REG8(0x36), 0x00 },
	{ CCI_REG8(0x33), 0x00 },
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x01), 0xe7 },
	{ CCI_REG8(0xf7), 0x01 },
	{ CCI_REG8(0xfc), 0x8f },
	{ CCI_REG8(0xfc), 0x8f },
	{ CCI_REG8(0xfc), 0x8e },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xee), 0x30 },
	{ CCI_REG8(0x87), 0x18 },
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x8c), 0x90 },
	{ CCI_REG8(0xfe), 0x00 },
	/* Analog & CISCTL */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x05), 0x02 },
	{ CCI_REG8(0x06), 0xda },
	{ CCI_REG8(0x9d), 0x0c },
	{ CCI_REG8(0x09), 0x00 },
	{ CCI_REG8(0x0a), 0x04 },
	{ CCI_REG8(0x0b), 0x00 },
	{ CCI_REG8(0x0c), 0x03 },
	{ CCI_REG8(0x0d), 0x07 },
	{ CCI_REG8(0x0e), 0xa8 },
	{ CCI_REG8(0x0f), 0x0a },
	{ CCI_REG8(0x10), 0x30 },
	{ CCI_REG8(0x11), 0x02 },
	{ CCI_REG8(0x17), 0x80 },
	{ CCI_REG8(0x19), 0x05 },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x30), 0x03 },
	{ CCI_REG8(0x31), 0x03 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xd9), 0xc0 },
	{ CCI_REG8(0x1b), 0x20 },
	{ CCI_REG8(0x21), 0x48 },
	{ CCI_REG8(0x28), 0x22 },
	{ CCI_REG8(0x29), 0x58 },
	{ CCI_REG8(0x44), 0x20 },
	{ CCI_REG8(0x4b), 0x10 },
	{ CCI_REG8(0x4e), 0x1a },
	{ CCI_REG8(0x50), 0x11 },
	{ CCI_REG8(0x52), 0x33 },
	{ CCI_REG8(0x53), 0x44 },
	{ CCI_REG8(0x55), 0x10 },
	{ CCI_REG8(0x5b), 0x11 },
	{ CCI_REG8(0xc5), 0x02 },
	{ CCI_REG8(0x8c), 0x1a },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x33), 0x05 },
	{ CCI_REG8(0x32), 0x38 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x91), 0x80 },
	{ CCI_REG8(0x92), 0x28 },
	{ CCI_REG8(0x93), 0x20 },
	{ CCI_REG8(0x95), 0xa0 },
	{ CCI_REG8(0x96), 0xe0 },
	{ CCI_REG8(0xd5), 0xfc },
	{ CCI_REG8(0x97), 0x28 },
	{ CCI_REG8(0x16), 0x0c },
	{ CCI_REG8(0x1a), 0x1a },
	{ CCI_REG8(0x1f), 0x11 },
	{ CCI_REG8(0x20), 0x10 },
	{ CCI_REG8(0x46), 0x83 },
	{ CCI_REG8(0x4a), 0x04 },
	{ CCI_REG8(0x54), 0x02 },
	{ CCI_REG8(0x62), 0x00 },
	{ CCI_REG8(0x72), 0x8f },
	{ CCI_REG8(0x73), 0x89 },
	{ CCI_REG8(0x7a), 0x05 },
	{ CCI_REG8(0x7d), 0xcc },
	{ CCI_REG8(0x90), 0x00 },
	{ CCI_REG8(0xce), 0x18 },
	{ CCI_REG8(0xd0), 0xb2 },
	{ CCI_REG8(0xd2), 0x40 },
	{ CCI_REG8(0xe6), 0xe0 },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x12), 0x01 },
	{ CCI_REG8(0x13), 0x01 },
	{ CCI_REG8(0x14), 0x01 },
	{ CCI_REG8(0x15), 0x02 },
	{ CCI_REG8(0x22), 0x7c },
	{ CCI_REG8(0x91), 0x00 },
	{ CCI_REG8(0x92), 0x00 },
	{ CCI_REG8(0x93), 0x00 },
	{ CCI_REG8(0x94), 0x00 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x88 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x8e },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x88 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x8e },
	/* Gain */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xb0), 0x6e },
	{ CCI_REG8(0xb1), 0x01 },
	{ CCI_REG8(0xb2), 0x00 },
	{ CCI_REG8(0xb3), 0x00 },
	{ CCI_REG8(0xb4), 0x00 },
	{ CCI_REG8(0xb6), 0x00 },
	/* ISP */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x53), 0x00 },
	{ CCI_REG8(0x89), 0x03 },
	{ CCI_REG8(0x60), 0x40 },
	/* BLK */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x42), 0x21 },
	{ CCI_REG8(0x49), 0x03 },
	{ CCI_REG8(0x4a), 0xff },
	{ CCI_REG8(0x4b), 0xc0 },
	{ CCI_REG8(0x55), 0x00 },
	/* Anti_blooming */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x41), 0x28 },
	{ CCI_REG8(0x4c), 0x00 },
	{ CCI_REG8(0x4d), 0x00 },
	{ CCI_REG8(0x4e), 0x3c },
	{ CCI_REG8(0x44), 0x08 },
	{ CCI_REG8(0x48), 0x02 },
	/* Crop */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x91), 0x00 },
	{ CCI_REG8(0x92), 0x08 },
	{ CCI_REG8(0x93), 0x00 },
	{ CCI_REG8(0x94), 0x07 },
	{ CCI_REG8(0x95), 0x07 },
	{ CCI_REG8(0x96), 0x98 },
	{ CCI_REG8(0x97), 0x0a },
	{ CCI_REG8(0x98), 0x20 },
	{ CCI_REG8(0x99), 0x00 },
	/* MIPI */
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x02), 0x57 },
	{ CCI_REG8(0x03), 0xb7 },
	{ CCI_REG8(0x15), 0x14 },
	{ CCI_REG8(0x18), 0x0f },
	{ CCI_REG8(0x21), 0x22 },
	{ CCI_REG8(0x22), 0x06 },
	{ CCI_REG8(0x23), 0x48 },
	{ CCI_REG8(0x24), 0x12 },
	{ CCI_REG8(0x25), 0x28 },
	{ CCI_REG8(0x26), 0x08 },
	{ CCI_REG8(0x29), 0x06 },
	{ CCI_REG8(0x2a), 0x58 },
	{ CCI_REG8(0x2b), 0x08 },
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x8c), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x3e), 0x01 },
};

static const struct cci_reg_sequence gc5035_mode_2592x1944[] = {
	/* System */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x3e), 0x01 },
	{ CCI_REG8(0xfc), 0x01 },
	{ CCI_REG8(0xf4), 0x40 },
	{ CCI_REG8(0xf5), 0xe9 },
	{ CCI_REG8(0xf6), 0x14 },
	{ CCI_REG8(0xf8), 0x58 },
	{ CCI_REG8(0xf9), 0x82 },
	{ CCI_REG8(0xfa), 0x00 },
	{ CCI_REG8(0xfc), 0x81 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x36), 0x01 },
	{ CCI_REG8(0xd3), 0x87 },
	{ CCI_REG8(0x36), 0x00 },
	{ CCI_REG8(0x33), 0x00 },
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x01), 0xe7 },
	{ CCI_REG8(0xf7), 0x01 },
	{ CCI_REG8(0xfc), 0x8f },
	{ CCI_REG8(0xfc), 0x8f },
	{ CCI_REG8(0xfc), 0x8e },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xee), 0x30 },
	{ CCI_REG8(0x87), 0x18 },
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x8c), 0x90 },
	{ CCI_REG8(0xfe), 0x00 },
	/* Analog & CISCTL */
	{ CCI_REG8(0x03), 0x03 },
	{ CCI_REG8(0x04), 0xd8 },
	{ CCI_REG8(0x41), 0x07 },
	{ CCI_REG8(0x42), 0xd8 },
	{ CCI_REG8(0x05), 0x02 },
	{ CCI_REG8(0x06), 0xda },
	{ CCI_REG8(0x9d), 0x18 },
	{ CCI_REG8(0x09), 0x00 },
	{ CCI_REG8(0x0a), 0x04 },
	{ CCI_REG8(0x0b), 0x00 },
	{ CCI_REG8(0x0c), 0x03 },
	{ CCI_REG8(0x0d), 0x07 },
	{ CCI_REG8(0x0e), 0xa8 },
	{ CCI_REG8(0x0f), 0x0a },
	{ CCI_REG8(0x10), 0x30 },
	{ CCI_REG8(0x11), 0x02 },
	{ CCI_REG8(0x17), 0x80 },
	{ CCI_REG8(0x19), 0x05 },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x30), 0x03 },
	{ CCI_REG8(0x31), 0x03 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xd9), 0xc0 },
	{ CCI_REG8(0x1b), 0x20 },
	{ CCI_REG8(0x21), 0x40 },
	{ CCI_REG8(0x28), 0x22 },
	{ CCI_REG8(0x29), 0x56 },
	{ CCI_REG8(0x44), 0x20 },
	{ CCI_REG8(0x4b), 0x10 },
	{ CCI_REG8(0x4e), 0x1a },
	{ CCI_REG8(0x50), 0x11 },
	{ CCI_REG8(0x52), 0x33 },
	{ CCI_REG8(0x53), 0x44 },
	{ CCI_REG8(0x55), 0x10 },
	{ CCI_REG8(0x5b), 0x11 },
	{ CCI_REG8(0xc5), 0x02 },
	{ CCI_REG8(0x8c), 0x1a },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x33), 0x05 },
	{ CCI_REG8(0x32), 0x38 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x91), 0x80 },
	{ CCI_REG8(0x92), 0x28 },
	{ CCI_REG8(0x93), 0x20 },
	{ CCI_REG8(0x95), 0xa0 },
	{ CCI_REG8(0x96), 0xe0 },
	{ CCI_REG8(0xd5), 0xfc },
	{ CCI_REG8(0x97), 0x28 },
	{ CCI_REG8(0x16), 0x0c },
	{ CCI_REG8(0x1a), 0x1a },
	{ CCI_REG8(0x1f), 0x11 },
	{ CCI_REG8(0x20), 0x10 },
	{ CCI_REG8(0x46), 0x83 },
	{ CCI_REG8(0x4a), 0x04 },
	{ CCI_REG8(0x54), 0x02 },
	{ CCI_REG8(0x62), 0x00 },
	{ CCI_REG8(0x72), 0x8f },
	{ CCI_REG8(0x73), 0x89 },
	{ CCI_REG8(0x7a), 0x05 },
	{ CCI_REG8(0x7d), 0xcc },
	{ CCI_REG8(0x90), 0x00 },
	{ CCI_REG8(0xce), 0x18 },
	{ CCI_REG8(0xd0), 0xb2 },
	{ CCI_REG8(0xd2), 0x40 },
	{ CCI_REG8(0xe6), 0xe0 },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x12), 0x01 },
	{ CCI_REG8(0x13), 0x01 },
	{ CCI_REG8(0x14), 0x01 },
	{ CCI_REG8(0x15), 0x02 },
	{ CCI_REG8(0x22), 0x7c },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x88 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x8e },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x88 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfc), 0x8e },
	/* GAIN */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xb0), 0x6e },
	{ CCI_REG8(0xb1), 0x01 },
	{ CCI_REG8(0xb2), 0x00 },
	{ CCI_REG8(0xb3), 0x00 },
	{ CCI_REG8(0xb4), 0x00 },
	{ CCI_REG8(0xb6), 0x00 },
	/* ISP */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x53), 0x00 },
	{ CCI_REG8(0x89), 0x03 },
	{ CCI_REG8(0x60), 0x40 },
	/* BLK */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x42), 0x21 },
	{ CCI_REG8(0x49), 0x03 },
	{ CCI_REG8(0x4a), 0xff },
	{ CCI_REG8(0x4b), 0xc0 },
	{ CCI_REG8(0x55), 0x00 },
	/* anti_blooming */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x41), 0x28 },
	{ CCI_REG8(0x4c), 0x00 },
	{ CCI_REG8(0x4d), 0x00 },
	{ CCI_REG8(0x4e), 0x3c },
	{ CCI_REG8(0x44), 0x08 },
	{ CCI_REG8(0x48), 0x02 },
	/* CROP */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x91), 0x00 },
	{ CCI_REG8(0x92), 0x08 },
	{ CCI_REG8(0x93), 0x00 },
	{ CCI_REG8(0x94), 0x08 },
	{ CCI_REG8(0x95), 0x07 },
	{ CCI_REG8(0x96), 0x98 },
	{ CCI_REG8(0x97), 0x0a },
	{ CCI_REG8(0x98), 0x20 },
	{ CCI_REG8(0x99), 0x00 },
	/* MIPI */
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x02), 0x57 },
	{ CCI_REG8(0x03), 0xb7 },
	{ CCI_REG8(0x15), 0x14 },
	{ CCI_REG8(0x18), 0x0f },
	{ CCI_REG8(0x21), 0x22 },
	{ CCI_REG8(0x22), 0x06 },
	{ CCI_REG8(0x23), 0x48 },
	{ CCI_REG8(0x24), 0x12 },
	{ CCI_REG8(0x25), 0x28 },
	{ CCI_REG8(0x26), 0x08 },
	{ CCI_REG8(0x29), 0x06 },
	{ CCI_REG8(0x2a), 0x58 },
	{ CCI_REG8(0x2b), 0x08 },
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x8c), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x3e), 0x01 },
};

struct gc5035_mode {
	u32 width;
	u32 height;
	const struct gc5035_reg_list reg_list;

	u32 hts;
	u32 vts_def;
	u32 vts_min;
};

/*
 * Full resolution only. The binned modes of the Intel patch (1296x972 and
 * 1280x720) declare an hts of 1460 and 1896 but write the same line length of
 * 2920 into the registers, so the HBLANK they would expose is wrong. They can
 * only be added once the real register values have been checked on hardware.
 */
static const struct gc5035_mode gc5035_modes[] = {
	{
		.width = GC5035_NATIVE_WIDTH,
		.height = GC5035_NATIVE_HEIGHT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(gc5035_mode_2592x1944),
			.regs = gc5035_mode_2592x1944,
		},
		.hts = 2920,
		.vts_def = 2008,
		.vts_min = 2008,
	},
};

static inline struct gc5035 *to_gc5035(struct v4l2_subdev *sd)
{
	return container_of(sd, struct gc5035, sd);
}

static int gc5035_set_page(struct gc5035 *gc5035, u8 page)
{
	return cci_write(gc5035->regmap, GC5035_REG_PAGE_SELECT, page, NULL);
}

static int gc5035_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc5035 *gc5035 = to_gc5035(sd);
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(gc5035_supply_name),
				    gc5035->supplies);
	if (ret < 0)
		return dev_err_probe(dev, ret, "failed to enable regulators\n");

	ret = clk_prepare_enable(gc5035->xclk);
	if (ret < 0) {
		regulator_bulk_disable(ARRAY_SIZE(gc5035_supply_name),
				       gc5035->supplies);
		return dev_err_probe(dev, ret, "failed to enable clock\n");
	}

	fsleep(GC5035_SLEEP_US);

	gpiod_set_value_cansleep(gc5035->powerdown_gpio, 0);
	gpiod_set_value_cansleep(gc5035->reset_gpio, 0);

	fsleep(GC5035_SLEEP_US);

	return 0;
}

static int gc5035_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc5035 *gc5035 = to_gc5035(sd);

	/*
	 * Reverse order compared to gc05a2: on INT3472 the clock is often a
	 * gpio gated clock which doubles as the module enable, so it has to be
	 * switched off after reset and powerdown have been asserted.
	 */
	gpiod_set_value_cansleep(gc5035->reset_gpio, 1);
	gpiod_set_value_cansleep(gc5035->powerdown_gpio, 1);
	clk_disable_unprepare(gc5035->xclk);
	regulator_bulk_disable(ARRAY_SIZE(gc5035_supply_name),
			       gc5035->supplies);

	return 0;
}

static int gc5035_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;

	code->code = GC5035_MBUS_CODE;

	return 0;
}

static int gc5035_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->code != GC5035_MBUS_CODE)
		return -EINVAL;

	if (fse->index >= ARRAY_SIZE(gc5035_modes))
		return -EINVAL;

	fse->min_width = gc5035_modes[fse->index].width;
	fse->max_width = gc5035_modes[fse->index].width;
	fse->min_height = gc5035_modes[fse->index].height;
	fse->max_height = gc5035_modes[fse->index].height;

	return 0;
}

static void gc5035_update_pad_format(const struct gc5035_mode *mode,
				     struct v4l2_mbus_framefmt *fmt)
{
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = GC5035_MBUS_CODE;
	fmt->field = V4L2_FIELD_NONE;
	fmt->colorspace = V4L2_COLORSPACE_RAW;
	fmt->ycbcr_enc = V4L2_MAP_YCBCR_ENC_DEFAULT(fmt->colorspace);
	fmt->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	fmt->xfer_func = V4L2_XFER_FUNC_NONE;
}

/*
 * Documentation/driver-api/media/tx-rx.rst:
 *   pixel_rate = link_freq * 2 * nr_lanes * 16 / k / bpp, k = 16 for D-PHY
 * that is, link_freq * 2 * lanes / bpp.
 *
 * Cross checked against the mode timing, which is the constraint that really
 * matters because V4L2_CID_PIXEL_RATE is used together with HBLANK and VBLANK
 * to compute the frame interval:
 *   hts * vts * fps = 2920 * 2008 * 30 = 175.9 MHz
 *   link_freq * 2 * lanes / bpp = 438e6 * 2 * 2 / 10 = 175.2 MHz
 * The two agree, so the bus formula is usable here.
 */
static u64 gc5035_to_pixel_rate(struct gc5035 *gc5035, u32 f_index)
{
	u64 pixel_rate = gc5035_link_freq_menu_items[f_index] * 2 *
			 gc5035->data_lanes;

	return div_u64(pixel_rate, GC5035_RGB_DEPTH);
}

static int gc5035_update_cur_mode_controls(struct gc5035 *gc5035,
					   const struct gc5035_mode *mode)
{
	s64 exposure_max, h_blank;
	int ret;

	ret = __v4l2_ctrl_modify_range(gc5035->vblank,
				       mode->vts_min - mode->height,
				       GC5035_VTS_MAX - mode->height, 1,
				       mode->vts_def - mode->height);
	if (ret)
		return ret;

	h_blank = mode->hts - mode->width;
	ret = __v4l2_ctrl_modify_range(gc5035->hblank, h_blank, h_blank, 1,
				       h_blank);
	if (ret)
		return ret;

	exposure_max = mode->vts_def - GC5035_EXP_MARGIN;

	return __v4l2_ctrl_modify_range(gc5035->exposure, GC5035_EXP_MIN,
					exposure_max, GC5035_EXP_STEP,
					exposure_max);
}

static int gc5035_set_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *fmt)
{
	struct gc5035 *gc5035 = to_gc5035(sd);
	struct v4l2_mbus_framefmt *mbus_fmt;
	const struct gc5035_mode *mode;
	struct v4l2_rect *crop;

	mode = v4l2_find_nearest_size(gc5035_modes, ARRAY_SIZE(gc5035_modes),
				      width, height, fmt->format.width,
				      fmt->format.height);

	crop = v4l2_subdev_state_get_crop(state, 0);
	crop->width = mode->width;
	crop->height = mode->height;

	gc5035_update_pad_format(mode, &fmt->format);
	mbus_fmt = v4l2_subdev_state_get_format(state, 0);
	*mbus_fmt = fmt->format;

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		return 0;

	gc5035->cur_mode = mode;

	return gc5035_update_cur_mode_controls(gc5035, mode);
}

static int gc5035_get_selection(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *state,
				struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP:
		sel->r = *v4l2_subdev_state_get_crop(state, 0);
		break;
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.top = 0;
		sel->r.left = 0;
		sel->r.width = GC5035_NATIVE_WIDTH;
		sel->r.height = GC5035_NATIVE_HEIGHT;
		break;
	default:
		return -EINVAL;
	}

	return 0;
}

static int gc5035_init_state(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state)
{
	struct v4l2_subdev_format fmt = {
		.which = V4L2_SUBDEV_FORMAT_TRY,
		.pad = 0,
		.format = {
			.code = GC5035_MBUS_CODE,
			.width = gc5035_modes[0].width,
			.height = gc5035_modes[0].height,
		},
	};

	return gc5035_set_format(sd, state, &fmt);
}

static int gc5035_test_pattern(struct gc5035 *gc5035, u32 pattern)
{
	int ret;

	ret = gc5035_set_page(gc5035, GC5035_PAGE_1);
	if (ret)
		return ret;

	ret = cci_write(gc5035->regmap, GC5035_REG_TEST_PATTERN,
			pattern ? GC5035_TEST_PATTERN_ON :
				  GC5035_TEST_PATTERN_OFF, NULL);
	if (ret)
		return ret;

	return gc5035_set_page(gc5035, GC5035_PAGE_0);
}

/*
 * Pick the highest analogue gain entry that does not exceed the requested
 * value, and compensate the remainder digitally:
 *
 *     dgain = 256 * a_gain / again_level[idx][0]
 *
 * The vendor code scales this by a further ratio read from the sensor OTP.
 * This driver does not read the OTP, so that ratio is unity here.
 */
static int gc5035_set_analogue_gain(struct gc5035 *gc5035, u32 a_gain)
{
	unsigned int idx;
	u32 dgain;
	int ret = 0;

	for (idx = ARRAY_SIZE(gc5035_again_level) - 1; idx > 0; idx--) {
		if (a_gain >= gc5035_again_level[idx][0])
			break;
	}

	dgain = DIV_ROUND_CLOSEST(GC5035_DGAIN_UNITY * a_gain,
				  gc5035_again_level[idx][0]);

	cci_write(gc5035->regmap, GC5035_REG_ANALOGUE_GAIN,
		  gc5035_again_level[idx][1], &ret);
	cci_write(gc5035->regmap, GC5035_REG_DIGITAL_GAIN_INT,
		  (dgain >> 8) & 0x0f, &ret);
	/*
	 * The low two bits of the fractional part are not implemented in the
	 * sensor, the vendor code masks them off.
	 */
	cci_write(gc5035->regmap, GC5035_REG_DIGITAL_GAIN_FRAC,
		  dgain & 0xfc, &ret);

	return ret;
}

static int gc5035_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct gc5035 *gc5035 =
		container_of(ctrl->handler, struct gc5035, ctrls);
	s64 exposure_max;
	int ret = 0;

	if (ctrl->id == V4L2_CID_VBLANK) {
		exposure_max = gc5035->cur_mode->height + ctrl->val -
			       GC5035_EXP_MARGIN;
		ret = __v4l2_ctrl_modify_range(gc5035->exposure,
					       GC5035_EXP_MIN, exposure_max,
					       GC5035_EXP_STEP, exposure_max);
		if (ret)
			return ret;
	}

	if (!pm_runtime_get_if_active(gc5035->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		ret = cci_write(gc5035->regmap, GC5035_REG_EXPOSURE,
				ctrl->val, NULL);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		ret = gc5035_set_analogue_gain(gc5035, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		ret = cci_write(gc5035->regmap, GC5035_REG_FRAME_LENGTH,
				gc5035->cur_mode->height + ctrl->val, NULL);
		break;
	case V4L2_CID_TEST_PATTERN:
		ret = gc5035_test_pattern(gc5035, ctrl->val);
		break;
	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(gc5035->dev);

	return ret;
}

static const struct v4l2_ctrl_ops gc5035_ctrl_ops = {
	.s_ctrl = gc5035_set_ctrl,
};

static int gc5035_identify_module(struct gc5035 *gc5035)
{
	u64 val;
	int ret;

	if (gc5035->identified)
		return 0;

	ret = cci_read(gc5035->regmap, GC5035_REG_CHIP_ID, &val, NULL);
	if (ret)
		return ret;

	if (val != GC5035_CHIP_ID)
		return dev_err_probe(gc5035->dev, -ENXIO,
				     "chip id mismatch: %x != %llx\n",
				     GC5035_CHIP_ID, val);

	gc5035->identified = true;

	return 0;
}

static int gc5035_enable_streams(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state,
				 u32 pad, u64 streams_mask)
{
	struct gc5035 *gc5035 = to_gc5035(sd);
	const struct gc5035_reg_list *reg_list;
	int ret;

	ret = pm_runtime_resume_and_get(gc5035->dev);
	if (ret < 0)
		return ret;

	ret = gc5035_identify_module(gc5035);
	if (ret)
		goto err_rpm_put;

	reg_list = &gc5035->cur_mode->reg_list;

	cci_write(gc5035->regmap, GC5035_REG_PAGE_SELECT, GC5035_PAGE_0, &ret);
	cci_multi_reg_write(gc5035->regmap, gc5035_init_regs,
			    ARRAY_SIZE(gc5035_init_regs), &ret);
	cci_multi_reg_write(gc5035->regmap, reg_list->regs,
			    reg_list->num_of_regs, &ret);
	if (ret)
		goto err_rpm_put;

	ret = __v4l2_ctrl_handler_setup(&gc5035->ctrls);
	if (ret)
		goto err_rpm_put;

	ret = cci_write(gc5035->regmap, GC5035_REG_STREAM,
			GC5035_STREAM_ON, NULL);
	if (ret)
		goto err_rpm_put;

	return 0;

err_rpm_put:
	pm_runtime_put(gc5035->dev);

	return ret;
}

static int gc5035_disable_streams(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *state,
				  u32 pad, u64 streams_mask)
{
	struct gc5035 *gc5035 = to_gc5035(sd);
	int ret;

	ret = cci_write(gc5035->regmap, GC5035_REG_STREAM,
			GC5035_STREAM_OFF, NULL);

	pm_runtime_put(gc5035->dev);

	return ret;
}

static const struct v4l2_subdev_video_ops gc5035_video_ops = {
	.s_stream = v4l2_subdev_s_stream_helper,
};

static const struct v4l2_subdev_pad_ops gc5035_pad_ops = {
	.enum_mbus_code = gc5035_enum_mbus_code,
	.enum_frame_size = gc5035_enum_frame_size,
	.get_fmt = v4l2_subdev_get_fmt,
	.set_fmt = gc5035_set_format,
	.get_selection = gc5035_get_selection,
	.enable_streams = gc5035_enable_streams,
	.disable_streams = gc5035_disable_streams,
};

static const struct v4l2_subdev_ops gc5035_subdev_ops = {
	.video = &gc5035_video_ops,
	.pad = &gc5035_pad_ops,
};

static const struct v4l2_subdev_internal_ops gc5035_internal_ops = {
	.init_state = gc5035_init_state,
};

static int gc5035_parse_fwnode(struct gc5035 *gc5035)
{
	struct v4l2_fwnode_endpoint bus_cfg = {
		.bus_type = V4L2_MBUS_CSI2_DPHY,
	};
	struct device *dev = gc5035->dev;
	struct fwnode_handle *endpoint;
	int ret;

	/*
	 * On IPU6 this graph does not come from ACPI: ipu-bridge synthesises
	 * it, but only for the HIDs listed in ipu_supported_sensors[].
	 *
	 * -EPROBE_DEFER rather than -EINVAL: the sensor can probe before
	 * ipu-bridge has built the graph. Failing here for good would make the
	 * driver unloadable over a pure probe ordering question. This is the
	 * same remedy ov2680 uses on x86.
	 */
	endpoint = fwnode_graph_get_endpoint_by_id(dev_fwnode(dev), 0, 0,
						   FWNODE_GRAPH_ENDPOINT_NEXT);
	if (!endpoint)
		return dev_err_probe(dev, -EPROBE_DEFER,
				     "waiting for endpoint node\n");

	ret = v4l2_fwnode_endpoint_alloc_parse(endpoint, &bus_cfg);
	if (ret) {
		dev_err_probe(dev, ret, "failed to parse endpoint\n");
		goto done;
	}

	/*
	 * The register tables configure the page 3 MIPI block for a fixed lane
	 * count, so any value cannot be accepted here: check that firmware
	 * declares the one the tables are written for. The count is then kept
	 * and used for the pixel rate computation rather than being folded
	 * into a constant.
	 */
	if (bus_cfg.bus.mipi_csi2.num_data_lanes != GC5035_DATA_LANES) {
		ret = dev_err_probe(dev, -EINVAL,
				    "unsupported number of data lanes %u\n",
				    bus_cfg.bus.mipi_csi2.num_data_lanes);
		goto done;
	}

	gc5035->data_lanes = bus_cfg.bus.mipi_csi2.num_data_lanes;

	ret = v4l2_link_freq_to_bitmap(dev, bus_cfg.link_frequencies,
				       bus_cfg.nr_of_link_frequencies,
				       gc5035_link_freq_menu_items,
				       ARRAY_SIZE(gc5035_link_freq_menu_items),
				       &gc5035->link_freq_bitmap);

done:
	v4l2_fwnode_endpoint_free(&bus_cfg);
	fwnode_handle_put(endpoint);

	return ret;
}

static int gc5035_init_controls(struct gc5035 *gc5035)
{
	struct i2c_client *client = v4l2_get_subdevdata(&gc5035->sd);
	const struct gc5035_mode *mode = &gc5035_modes[0];
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl_handler *ctrl_hdlr;
	s64 exposure_max, h_blank;
	int ret;

	ctrl_hdlr = &gc5035->ctrls;
	ret = v4l2_ctrl_handler_init(ctrl_hdlr, 8);
	if (ret)
		return ret;

	gc5035->link_freq =
		v4l2_ctrl_new_int_menu(ctrl_hdlr, &gc5035_ctrl_ops,
				       V4L2_CID_LINK_FREQ,
				       ARRAY_SIZE(gc5035_link_freq_menu_items)
				       - 1,
				       0, gc5035_link_freq_menu_items);
	if (gc5035->link_freq)
		gc5035->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	gc5035->pixel_rate =
		v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops,
				  V4L2_CID_PIXEL_RATE, 0,
				  gc5035_to_pixel_rate(gc5035, 0), 1,
				  gc5035_to_pixel_rate(gc5035, 0));
	if (gc5035->pixel_rate)
		gc5035->pixel_rate->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	gc5035->vblank =
		v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops, V4L2_CID_VBLANK,
				  mode->vts_min - mode->height,
				  GC5035_VTS_MAX - mode->height, 1,
				  mode->vts_def - mode->height);

	h_blank = mode->hts - mode->width;
	gc5035->hblank = v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops,
					   V4L2_CID_HBLANK, h_blank, h_blank,
					   1, h_blank);
	if (gc5035->hblank)
		gc5035->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	exposure_max = mode->vts_def - GC5035_EXP_MARGIN;
	gc5035->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops,
					     V4L2_CID_EXPOSURE, GC5035_EXP_MIN,
					     exposure_max, GC5035_EXP_STEP,
					     exposure_max);

	v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			  GC5035_AGAIN_MIN, GC5035_AGAIN_MAX, 1,
			  GC5035_AGAIN_MIN);

	v4l2_ctrl_new_std_menu_items(ctrl_hdlr, &gc5035_ctrl_ops,
				     V4L2_CID_TEST_PATTERN,
				     ARRAY_SIZE(gc5035_test_pattern_menu) - 1,
				     0, 0, gc5035_test_pattern_menu);

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		goto error_ctrls;

	ret = v4l2_ctrl_new_fwnode_properties(ctrl_hdlr, &gc5035_ctrl_ops,
					      &props);
	if (ret)
		goto error_ctrls;

	if (ctrl_hdlr->error) {
		ret = ctrl_hdlr->error;
		goto error_ctrls;
	}

	gc5035->sd.ctrl_handler = ctrl_hdlr;

	return 0;

error_ctrls:
	v4l2_ctrl_handler_free(ctrl_hdlr);

	return ret;
}

static int gc5035_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct gc5035 *gc5035;
	unsigned long freq;
	unsigned int i;
	int ret;

	gc5035 = devm_kzalloc(dev, sizeof(*gc5035), GFP_KERNEL);
	if (!gc5035)
		return -ENOMEM;

	gc5035->dev = dev;

	v4l2_i2c_subdev_init(&gc5035->sd, client, &gc5035_subdev_ops);
	gc5035->sd.internal_ops = &gc5035_internal_ops;

	ret = gc5035_parse_fwnode(gc5035);
	if (ret)
		return ret;

	gc5035->regmap = devm_cci_regmap_init_i2c(client, 8);
	if (IS_ERR(gc5035->regmap))
		return dev_err_probe(dev, PTR_ERR(gc5035->regmap),
				     "failed to init CCI\n");

	/*
	 * On x86 these are provided by INT3472 and either of them may be
	 * absent. On the machine this was developed against, firmware
	 * describes two GPIOs for this sensor: a RESET (type 0x00) and a
	 * POWER_ENABLE (type 0x0b), the latter surfacing as a regulator
	 * rather than as a GPIO. No powerdown pin is described, hence
	 * _optional on both.
	 */
	gc5035->reset_gpio = devm_gpiod_get_optional(dev, "reset",
						     GPIOD_OUT_HIGH);
	if (IS_ERR(gc5035->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(gc5035->reset_gpio),
				     "failed to get reset GPIO\n");

	gc5035->powerdown_gpio = devm_gpiod_get_optional(dev, "powerdown",
							 GPIOD_OUT_HIGH);
	if (IS_ERR(gc5035->powerdown_gpio))
		return dev_err_probe(dev, PTR_ERR(gc5035->powerdown_gpio),
				     "failed to get powerdown GPIO\n");

	gc5035->xclk = devm_v4l2_sensor_clk_get(dev, "clk");
	if (IS_ERR(gc5035->xclk))
		return dev_err_probe(dev, PTR_ERR(gc5035->xclk),
				     "failed to get clock\n");

	freq = clk_get_rate(gc5035->xclk);
	if (freq != GC5035_MCLK_DEFAULT)
		dev_warn(dev, "external clock %lu, expected %lu\n", freq,
			 (unsigned long)GC5035_MCLK_DEFAULT);

	for (i = 0; i < ARRAY_SIZE(gc5035_supply_name); i++)
		gc5035->supplies[i].supply = gc5035_supply_name[i];

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(gc5035_supply_name),
				      gc5035->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	gc5035->cur_mode = &gc5035_modes[0];

	ret = gc5035_init_controls(gc5035);
	if (ret)
		return dev_err_probe(dev, ret, "failed to init controls\n");

	gc5035->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	gc5035->pad.flags = MEDIA_PAD_FL_SOURCE;
	gc5035->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;

	ret = media_entity_pads_init(&gc5035->sd.entity, 1, &gc5035->pad);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to init media entity\n");
		goto err_ctrl_handler_free;
	}

	gc5035->sd.state_lock = gc5035->ctrls.lock;
	ret = v4l2_subdev_init_finalize(&gc5035->sd);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to finalize subdev\n");
		goto err_media_entity_cleanup;
	}

	pm_runtime_enable(dev);
	pm_runtime_set_autosuspend_delay(dev, 1000);
	pm_runtime_use_autosuspend(dev);
	pm_runtime_idle(dev);

	ret = v4l2_async_register_subdev_sensor(&gc5035->sd);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to register subdev\n");
		goto err_rpm;
	}

	return 0;

err_rpm:
	pm_runtime_disable(dev);
	v4l2_subdev_cleanup(&gc5035->sd);

err_media_entity_cleanup:
	media_entity_cleanup(&gc5035->sd.entity);

err_ctrl_handler_free:
	v4l2_ctrl_handler_free(&gc5035->ctrls);

	return ret;
}

static void gc5035_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct gc5035 *gc5035 = to_gc5035(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&gc5035->ctrls);

	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		gc5035_power_off(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	pm_runtime_dont_use_autosuspend(&client->dev);
}

static DEFINE_RUNTIME_DEV_PM_OPS(gc5035_pm_ops, gc5035_power_off,
				 gc5035_power_on, NULL);

static const struct acpi_device_id gc5035_acpi_ids[] = {
	{ "GCTI5035" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, gc5035_acpi_ids);

static const struct of_device_id gc5035_of_match[] = {
	{ .compatible = "galaxycore,gc5035" },
	{ }
};
MODULE_DEVICE_TABLE(of, gc5035_of_match);

static struct i2c_driver gc5035_i2c_driver = {
	.driver = {
		.name = "gc5035",
		.acpi_match_table = gc5035_acpi_ids,
		.of_match_table = gc5035_of_match,
		.pm = pm_ptr(&gc5035_pm_ops),
	},
	.probe = gc5035_probe,
	.remove = gc5035_remove,
};
module_i2c_driver(gc5035_i2c_driver);

MODULE_DESCRIPTION("GalaxyCore GC5035 sensor driver");
MODULE_LICENSE("GPL");

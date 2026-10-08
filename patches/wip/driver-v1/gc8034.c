// SPDX-License-Identifier: GPL-2.0
/*
 * Driver for GalaxyCore GC8034 image sensor
 *
 * Copyright (C) 2017 Fuzhou Rockchip Electronics Co., Ltd.
 * Copyright (C) 2026 Nicola Fiorillo <nicfio@gmail.com>
 *
 * The registers and sequences come from the Rockchip BSP driver,
 * rockchip-linux/kernel, branch develop-5.10.
 */
#include <linux/array_size.h>
#include <linux/build_bug.h>
#include <linux/clk.h>
#include <linux/container_of.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/math.h>
#include <linux/minmax.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/property.h>
#include <linux/regulator/consumer.h>
#include <linux/time64.h>
#include <linux/types.h>
#include <linux/units.h>

#include <media/v4l2-cci.h>
#include <media/v4l2-common.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

/* 8 bit register addresses, with the page selected by register 0xfe */
#define GC8034_REG_PAGE_SELECT		CCI_REG8(0xfe)
#define GC8034_PAGE_0			0x00

/* readable on any page */
#define GC8034_REG_CHIP_ID		CCI_REG16(0xf0)
#define GC8034_CHIP_ID			0x8044	/* not 0x8034 */

#define GC8034_REG_EXPOSURE		CCI_REG16(0x03)
#define GC8034_REG_ANALOGUE_GAIN	CCI_REG8(0xb6)
#define GC8034_REG_BLANKING		CCI_REG16(0x07)
#define GC8034_REG_STREAM		CCI_REG8(0x3f)
#define GC8034_STREAM_ON		0xd0
#define GC8034_STREAM_OFF		0x00

/*
 * The register tables read out a 3284x2464 window and crop 3264x2448 from it
 * at (9, 8). The size of the full pixel array is not documented, so the
 * readout window is reported as the native size.
 */
#define GC8034_NATIVE_WIDTH		3284
#define GC8034_NATIVE_HEIGHT		2464
#define GC8034_CROP_LEFT		9
#define GC8034_CROP_TOP			8
#define GC8034_WIDTH			3264
#define GC8034_HEIGHT			2448

/*
 * The blanking register holds the frame length minus the active height and
 * 36 lines, as computed by the vendor code.
 */
#define GC8034_VTS_OFFSET		(GC8034_HEIGHT + 36)
#define GC8034_VTS_MAX			0x1fff

/* The sensor only takes even exposure values. */
#define GC8034_EXP_MIN			4
#define GC8034_EXP_STEP			2
#define GC8034_EXP_MARGIN		4
#define GC8034_EXP_DEF			2246

/*
 * The register tables have only been tested with a 19.2 MHz external clock,
 * at which the link frequency is 268.8 MHz and the frame rate 24 fps. The PLL
 * settings are not documented, so the pixel rate is derived from the measured
 * frame rate.
 */
#define GC8034_XCLK_FREQ		(19200 * HZ_PER_KHZ)
#define GC8034_LINK_FREQ		(268800 * HZ_PER_KHZ)
#define GC8034_DATA_LANES		4
#define GC8034_HTS			4272
#define GC8034_VTS_DEF			2496
#define GC8034_PIXEL_RATE		(GC8034_HTS * GC8034_VTS_DEF * 24)

/*
 * No datasheet is available. The power sequence and delays follow the vendor
 * driver: supplies in the order of gc8034_supply_name, 100 us, clock, 1 ms,
 * powerdown released, 500 us, reset released, then 6 ms and 8192 clock cycles
 * before the first I2C access.
 */
#define GC8034_SUPPLY_DELAY_US		100
#define GC8034_CLK_DELAY_US		1000
#define GC8034_PWDN_DELAY_US		500
#define GC8034_RESET_DELAY_US		(6000 + \
					 DIV_ROUND_UP(8192 * USEC_PER_MSEC, \
						      GC8034_XCLK_FREQ / \
						      MSEC_PER_SEC))

#define GC8034_MBUS_CODE		MEDIA_BUS_FMT_SRGGB10_1X10

static const s64 gc8034_link_freq_menu[] = {
	GC8034_LINK_FREQ,
};

static const char * const gc8034_supply_name[] = {
	"dovdd",
	"dvdd",
	"avdd",
};

/*
 * V4L2_CID_ANALOGUE_GAIN is the value of register 0xb6, an index into this
 * table of gains in Q6 fixed point (64 is 1.0x). Only the seven entries the
 * vendor code uses are listed. The digital gain is left at the 1.0x the tables
 * program.
 */
static const u16 gc8034_again_level[] = {
	0x0040,	/*  1.000x */
	0x0058,	/*  1.375x */
	0x007d,	/*  1.950x */
	0x00ad,	/*  2.700x */
	0x00f3,	/*  3.800x */
	0x0159,	/*  5.400x */
	0x01ea,	/*  7.660x */
};

/*
 * Analogue bias registers rewritten for each gain index. The sequence selects
 * its own pages through register 0xfe.
 */
static const u8 gc8034_agc_bias_reg[] = {
	0xfe, 0x20, 0x33, 0xfe, 0xdf, 0xe7, 0xe8,
	0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xfe,
};

static const u8 gc8034_agc_bias[][ARRAY_SIZE(gc8034_agc_bias_reg)] = {
	{ 0x00, 0x55, 0x83, 0x01, 0x06, 0x18, 0x20,
	  0x16, 0x17, 0x50, 0x6c, 0x9b, 0xd8, 0x00 },
	{ 0x00, 0x55, 0x83, 0x01, 0x06, 0x18, 0x20,
	  0x16, 0x17, 0x50, 0x6c, 0x9b, 0xd8, 0x00 },
	{ 0x00, 0x4e, 0x84, 0x01, 0x0c, 0x2e, 0x2d,
	  0x15, 0x19, 0x47, 0x70, 0x9f, 0xd8, 0x00 },
	{ 0x00, 0x51, 0x80, 0x01, 0x07, 0x28, 0x32,
	  0x22, 0x20, 0x49, 0x70, 0x91, 0xd9, 0x00 },
	{ 0x00, 0x4d, 0x83, 0x01, 0x0f, 0x3b, 0x3b,
	  0x1c, 0x1f, 0x47, 0x6f, 0x9b, 0xd3, 0x00 },
	{ 0x00, 0x50, 0x83, 0x01, 0x08, 0x35, 0x46,
	  0x1e, 0x22, 0x4c, 0x70, 0x9a, 0xd2, 0x00 },
	{ 0x00, 0x52, 0x80, 0x01, 0x0c, 0x35, 0x3a,
	  0x2b, 0x2d, 0x4c, 0x67, 0x8d, 0xc0, 0x00 },
};

static_assert(ARRAY_SIZE(gc8034_agc_bias) == ARRAY_SIZE(gc8034_again_level));

struct gc8034 {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;

	struct clk *xclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(gc8034_supply_name)];
	struct gpio_desc *reset_gpio;
	struct gpio_desc *powerdown_gpio;

	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;

	struct regmap *regmap;
};

struct gc8034_reg_list {
	u32 num_of_regs;
	const struct cci_reg_sequence *regs;
};

/*
 * The register sequences are reproduced unmodified from the vendor code. No
 * register documentation is available for the PLL and CSI-2 settings.
 *
 * The vendor code keeps all four lane settings in one list. It is split here
 * at the point where its two lane lists separate global and mode settings.
 */
static const struct cci_reg_sequence gc8034_global_regs[] = {
	/* SYS */
	{ CCI_REG8(0xf2), 0x00 },
	{ CCI_REG8(0xf4), 0x80 },
	{ CCI_REG8(0xf5), 0x19 },
	{ CCI_REG8(0xf6), 0x44 },
	{ CCI_REG8(0xf8), 0x63 },
	{ CCI_REG8(0xfa), 0x45 },
	{ CCI_REG8(0xf9), 0x00 },
	{ CCI_REG8(0xf7), 0x9d },
	{ CCI_REG8(0xfc), 0x00 },
	{ CCI_REG8(0xfc), 0x00 },
	{ CCI_REG8(0xfc), 0xea },
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x03), 0x9a },
	{ CCI_REG8(0x18), 0x07 },
	{ CCI_REG8(0x01), 0x07 },
	{ CCI_REG8(0xfc), 0xee },
	/* Cisctl&Analog */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x03), 0x08 },
	{ CCI_REG8(0x04), 0xc6 },
	{ CCI_REG8(0x05), 0x02 },
	{ CCI_REG8(0x06), 0x16 },
	{ CCI_REG8(0x07), 0x00 },
	{ CCI_REG8(0x08), 0x10 },
	{ CCI_REG8(0x0a), 0x3a },
	{ CCI_REG8(0x0b), 0x00 },
	{ CCI_REG8(0x0c), 0x04 },
	{ CCI_REG8(0x0d), 0x09 },
	{ CCI_REG8(0x0e), 0xa0 },
	{ CCI_REG8(0x0f), 0x0c },
	{ CCI_REG8(0x10), 0xd4 },
	{ CCI_REG8(0x17), 0xc0 },
	{ CCI_REG8(0x18), 0x02 },
	{ CCI_REG8(0x19), 0x17 },
	{ CCI_REG8(0x1e), 0x50 },
	{ CCI_REG8(0x1f), 0x80 },
	{ CCI_REG8(0x21), 0x4c },
	{ CCI_REG8(0x25), 0x00 },
	{ CCI_REG8(0x28), 0x4a },
	{ CCI_REG8(0x2d), 0x89 },
	{ CCI_REG8(0xca), 0x02 },
	{ CCI_REG8(0xcb), 0x00 },
	{ CCI_REG8(0xcc), 0x39 },
	{ CCI_REG8(0xce), 0xd0 },
	{ CCI_REG8(0xcf), 0x93 },
	{ CCI_REG8(0xd0), 0x19 },
	{ CCI_REG8(0xd1), 0xaa },
	{ CCI_REG8(0xd2), 0xcb },
	{ CCI_REG8(0xd8), 0x40 },
	{ CCI_REG8(0xd9), 0xff },
	{ CCI_REG8(0xda), 0x0e },
	{ CCI_REG8(0xdb), 0xb0 },
	{ CCI_REG8(0xdc), 0x0e },
	{ CCI_REG8(0xde), 0x08 },
	{ CCI_REG8(0xe4), 0xc6 },
	{ CCI_REG8(0xe5), 0x08 },
	{ CCI_REG8(0xe6), 0x10 },
	{ CCI_REG8(0xed), 0x2a },
	{ CCI_REG8(0xfe), 0x02 },
	{ CCI_REG8(0x59), 0x02 },
	{ CCI_REG8(0x5a), 0x04 },
	{ CCI_REG8(0x5b), 0x08 },
	{ CCI_REG8(0x5c), 0x20 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x1a), 0x09 },
	{ CCI_REG8(0x1d), 0x13 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0xfe), 0x10 },
	{ CCI_REG8(0xfe), 0x00 },
	/* Gamma */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x20), 0x55 },
	{ CCI_REG8(0x33), 0x83 },
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0xdf), 0x06 },
	{ CCI_REG8(0xe7), 0x18 },
	{ CCI_REG8(0xe8), 0x20 },
	{ CCI_REG8(0xe9), 0x16 },
	{ CCI_REG8(0xea), 0x17 },
	{ CCI_REG8(0xeb), 0x50 },
	{ CCI_REG8(0xec), 0x6c },
	{ CCI_REG8(0xed), 0x9b },
	{ CCI_REG8(0xee), 0xd8 },
	/* ISP */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x80), 0x10 },
	{ CCI_REG8(0x84), 0x01 },
	{ CCI_REG8(0x88), 0x03 },
	{ CCI_REG8(0x89), 0x03 },
	{ CCI_REG8(0x8d), 0x03 },
	{ CCI_REG8(0x8f), 0x14 },
	{ CCI_REG8(0xad), 0x30 },
	{ CCI_REG8(0x66), 0x2c },
	{ CCI_REG8(0xbc), 0x49 },
	{ CCI_REG8(0xc2), 0x7f },
	{ CCI_REG8(0xc3), 0xff },
	/* Crop window */
	{ CCI_REG8(0x90), 0x01 },
	{ CCI_REG8(0x92), 0x08 },
	{ CCI_REG8(0x94), 0x09 },
	{ CCI_REG8(0x95), 0x04 },
	{ CCI_REG8(0x96), 0xc8 },
	{ CCI_REG8(0x97), 0x06 },
	{ CCI_REG8(0x98), 0x60 },
	/* Gain */
	{ CCI_REG8(0xb0), 0x90 },
	{ CCI_REG8(0xb1), 0x01 },
	{ CCI_REG8(0xb2), 0x00 },
	{ CCI_REG8(0xb6), 0x00 },
	/* BLK */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x40), 0x22 },
	{ CCI_REG8(0x41), 0x20 },
	{ CCI_REG8(0x42), 0x02 },
	{ CCI_REG8(0x43), 0x08 },
	{ CCI_REG8(0x4e), 0x0f },
	{ CCI_REG8(0x4f), 0xf0 },
	{ CCI_REG8(0x58), 0x80 },
	{ CCI_REG8(0x59), 0x80 },
	{ CCI_REG8(0x5a), 0x80 },
	{ CCI_REG8(0x5b), 0x80 },
	{ CCI_REG8(0x5c), 0x00 },
	{ CCI_REG8(0x5d), 0x00 },
	{ CCI_REG8(0x5e), 0x00 },
	{ CCI_REG8(0x5f), 0x00 },
	{ CCI_REG8(0x6b), 0x01 },
	{ CCI_REG8(0x6c), 0x00 },
	{ CCI_REG8(0x6d), 0x0c },
	/* WB offset */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0xbf), 0x40 },
	/* Dark Sun */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x68), 0x77 },
	/* DPC */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x60), 0x00 },
	{ CCI_REG8(0x61), 0x10 },
	{ CCI_REG8(0x62), 0x28 },
	{ CCI_REG8(0x63), 0x10 },
	{ CCI_REG8(0x64), 0x02 },
	/* LSC */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0xa8), 0x60 },
	{ CCI_REG8(0xa2), 0xd1 },
	{ CCI_REG8(0xc8), 0x57 },
	{ CCI_REG8(0xa1), 0xb8 },
	{ CCI_REG8(0xa3), 0x91 },
	{ CCI_REG8(0xc0), 0x50 },
	{ CCI_REG8(0xd0), 0x05 },
	{ CCI_REG8(0xd1), 0xb2 },
	{ CCI_REG8(0xd2), 0x1f },
	{ CCI_REG8(0xd3), 0x00 },
	{ CCI_REG8(0xd4), 0x00 },
	{ CCI_REG8(0xd5), 0x00 },
	{ CCI_REG8(0xd6), 0x00 },
	{ CCI_REG8(0xd7), 0x00 },
	{ CCI_REG8(0xd8), 0x00 },
	{ CCI_REG8(0xd9), 0x00 },
	{ CCI_REG8(0xa4), 0x10 },
	{ CCI_REG8(0xa5), 0x20 },
	{ CCI_REG8(0xa6), 0x60 },
	{ CCI_REG8(0xa7), 0x80 },
	{ CCI_REG8(0xab), 0x18 },
	{ CCI_REG8(0xc7), 0xc0 },
	/* ABB */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x20), 0x02 },
	{ CCI_REG8(0x21), 0x02 },
	{ CCI_REG8(0x23), 0x42 },
	/* MIPI */
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x02), 0x03 },
	{ CCI_REG8(0x04), 0x80 },
	{ CCI_REG8(0x11), 0x2b },
	{ CCI_REG8(0x12), 0xf8 },
	{ CCI_REG8(0x13), 0x07 },
	{ CCI_REG8(0x15), 0x10 },
	{ CCI_REG8(0x16), 0x29 },
	{ CCI_REG8(0x17), 0xff },
	{ CCI_REG8(0x19), 0xaa },
	{ CCI_REG8(0x1a), 0x02 },
	{ CCI_REG8(0x21), 0x02 },
	{ CCI_REG8(0x22), 0x03 },
	{ CCI_REG8(0x23), 0x0a },
	{ CCI_REG8(0x24), 0x00 },
	{ CCI_REG8(0x25), 0x12 },
	{ CCI_REG8(0x26), 0x04 },
	{ CCI_REG8(0x29), 0x04 },
	{ CCI_REG8(0x2a), 0x02 },
	{ CCI_REG8(0x2b), 0x04 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x3f), 0x00 },
};

static const struct cci_reg_sequence gc8034_mode_3264x2448[] = {
	/* SYS */
	{ CCI_REG8(0xf2), 0x00 },
	{ CCI_REG8(0xf4), 0x80 },
	{ CCI_REG8(0xf5), 0x19 },
	{ CCI_REG8(0xf6), 0x44 },
	{ CCI_REG8(0xf8), 0x63 },
	{ CCI_REG8(0xfa), 0x45 },
	{ CCI_REG8(0xf9), 0x00 },
	{ CCI_REG8(0xf7), 0x95 },
	{ CCI_REG8(0xfc), 0x00 },
	{ CCI_REG8(0xfc), 0x00 },
	{ CCI_REG8(0xfc), 0xea },
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x03), 0x9a },
	{ CCI_REG8(0x18), 0x07 },
	{ CCI_REG8(0x01), 0x07 },
	{ CCI_REG8(0xfc), 0xee },
	/* ISP */
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x80), 0x13 },
	{ CCI_REG8(0xad), 0x00 },
	/* Crop window */
	{ CCI_REG8(0x90), 0x01 },
	{ CCI_REG8(0x92), 0x08 },
	{ CCI_REG8(0x94), 0x09 },
	{ CCI_REG8(0x95), 0x09 },
	{ CCI_REG8(0x96), 0x90 },
	{ CCI_REG8(0x97), 0x0c },
	{ CCI_REG8(0x98), 0xc0 },
	/* DPC */
	{ CCI_REG8(0xfe), 0x01 },
	{ CCI_REG8(0x62), 0x60 },
	{ CCI_REG8(0x63), 0x48 },
	/* MIPI */
	{ CCI_REG8(0xfe), 0x03 },
	{ CCI_REG8(0x02), 0x03 },
	{ CCI_REG8(0x04), 0x80 },
	{ CCI_REG8(0x11), 0x2b },
	{ CCI_REG8(0x12), 0xf0 },
	{ CCI_REG8(0x13), 0x0f },
	{ CCI_REG8(0x15), 0x10 },
	{ CCI_REG8(0x16), 0x29 },
	{ CCI_REG8(0x17), 0xff },
	{ CCI_REG8(0x19), 0xaa },
	{ CCI_REG8(0x1a), 0x02 },
	{ CCI_REG8(0x21), 0x05 },
	{ CCI_REG8(0x22), 0x06 },
	{ CCI_REG8(0x23), 0x2b },
	{ CCI_REG8(0x24), 0x00 },
	{ CCI_REG8(0x25), 0x12 },
	{ CCI_REG8(0x26), 0x07 },
	{ CCI_REG8(0x29), 0x07 },
	{ CCI_REG8(0x2a), 0x12 },
	{ CCI_REG8(0x2b), 0x07 },
	{ CCI_REG8(0xfe), 0x00 },
	{ CCI_REG8(0x3f), 0x00 },
};

struct gc8034_mode {
	u32 width;
	u32 height;
	const struct gc8034_reg_list reg_list;

	u32 hts;
	u32 vts_def;
	u32 vts_min;
};

static const struct gc8034_mode gc8034_modes[] = {
	{
		.width = GC8034_WIDTH,
		.height = GC8034_HEIGHT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(gc8034_mode_3264x2448),
			.regs = gc8034_mode_3264x2448,
		},
		.hts = GC8034_HTS,
		.vts_def = GC8034_VTS_DEF,
		.vts_min = GC8034_VTS_DEF,
	},
};

static inline struct gc8034 *to_gc8034(struct v4l2_subdev *sd)
{
	return container_of(sd, struct gc8034, sd);
}

static void gc8034_disable_supplies(struct gc8034 *gc8034, unsigned int num)
{
	while (num--)
		regulator_disable(gc8034->supplies[num].consumer);
}

static int gc8034_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc8034 *gc8034 = to_gc8034(sd);
	unsigned int i;
	int ret;

	/* One by one: regulator_bulk_enable() works in parallel. */
	for (i = 0; i < ARRAY_SIZE(gc8034_supply_name); i++) {
		ret = regulator_enable(gc8034->supplies[i].consumer);
		if (ret) {
			dev_err(dev, "failed to enable %s: %d\n",
				gc8034_supply_name[i], ret);
			gc8034_disable_supplies(gc8034, i);
			return ret;
		}
	}

	fsleep(GC8034_SUPPLY_DELAY_US);

	ret = clk_prepare_enable(gc8034->xclk);
	if (ret) {
		dev_err(dev, "failed to enable clock: %d\n", ret);
		gc8034_disable_supplies(gc8034, ARRAY_SIZE(gc8034_supply_name));
		return ret;
	}

	fsleep(GC8034_CLK_DELAY_US);
	gpiod_set_value_cansleep(gc8034->powerdown_gpio, 0);
	fsleep(GC8034_PWDN_DELAY_US);
	gpiod_set_value_cansleep(gc8034->reset_gpio, 0);
	fsleep(GC8034_RESET_DELAY_US);

	return 0;
}

static int gc8034_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc8034 *gc8034 = to_gc8034(sd);

	gpiod_set_value_cansleep(gc8034->powerdown_gpio, 1);
	gpiod_set_value_cansleep(gc8034->reset_gpio, 1);
	clk_disable_unprepare(gc8034->xclk);
	gc8034_disable_supplies(gc8034, ARRAY_SIZE(gc8034_supply_name));

	return 0;
}

static int gc8034_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;

	code->code = GC8034_MBUS_CODE;

	return 0;
}

static int gc8034_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->code != GC8034_MBUS_CODE)
		return -EINVAL;

	if (fse->index >= ARRAY_SIZE(gc8034_modes))
		return -EINVAL;

	fse->min_width = gc8034_modes[fse->index].width;
	fse->max_width = gc8034_modes[fse->index].width;
	fse->min_height = gc8034_modes[fse->index].height;
	fse->max_height = gc8034_modes[fse->index].height;

	return 0;
}

static void gc8034_update_pad_format(const struct gc8034_mode *mode,
				     struct v4l2_mbus_framefmt *fmt)
{
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = GC8034_MBUS_CODE;
	fmt->field = V4L2_FIELD_NONE;
	fmt->colorspace = V4L2_COLORSPACE_RAW;
	fmt->ycbcr_enc = V4L2_MAP_YCBCR_ENC_DEFAULT(fmt->colorspace);
	fmt->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	fmt->xfer_func = V4L2_XFER_FUNC_NONE;
}

static int gc8034_set_format(struct v4l2_subdev *sd,
			     const struct v4l2_subdev_client_info *ci,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *fmt)
{
	struct v4l2_mbus_framefmt *mbus_fmt;
	const struct gc8034_mode *mode;
	struct v4l2_rect *crop;

	mode = v4l2_find_nearest_size(gc8034_modes, ARRAY_SIZE(gc8034_modes),
				      width, height, fmt->format.width,
				      fmt->format.height);

	crop = v4l2_subdev_state_get_crop(state, 0);
	crop->left = GC8034_CROP_LEFT;
	crop->top = GC8034_CROP_TOP;
	crop->width = mode->width;
	crop->height = mode->height;

	gc8034_update_pad_format(mode, &fmt->format);
	mbus_fmt = v4l2_subdev_state_get_format(state, 0);
	*mbus_fmt = fmt->format;

	return 0;
}

static int gc8034_get_selection(struct v4l2_subdev *sd,
				const struct v4l2_subdev_client_info *ci,
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
		sel->r.width = GC8034_NATIVE_WIDTH;
		sel->r.height = GC8034_NATIVE_HEIGHT;
		break;
	default:
		return -EINVAL;
	}

	return 0;
}

static int gc8034_init_state(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state)
{
	struct v4l2_subdev_format fmt = {
		.which = V4L2_SUBDEV_FORMAT_TRY,
		.pad = 0,
		.format = {
			.code = GC8034_MBUS_CODE,
			.width = gc8034_modes[0].width,
			.height = gc8034_modes[0].height,
		},
	};

	return gc8034_set_format(sd, NULL, state, &fmt);
}

static int gc8034_set_analogue_gain(struct gc8034 *gc8034, u32 idx)
{
	unsigned int i;
	int ret = 0;

	cci_write(gc8034->regmap, GC8034_REG_ANALOGUE_GAIN, idx, &ret);

	for (i = 0; i < ARRAY_SIZE(gc8034_agc_bias_reg); i++)
		cci_write(gc8034->regmap, CCI_REG8(gc8034_agc_bias_reg[i]),
			  gc8034_agc_bias[idx][i], &ret);

	return ret;
}

static int gc8034_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct gc8034 *gc8034 =
		container_of(ctrl->handler, struct gc8034, ctrls);
	const struct v4l2_mbus_framefmt *format;
	struct v4l2_subdev_state *state;
	s64 exposure_max, exposure_def;
	int ret;

	state = v4l2_subdev_get_locked_active_state(&gc8034->sd);
	format = v4l2_subdev_state_get_format(state, 0);

	if (ctrl->id == V4L2_CID_VBLANK) {
		exposure_max = round_down(format->height + ctrl->val -
					  GC8034_EXP_MARGIN, GC8034_EXP_STEP);
		exposure_def = min(GC8034_EXP_DEF, exposure_max);
		ret = __v4l2_ctrl_modify_range(gc8034->exposure,
					       GC8034_EXP_MIN, exposure_max,
					       GC8034_EXP_STEP, exposure_def);
		if (ret)
			return ret;
	}

	if (!pm_runtime_get_if_active(gc8034->dev))
		return 0;

	ret = cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0,
			NULL);
	if (ret)
		goto out;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		ret = cci_write(gc8034->regmap, GC8034_REG_EXPOSURE,
				ctrl->val, NULL);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		ret = gc8034_set_analogue_gain(gc8034, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		/* The register holds an offset, not the VTS. */
		ret = cci_write(gc8034->regmap, GC8034_REG_BLANKING,
				format->height + ctrl->val -
				GC8034_VTS_OFFSET, NULL);
		break;
	default:
		ret = -EINVAL;
		break;
	}

out:
	pm_runtime_put_autosuspend(gc8034->dev);

	return ret;
}

static const struct v4l2_ctrl_ops gc8034_ctrl_ops = {
	.s_ctrl = gc8034_set_ctrl,
};

/* Only ever called from probe, with the sensor powered up. */
static int gc8034_identify_module(struct gc8034 *gc8034)
{
	u64 val;
	int ret;

	ret = cci_read(gc8034->regmap, GC8034_REG_CHIP_ID, &val, NULL);
	if (ret)
		return dev_err_probe(gc8034->dev, ret,
				     "failed to read chip id\n");

	if (val != GC8034_CHIP_ID)
		return dev_err_probe(gc8034->dev, -ENXIO,
				     "chip id mismatch: %x != %llx\n",
				     GC8034_CHIP_ID, val);

	return 0;
}

static int gc8034_enable_streams(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state,
				 u32 pad, u64 streams_mask)
{
	struct gc8034 *gc8034 = to_gc8034(sd);
	const struct v4l2_mbus_framefmt *format;
	const struct gc8034_reg_list *reg_list;
	const struct gc8034_mode *mode;
	int ret;

	ret = pm_runtime_resume_and_get(gc8034->dev);
	if (ret < 0)
		return ret;

	format = v4l2_subdev_state_get_format(state, 0);
	mode = v4l2_find_nearest_size(gc8034_modes, ARRAY_SIZE(gc8034_modes),
				      width, height, format->width,
				      format->height);
	reg_list = &mode->reg_list;

	cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0, &ret);
	cci_multi_reg_write(gc8034->regmap, gc8034_global_regs,
			    ARRAY_SIZE(gc8034_global_regs), &ret);
	cci_multi_reg_write(gc8034->regmap, reg_list->regs,
			    reg_list->num_of_regs, &ret);
	if (ret)
		goto err_rpm_put;

	ret = __v4l2_ctrl_handler_setup(&gc8034->ctrls);
	if (ret)
		goto err_rpm_put;

	ret = cci_write(gc8034->regmap, GC8034_REG_STREAM, GC8034_STREAM_ON,
			NULL);
	if (ret)
		goto err_rpm_put;

	return 0;

err_rpm_put:
	pm_runtime_put_autosuspend(gc8034->dev);

	return ret;
}

static int gc8034_disable_streams(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *state,
				  u32 pad, u64 streams_mask)
{
	struct gc8034 *gc8034 = to_gc8034(sd);
	int ret;

	ret = cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0,
			NULL);
	if (!ret)
		ret = cci_write(gc8034->regmap, GC8034_REG_STREAM,
				GC8034_STREAM_OFF, NULL);
	if (ret)
		dev_err(gc8034->dev, "failed to stop streaming: %d\n", ret);

	pm_runtime_put_autosuspend(gc8034->dev);

	return 0;
}

static const struct v4l2_subdev_video_ops gc8034_video_ops = {
	.s_stream = v4l2_subdev_s_stream_helper,
};

static const struct v4l2_subdev_pad_ops gc8034_pad_ops = {
	.enum_mbus_code = gc8034_enum_mbus_code,
	.enum_frame_size = gc8034_enum_frame_size,
	.get_fmt = v4l2_subdev_get_fmt,
	.set_fmt = gc8034_set_format,
	.get_selection = gc8034_get_selection,
	.enable_streams = gc8034_enable_streams,
	.disable_streams = gc8034_disable_streams,
};

static const struct v4l2_subdev_ops gc8034_subdev_ops = {
	.video = &gc8034_video_ops,
	.pad = &gc8034_pad_ops,
};

static const struct v4l2_subdev_internal_ops gc8034_internal_ops = {
	.init_state = gc8034_init_state,
};

static int gc8034_parse_fwnode(struct gc8034 *gc8034)
{
	struct v4l2_fwnode_endpoint bus_cfg = {
		.bus_type = V4L2_MBUS_CSI2_DPHY,
	};
	struct device *dev = gc8034->dev;
	struct fwnode_handle *endpoint;
	unsigned long link_freq_bitmap;
	int ret;

	endpoint = fwnode_graph_get_endpoint_by_id(dev_fwnode(dev), 0, 0,
						   FWNODE_GRAPH_ENDPOINT_NEXT);
	ret = v4l2_fwnode_endpoint_alloc_parse(endpoint, &bus_cfg);
	fwnode_handle_put(endpoint);
	if (ret)
		return dev_err_probe(dev, ret, "failed to parse endpoint\n");

	/* The register tables configure the CSI-2 transmitter for 4 lanes. */
	if (bus_cfg.bus.mipi_csi2.num_data_lanes != GC8034_DATA_LANES) {
		ret = dev_err_probe(dev, -EINVAL,
				    "unsupported number of data lanes %u\n",
				    bus_cfg.bus.mipi_csi2.num_data_lanes);
		goto done;
	}

	ret = v4l2_link_freq_to_bitmap(dev, bus_cfg.link_frequencies,
				       bus_cfg.nr_of_link_frequencies,
				       gc8034_link_freq_menu,
				       ARRAY_SIZE(gc8034_link_freq_menu),
				       &link_freq_bitmap);

done:
	v4l2_fwnode_endpoint_free(&bus_cfg);

	return ret;
}

static int gc8034_init_controls(struct gc8034 *gc8034)
{
	const struct gc8034_mode *mode = &gc8034_modes[0];
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl_handler *ctrl_hdlr;
	struct v4l2_ctrl *link_freq;
	s64 exposure_max, h_blank;
	int ret;

	ret = v4l2_fwnode_device_parse(gc8034->dev, &props);
	if (ret)
		return ret;

	ctrl_hdlr = &gc8034->ctrls;
	ret = v4l2_ctrl_handler_init(ctrl_hdlr, 8);
	if (ret)
		return ret;

	link_freq = v4l2_ctrl_new_int_menu(ctrl_hdlr, NULL, V4L2_CID_LINK_FREQ,
					   ARRAY_SIZE(gc8034_link_freq_menu) -
					   1, 0, gc8034_link_freq_menu);

	v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_PIXEL_RATE,
			  GC8034_PIXEL_RATE, GC8034_PIXEL_RATE, 1,
			  GC8034_PIXEL_RATE);

	gc8034->vblank =
		v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops, V4L2_CID_VBLANK,
				  mode->vts_min - mode->height,
				  GC8034_VTS_MAX - mode->height, 1,
				  mode->vts_def - mode->height);

	h_blank = mode->hts - mode->width;
	gc8034->hblank = v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_HBLANK,
					   h_blank, h_blank, 1, h_blank);

	exposure_max = mode->vts_def - GC8034_EXP_MARGIN;
	gc8034->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
					     V4L2_CID_EXPOSURE, GC8034_EXP_MIN,
					     exposure_max, GC8034_EXP_STEP,
					     min(GC8034_EXP_DEF, exposure_max));

	v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			  0, ARRAY_SIZE(gc8034_again_level) - 1, 1, 0);

	v4l2_ctrl_new_fwnode_properties(ctrl_hdlr, &gc8034_ctrl_ops, &props);

	if (ctrl_hdlr->error) {
		ret = ctrl_hdlr->error;
		goto error_ctrls;
	}

	link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	gc8034->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	gc8034->sd.ctrl_handler = ctrl_hdlr;

	return 0;

error_ctrls:
	v4l2_ctrl_handler_free(ctrl_hdlr);

	return ret;
}

static int gc8034_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct gc8034 *gc8034;
	unsigned long freq;
	unsigned int i;
	int ret;

	gc8034 = devm_kzalloc(dev, sizeof(*gc8034), GFP_KERNEL);
	if (!gc8034)
		return -ENOMEM;

	gc8034->dev = dev;

	v4l2_i2c_subdev_init(&gc8034->sd, client, &gc8034_subdev_ops);
	gc8034->sd.internal_ops = &gc8034_internal_ops;

	ret = gc8034_parse_fwnode(gc8034);
	if (ret)
		return ret;

	gc8034->xclk = devm_v4l2_sensor_clk_get(dev, NULL);
	if (IS_ERR(gc8034->xclk))
		return dev_err_probe(dev, PTR_ERR(gc8034->xclk),
				     "failed to get clock\n");

	freq = clk_get_rate(gc8034->xclk);
	if (freq != GC8034_XCLK_FREQ)
		return dev_err_probe(dev, -EINVAL,
				     "external clock %lu Hz not supported\n",
				     freq);

	gc8034->regmap = devm_cci_regmap_init_i2c(client, 8);
	if (IS_ERR(gc8034->regmap))
		return dev_err_probe(dev, PTR_ERR(gc8034->regmap),
				     "failed to init CCI\n");

	gc8034->reset_gpio = devm_gpiod_get_optional(dev, "reset",
						     GPIOD_OUT_HIGH);
	if (IS_ERR(gc8034->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(gc8034->reset_gpio),
				     "failed to get reset GPIO\n");

	gc8034->powerdown_gpio = devm_gpiod_get_optional(dev, "powerdown",
							 GPIOD_OUT_HIGH);
	if (IS_ERR(gc8034->powerdown_gpio))
		return dev_err_probe(dev, PTR_ERR(gc8034->powerdown_gpio),
				     "failed to get powerdown GPIO\n");

	for (i = 0; i < ARRAY_SIZE(gc8034_supply_name); i++)
		gc8034->supplies[i].supply = gc8034_supply_name[i];

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(gc8034_supply_name),
				      gc8034->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	ret = gc8034_power_on(dev);
	if (ret)
		return ret;

	ret = gc8034_identify_module(gc8034);
	if (ret)
		goto err_power_off;

	ret = gc8034_init_controls(gc8034);
	if (ret) {
		dev_err_probe(dev, ret, "failed to init controls\n");
		goto err_power_off;
	}

	gc8034->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	gc8034->pad.flags = MEDIA_PAD_FL_SOURCE;
	gc8034->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;

	ret = media_entity_pads_init(&gc8034->sd.entity, 1, &gc8034->pad);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to init media entity\n");
		goto err_ctrl_handler_free;
	}

	gc8034->sd.state_lock = gc8034->ctrls.lock;
	ret = v4l2_subdev_init_finalize(&gc8034->sd);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to finalize subdev\n");
		goto err_media_entity_cleanup;
	}

	/* The sensor is on: say so, or runtime PM would power it up again. */
	pm_runtime_set_active(dev);
	pm_runtime_enable(dev);
	pm_runtime_set_autosuspend_delay(dev, 1000);
	pm_runtime_use_autosuspend(dev);

	ret = v4l2_async_register_subdev_sensor(&gc8034->sd);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to register subdev\n");
		goto err_rpm;
	}

	/* Hands the sensor over to autosuspend, which powers it back down. */
	pm_runtime_idle(dev);

	return 0;

err_rpm:
	pm_runtime_disable(dev);
	pm_runtime_dont_use_autosuspend(dev);
	pm_runtime_set_suspended(dev);
	v4l2_subdev_cleanup(&gc8034->sd);

err_media_entity_cleanup:
	media_entity_cleanup(&gc8034->sd.entity);

err_ctrl_handler_free:
	v4l2_ctrl_handler_free(&gc8034->ctrls);

err_power_off:
	gc8034_power_off(dev);

	return ret;
}

static void gc8034_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct gc8034 *gc8034 = to_gc8034(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&gc8034->ctrls);

	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		gc8034_power_off(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	pm_runtime_dont_use_autosuspend(&client->dev);
}

static const struct dev_pm_ops gc8034_pm_ops = {
	RUNTIME_PM_OPS(gc8034_power_off, gc8034_power_on, NULL)
};

static const struct acpi_device_id gc8034_acpi_ids[] = {
	{ "GCTI8034" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, gc8034_acpi_ids);

static struct i2c_driver gc8034_i2c_driver = {
	.driver = {
		.name = "gc8034",
		.acpi_match_table = gc8034_acpi_ids,
		.pm = pm_ptr(&gc8034_pm_ops),
	},
	.probe = gc8034_probe,
	.remove = gc8034_remove,
};
module_i2c_driver(gc8034_i2c_driver);

MODULE_AUTHOR("Nicola Fiorillo <nicfio@gmail.com>");
MODULE_DESCRIPTION("GalaxyCore GC8034 sensor driver");
MODULE_LICENSE("GPL");

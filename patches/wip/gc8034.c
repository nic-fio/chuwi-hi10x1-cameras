// SPDX-License-Identifier: GPL-2.0
/*
 * Driver for GalaxyCore GC8034 image sensor
 *
 * Copyright (C) 2017 Fuzhou Rockchip Electronics Co., Ltd.
 * Copyright (C) 2026 <TODO: nome e email reali prima dell'invio upstream>
 *
 * SCHELETRO — NON FUNZIONANTE. Vedi i TODO marcati "BLOCCANTE".
 *
 * Struttura basata su drivers/media/i2c/gc08a3.c (Zhi Mao, MediaTek), stesso
 * produttore di sensori. Adattamento x86/ACPI basato su
 * drivers/media/i2c/ov2740.c e t4ka3.c, che girano sulla stessa catena IPU6.
 *
 * Registri e sequenze derivati dal driver BSP Rockchip (GPL-2.0), repo
 * rockchip-linux/kernel branch develop-5.10, commit
 * 34690d3be73e98c6b037e24c76b3200fb22b9e79. L'attribuzione agli autori
 * originali va concordata prima di qualsiasi invio upstream: vedi
 * reference/README.md nel progetto.
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
 * Come il GC5035, il GC8034 usa indirizzi di registro a 8 bit con banchi di
 * pagina selezionati dal registro 0xfe. E' la differenza architetturale
 * principale rispetto al template gc08a3, che e' flat a 16 bit.
 */
#define GC8034_REG_PAGE_SELECT		CCI_REG8(0xfe)
#define GC8034_PAGE_0			0x00

/* leggibili in qualsiasi pagina */
#define GC8034_REG_CHIP_ID		CCI_REG16(0xf0)
#define GC8034_CHIP_ID			0x8044	/* non 0x8034 */

#define GC8034_REG_EXPOSURE		CCI_REG16(0x03)
#define GC8034_REG_ANALOGUE_GAIN	CCI_REG8(0xb6)
#define GC8034_REG_DIGITAL_GAIN_INT	CCI_REG8(0xb1)
#define GC8034_REG_DIGITAL_GAIN_FRAC	CCI_REG8(0xb2)
#define GC8034_REG_BLANKING		CCI_REG16(0x07)
#define GC8034_REG_STREAM		CCI_REG8(0x3f)
#define GC8034_STREAM_ON_2LANE		0x91
#define GC8034_STREAM_ON_4LANE		0xd0
#define GC8034_STREAM_OFF		0x00

#define GC8034_NATIVE_WIDTH		3264
#define GC8034_NATIVE_HEIGHT		2448

/*
 * Il registro 0x07/0x08 NON contiene la VTS: contiene un offset.
 * Verificato sui default del blob Rockchip: reg = 16 -> VTS = 2500 = 0x09c4,
 * coerente con il vts_def dichiarato.
 *
 *     VTS = reg + GC8034_VTS_OFFSET
 *     reg = height + vblank - GC8034_VTS_OFFSET
 *
 * dove 2484 = 2448 righe attive + 36 di overhead fisso.
 */
#define GC8034_VTS_OFFSET		2484
#define GC8034_VTS_MAX			0x1fff

/*
 * Il sensore non accetta shutter dispari: il BSP arrotonda al pari e compensa
 * il bit perso con un rapporto di guadagno digitale. Dichiarare step = 2 e'
 * equivalente e molto piu' pulito da leggere.
 */
#define GC8034_EXP_MIN			4
#define GC8034_EXP_STEP			2
#define GC8034_EXP_MARGIN		4

/*
 * TODO BLOCCANTE: valori dal BSP Rockchip, piattaforma completamente diversa.
 * Vanno confermati sul CHUWI Hi10 X1. Il numero di lane arriva dal fwnode che
 * ipu-bridge costruisce leggendo l'SSDB; la link frequency invece NON e'
 * ricavabile dal firmware (maxlanespeed resta a zero, verificato) e deve
 * corrispondere a quella per cui sono calcolate le tabelle registri.
 */
#define GC8034_LINK_FREQ_336MHZ		(336 * HZ_PER_MHZ)
#define GC8034_DATA_LANES		4
#define GC8034_RGB_DEPTH		10

/* TODO: confermare dal _DSD clock-frequency. Il BSP usa 24 MHz. */
#define GC8034_MCLK_DEFAULT		(24 * HZ_PER_MHZ)

/*
 * Timing del BSP, piu' lenti di quelli del template gc08a3 (2 ms + 2 ms):
 * 6 ms dopo il rilascio del reset, poi 8192 cicli di xvclk (~341 us a 24 MHz)
 * prima della prima transazione I2C.
 */
#define GC8034_RESET_SETTLE_US		6000
#define GC8034_I2C_SETTLE_US		350

#define GC8034_MBUS_CODE		MEDIA_BUS_FMT_SRGGB10_1X10

/*
 * Nessun V4L2_CID_TEST_PATTERN: il BSP Rockchip non ne espone uno e il
 * registro corrispondente non e' documentato. Da aggiungere solo se lo si
 * individua sull'hardware — meglio un controllo assente che uno che scrive
 * un registro sbagliato.
 */

static const s64 gc8034_link_freq_menu_items[] = {
	GC8034_LINK_FREQ_336MHZ,
};

static const char * const gc8034_supply_name[] = {
	"avdd",
	"dvdd",
	"dovdd",
};

/*
 * Il registro 0xb6 non prende un moltiplicatore, prende un INDICE in questa
 * tabella. Il resto del guadagno richiesto viene compensato in digitale su
 * 0xb1/0xb2. Unita': 0x40 = 64 = 1,00x (Q6).
 *
 * Il BSP usa solo i primi 7 indici (MEAG_INDEX = 7): le ultime due voci sono
 * codice morto la' dentro. Qui sono tenute perche' il sensore le accetta, ma
 * il range del controllo si ferma comunque all'ultima voce usata finche' non
 * si puo' verificare sull'hardware.
 */
static const u16 gc8034_again_level[] = {
	0x0040,	/*  1,000x */
	0x0058,	/*  1,375x */
	0x007d,	/*  1,950x */
	0x00ad,	/*  2,700x */
	0x00f3,	/*  3,800x */
	0x0159,	/*  5,400x */
	0x01ea,	/*  7,660x */
};

#define GC8034_AGAIN_MIN		64	/* 1,00x in Q6 */
#define GC8034_AGAIN_MAX		490	/* 7,66x in Q6 */
#define GC8034_DGAIN_UNITY		256	/* 1,00x in Q8 */

struct gc8034 {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;

	struct clk *xclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(gc8034_supply_name)];
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
	const struct gc8034_mode *cur_mode;
};

struct gc8034_reg_list {
	u32 num_of_regs;
	const struct cci_reg_sequence *regs;
};

/*
 * TODO BLOCCANTE: importare le sequenze dal BSP Rockchip
 * (reference/gc8034-rockchip-bsp.c, ~879 righe di tabelle fra global e mode).
 *
 * Non e' un copia-incolla: vanno separate in tre liste come chiedono i
 * revisori (power-on / clock e link frequency / mode), va tolto tutto il
 * codice OTP e gli ioctl Rockchip, e va sciolta l'attribuzione.
 */
static const struct cci_reg_sequence gc8034_mode_3264x2448[] = {
	{ GC8034_REG_PAGE_SELECT, GC8034_PAGE_0 },
};

struct gc8034_mode {
	u32 width;
	u32 height;
	const struct gc8034_reg_list reg_list;

	u32 hts;
	u32 vts_def;
	u32 vts_min;
	u32 fps;
};

static const struct gc8034_mode gc8034_modes[] = {
	{
		.width = GC8034_NATIVE_WIDTH,
		.height = GC8034_NATIVE_HEIGHT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(gc8034_mode_3264x2448),
			.regs = gc8034_mode_3264x2448,
		},
		.hts = 4272,
		.vts_def = 2496,
		.vts_min = 2496,
		.fps = 30,
	},
};

static inline struct gc8034 *to_gc8034(struct v4l2_subdev *sd)
{
	return container_of(sd, struct gc8034, sd);
}

static int gc8034_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc8034 *gc8034 = to_gc8034(sd);
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(gc8034_supply_name),
				    gc8034->supplies);
	if (ret < 0)
		return dev_err_probe(dev, ret, "failed to enable regulators\n");

	ret = clk_prepare_enable(gc8034->xclk);
	if (ret < 0) {
		regulator_bulk_disable(ARRAY_SIZE(gc8034_supply_name),
				       gc8034->supplies);
		return dev_err_probe(dev, ret, "failed to enable clock\n");
	}

	gpiod_set_value_cansleep(gc8034->powerdown_gpio, 0);
	gpiod_set_value_cansleep(gc8034->reset_gpio, 0);

	/* Il sensore vuole 6 ms dopo il rilascio del reset... */
	usleep_range(GC8034_RESET_SETTLE_US, GC8034_RESET_SETTLE_US + 1000);
	/* ...e 8192 cicli di xvclk prima del primo accesso I2C. */
	usleep_range(GC8034_I2C_SETTLE_US, GC8034_I2C_SETTLE_US + 100);

	return 0;
}

static int gc8034_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc8034 *gc8034 = to_gc8034(sd);

	gpiod_set_value_cansleep(gc8034->reset_gpio, 1);
	gpiod_set_value_cansleep(gc8034->powerdown_gpio, 1);
	clk_disable_unprepare(gc8034->xclk);
	regulator_bulk_disable(ARRAY_SIZE(gc8034_supply_name),
			       gc8034->supplies);

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

/*
 * V4L2_CID_PIXEL_RATE e' il rate del PIXEL ARRAY, non del bus CSI-2, perche'
 * viene usato con HBLANK/VBLANK per calcolare il frame interval:
 *
 *     frame_interval = (width + HBLANK) * (height + VBLANK) / PIXEL_RATE
 *
 * Qui le due grandezze divergono, al contrario del GC5035 dove coincidono
 * quasi esattamente:
 *
 *     hts * vts * fps          = 4272 * 2496 * 30 = 319,9 MHz  <- questo
 *     link_freq * 2 * lanes / bpp = 336e6 * 2 * 4 / 10 = 268,8 MHz
 *
 * La differenza e' attesa: durante il blanking orizzontale non si trasmette
 * nulla sul bus, quindi il rate del pixel array e' piu' alto di quello del
 * bus. Il valore corretto per il controllo e' il primo.
 *
 * TODO: verificare sull'hardware. Il BSP calcolava vts*hts*fps ma dichiarava
 * anche una GC8034_PIXEL_RATE 288000000 inutilizzata e incoerente con
 * entrambi.
 */
static u64 gc8034_to_pixel_rate(const struct gc8034_mode *mode)
{
	return (u64)mode->hts * mode->vts_def * mode->fps;
}

static int gc8034_update_cur_mode_controls(struct gc8034 *gc8034,
					   const struct gc8034_mode *mode)
{
	s64 exposure_max, h_blank;
	int ret;

	ret = __v4l2_ctrl_modify_range(gc8034->vblank,
				       mode->vts_min - mode->height,
				       GC8034_VTS_MAX - mode->height, 1,
				       mode->vts_def - mode->height);
	if (ret)
		return ret;

	h_blank = mode->hts - mode->width;
	ret = __v4l2_ctrl_modify_range(gc8034->hblank, h_blank, h_blank, 1,
				       h_blank);
	if (ret)
		return ret;

	exposure_max = mode->vts_def - GC8034_EXP_MARGIN;

	return __v4l2_ctrl_modify_range(gc8034->exposure, GC8034_EXP_MIN,
					exposure_max, GC8034_EXP_STEP,
					exposure_max);
}

static int gc8034_set_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *fmt)
{
	struct gc8034 *gc8034 = to_gc8034(sd);
	struct v4l2_mbus_framefmt *mbus_fmt;
	const struct gc8034_mode *mode;
	struct v4l2_rect *crop;

	mode = v4l2_find_nearest_size(gc8034_modes, ARRAY_SIZE(gc8034_modes),
				      width, height, fmt->format.width,
				      fmt->format.height);

	crop = v4l2_subdev_state_get_crop(state, 0);
	crop->width = mode->width;
	crop->height = mode->height;

	gc8034_update_pad_format(mode, &fmt->format);
	mbus_fmt = v4l2_subdev_state_get_format(state, 0);
	*mbus_fmt = fmt->format;

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		return 0;

	gc8034->cur_mode = mode;

	return gc8034_update_cur_mode_controls(gc8034, mode);
}

static int gc8034_get_selection(struct v4l2_subdev *sd,
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

	return gc8034_set_format(sd, state, &fmt);
}

/*
 * Sceglie l'indice di guadagno analogico piu' alto che non superi il valore
 * richiesto, e compensa il resto in digitale:
 *
 *     dgain = 256 * a_gain / again_level[idx]
 */
static int gc8034_set_analogue_gain(struct gc8034 *gc8034, u32 a_gain)
{
	unsigned int idx;
	u32 dgain;
	int ret = 0;

	for (idx = ARRAY_SIZE(gc8034_again_level) - 1; idx > 0; idx--) {
		if (a_gain >= gc8034_again_level[idx])
			break;
	}

	dgain = DIV_ROUND_CLOSEST(GC8034_DGAIN_UNITY * a_gain,
				  gc8034_again_level[idx]);

	cci_write(gc8034->regmap, GC8034_REG_ANALOGUE_GAIN, idx, &ret);
	cci_write(gc8034->regmap, GC8034_REG_DIGITAL_GAIN_INT,
		  (dgain >> 8) & 0x0f, &ret);
	cci_write(gc8034->regmap, GC8034_REG_DIGITAL_GAIN_FRAC,
		  dgain & 0xff, &ret);

	/*
	 * TODO BLOCCANTE: il BSP riscrive anche 14 registri di bias analogico
	 * da agc_register[9][14] a ogni cambio di indice. Sono valori non
	 * documentati ma piccoli e strutturati, necessari per la qualita'
	 * dell'immagine. Vanno importati dal BSP insieme alle tabelle mode.
	 */

	return ret;
}

static int gc8034_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct gc8034 *gc8034 =
		container_of(ctrl->handler, struct gc8034, ctrls);
	s64 exposure_max;
	int ret = 0;

	if (ctrl->id == V4L2_CID_VBLANK) {
		exposure_max = gc8034->cur_mode->height + ctrl->val -
			       GC8034_EXP_MARGIN;
		ret = __v4l2_ctrl_modify_range(gc8034->exposure,
					       GC8034_EXP_MIN, exposure_max,
					       GC8034_EXP_STEP, exposure_max);
		if (ret)
			return ret;
	}

	if (!pm_runtime_get_if_active(gc8034->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		ret = cci_write(gc8034->regmap, GC8034_REG_EXPOSURE,
				ctrl->val, NULL);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		ret = gc8034_set_analogue_gain(gc8034, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		/* Il registro contiene un offset, non la VTS. */
		ret = cci_write(gc8034->regmap, GC8034_REG_BLANKING,
				gc8034->cur_mode->height + ctrl->val -
				GC8034_VTS_OFFSET, NULL);
		break;
	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(gc8034->dev);

	return ret;
}

static const struct v4l2_ctrl_ops gc8034_ctrl_ops = {
	.s_ctrl = gc8034_set_ctrl,
};

static int gc8034_identify_module(struct gc8034 *gc8034)
{
	u64 val;
	int ret;

	if (gc8034->identified)
		return 0;

	ret = cci_read(gc8034->regmap, GC8034_REG_CHIP_ID, &val, NULL);
	if (ret)
		return ret;

	if (val != GC8034_CHIP_ID)
		return dev_err_probe(gc8034->dev, -ENXIO,
				     "chip id mismatch: %x != %llx\n",
				     GC8034_CHIP_ID, val);

	gc8034->identified = true;

	return 0;
}

static int gc8034_enable_streams(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state,
				 u32 pad, u64 streams_mask)
{
	struct gc8034 *gc8034 = to_gc8034(sd);
	const struct gc8034_reg_list *reg_list;
	u8 stream_on;
	int ret;

	ret = pm_runtime_resume_and_get(gc8034->dev);
	if (ret < 0)
		return ret;

	ret = gc8034_identify_module(gc8034);
	if (ret)
		goto err_rpm_put;

	reg_list = &gc8034->cur_mode->reg_list;

	cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0, &ret);
	cci_multi_reg_write(gc8034->regmap, reg_list->regs,
			    reg_list->num_of_regs, &ret);
	if (ret)
		goto err_rpm_put;

	ret = __v4l2_ctrl_handler_setup(&gc8034->ctrls);
	if (ret)
		goto err_rpm_put;

	/* Il valore di start streaming dipende dal numero di lane. */
	stream_on = gc8034->data_lanes == 4 ? GC8034_STREAM_ON_4LANE :
					      GC8034_STREAM_ON_2LANE;

	ret = cci_write(gc8034->regmap, GC8034_REG_STREAM, stream_on, NULL);
	if (ret)
		goto err_rpm_put;

	return 0;

err_rpm_put:
	pm_runtime_put(gc8034->dev);

	return ret;
}

static int gc8034_disable_streams(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *state,
				  u32 pad, u64 streams_mask)
{
	struct gc8034 *gc8034 = to_gc8034(sd);
	int ret;

	ret = cci_write(gc8034->regmap, GC8034_REG_STREAM,
			GC8034_STREAM_OFF, NULL);

	pm_runtime_put(gc8034->dev);

	return ret;
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
	int ret;

	/*
	 * -EPROBE_DEFER, non -EINVAL: su IPU6 il grafo lo sintetizza
	 * ipu-bridge e il sensore puo' fare probe prima che sia pronto.
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

	if (bus_cfg.bus.mipi_csi2.num_data_lanes != GC8034_DATA_LANES) {
		ret = dev_err_probe(dev, -EINVAL,
				    "unsupported number of data lanes %u\n",
				    bus_cfg.bus.mipi_csi2.num_data_lanes);
		goto done;
	}

	gc8034->data_lanes = bus_cfg.bus.mipi_csi2.num_data_lanes;

	ret = v4l2_link_freq_to_bitmap(dev, bus_cfg.link_frequencies,
				       bus_cfg.nr_of_link_frequencies,
				       gc8034_link_freq_menu_items,
				       ARRAY_SIZE(gc8034_link_freq_menu_items),
				       &gc8034->link_freq_bitmap);

done:
	v4l2_fwnode_endpoint_free(&bus_cfg);
	fwnode_handle_put(endpoint);

	return ret;
}

static int gc8034_init_controls(struct gc8034 *gc8034)
{
	struct i2c_client *client = v4l2_get_subdevdata(&gc8034->sd);
	const struct gc8034_mode *mode = &gc8034_modes[0];
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl_handler *ctrl_hdlr;
	s64 exposure_max, h_blank, pixel_rate;
	int ret;

	ctrl_hdlr = &gc8034->ctrls;
	ret = v4l2_ctrl_handler_init(ctrl_hdlr, 8);
	if (ret)
		return ret;

	gc8034->link_freq =
		v4l2_ctrl_new_int_menu(ctrl_hdlr, &gc8034_ctrl_ops,
				       V4L2_CID_LINK_FREQ,
				       ARRAY_SIZE(gc8034_link_freq_menu_items)
				       - 1,
				       0, gc8034_link_freq_menu_items);
	if (gc8034->link_freq)
		gc8034->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	pixel_rate = gc8034_to_pixel_rate(mode);
	gc8034->pixel_rate =
		v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
				  V4L2_CID_PIXEL_RATE, 0, pixel_rate, 1,
				  pixel_rate);
	if (gc8034->pixel_rate)
		gc8034->pixel_rate->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	gc8034->vblank =
		v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops, V4L2_CID_VBLANK,
				  mode->vts_min - mode->height,
				  GC8034_VTS_MAX - mode->height, 1,
				  mode->vts_def - mode->height);

	h_blank = mode->hts - mode->width;
	gc8034->hblank = v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
					   V4L2_CID_HBLANK, h_blank, h_blank,
					   1, h_blank);
	if (gc8034->hblank)
		gc8034->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	exposure_max = mode->vts_def - GC8034_EXP_MARGIN;
	gc8034->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
					     V4L2_CID_EXPOSURE, GC8034_EXP_MIN,
					     exposure_max, GC8034_EXP_STEP,
					     exposure_max);

	v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			  GC8034_AGAIN_MIN, GC8034_AGAIN_MAX, 1,
			  GC8034_AGAIN_MIN);

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		goto error_ctrls;

	ret = v4l2_ctrl_new_fwnode_properties(ctrl_hdlr, &gc8034_ctrl_ops,
					      &props);
	if (ret)
		goto error_ctrls;

	if (ctrl_hdlr->error) {
		ret = ctrl_hdlr->error;
		goto error_ctrls;
	}

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

	gc8034->xclk = devm_v4l2_sensor_clk_get(dev, "clk");
	if (IS_ERR(gc8034->xclk))
		return dev_err_probe(dev, PTR_ERR(gc8034->xclk),
				     "failed to get clock\n");

	freq = clk_get_rate(gc8034->xclk);
	if (freq != GC8034_MCLK_DEFAULT)
		dev_warn(dev, "external clock %lu, expected %lu\n", freq,
			 (unsigned long)GC8034_MCLK_DEFAULT);

	for (i = 0; i < ARRAY_SIZE(gc8034_supply_name); i++)
		gc8034->supplies[i].supply = gc8034_supply_name[i];

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(gc8034_supply_name),
				      gc8034->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	gc8034->cur_mode = &gc8034_modes[0];

	ret = gc8034_init_controls(gc8034);
	if (ret)
		return dev_err_probe(dev, ret, "failed to init controls\n");

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

	pm_runtime_enable(dev);
	pm_runtime_set_autosuspend_delay(dev, 1000);
	pm_runtime_use_autosuspend(dev);
	pm_runtime_idle(dev);

	ret = v4l2_async_register_subdev_sensor(&gc8034->sd);
	if (ret < 0) {
		dev_err_probe(dev, ret, "failed to register subdev\n");
		goto err_rpm;
	}

	return 0;

err_rpm:
	pm_runtime_disable(dev);
	v4l2_subdev_cleanup(&gc8034->sd);

err_media_entity_cleanup:
	media_entity_cleanup(&gc8034->sd.entity);

err_ctrl_handler_free:
	v4l2_ctrl_handler_free(&gc8034->ctrls);

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

static DEFINE_RUNTIME_DEV_PM_OPS(gc8034_pm_ops, gc8034_power_off,
				 gc8034_power_on, NULL);

static const struct acpi_device_id gc8034_acpi_ids[] = {
	{ "GCTI8034" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, gc8034_acpi_ids);

static const struct of_device_id gc8034_of_match[] = {
	{ .compatible = "galaxycore,gc8034" },
	{ }
};
MODULE_DEVICE_TABLE(of, gc8034_of_match);

static struct i2c_driver gc8034_i2c_driver = {
	.driver = {
		.name = "gc8034",
		.acpi_match_table = gc8034_acpi_ids,
		.of_match_table = gc8034_of_match,
		.pm = pm_ptr(&gc8034_pm_ops),
	},
	.probe = gc8034_probe,
	.remove = gc8034_remove,
};
module_i2c_driver(gc8034_i2c_driver);

MODULE_DESCRIPTION("GalaxyCore GC8034 sensor driver");
MODULE_LICENSE("GPL");

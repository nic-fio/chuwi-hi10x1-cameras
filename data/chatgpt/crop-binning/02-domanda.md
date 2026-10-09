Seconda richiesta: revisione del codice della v2, come la farebbero Laurent
Pinchart e Sakari Ailus sulla mailing list linux-media. Sii severo e concreto
(riga, problema, correzione). Non inventare fatti sui registri: le scelte
geometriche vengono dalle misure riassunte sotto.

Correzione a un mio errore nella domanda precedente: il GC5035 usa 2 lane
CSI-2, il GC8034 4 lane.

Contesto delle scelte (tutte misurate sul tablet, due corse ciascuna):
- GC5035: area valida 2608x1964; row start 1 riga/unita'; col start a passi
  di 4 colonne e valori pari corrotti; finestra orizzontale stretta = nero;
  quindi crop verticale con la finestra di lettura (row start = top + 4,
  altezza = height), orizzontale col crop d'uscita (finestra da col 1 larga
  2616, uscita da left + 4), margine destro >= 2. Periodo = (h + vblank) *
  2920 / 168,96 MHz esatto da 64 a 1964 righe.
- GC8034: area 3282x2500 (riga 14-2513 del sensore; oltre la riga 2521 i
  tempi cambiano); col start inaffidabile, quindi finestra di tabella e crop
  d'uscita (left + 1); finestra alta height + 16 e uscita a y 8; righe del
  fotogramma = finestra + 20 + registro di blanking => registro = vblank - 36,
  periodo = (h + vblank) * 4272 / 256 MHz esatto da 64 a 2448 righe;
  larghezza <= 384 flusso rotto, >= 448 ok => minimo 512; larghezza massima
  3280 (uscita larga quanto la finestra = errori CSI).
- Entrambi: alla posizione di default la v2 produce la stessa immagine della
  v1; byte alti dei registri di geometria non riscritti dalla tabella v1 =>
  la v2 scrive tutta la geometria a ogni stream on. Binning non incluso (nel
  modo binned del GC5035 la frequenza del collegamento non e' nota).
- Prove: 0 KO in due corse (rettangolo, periodo, posizione al pixel,
  fotogrammi completi), EBUSY in stream, v4l2-compliance 54/54 0 avvisi,
  libcamera 60/60 in tre configurazioni per camera.

Domande:
1. Errori o rischi nel codice (locking, controlli, stato TRY/ACTIVE, regole di
   arrotondamento, overflow, ordine delle scritture)?
2. set_fmt che centra il crop quando cambia la dimensione (come ov01a10):
   va bene? Cosa direbbe Laurent?
3. NATIVE_SIZE = CROP_BOUNDS = area misurata: corretto? Cosa riportare
   meglio?
4. Il GC8034 ha larghezza minima 512 e massima 3280 dentro un'area di 3282:
   e' un problema per i revisori o per libcamera?
5. Cosa manca perche' la v2 sia accettabile?

Diff v1 -> v2 (formato unified):
```diff
--- driver-v1/gc5035.c	2026-10-08 19:28:26.715714779 +0200
+++ driver-v2/gc5035.c	2026-10-09 18:04:22.791683422 +0200
@@ -76,22 +76,48 @@
 #define GC5035_REG_OUT_WIDTH		CCI_REG16(0x97)
 
 /*
- * The sensor reads out a 2608x1960 window starting at (3, 4) and crops
- * 2592x1944 from it at (8, 8). The size of the full pixel array is not
- * documented, so the readout window is reported as the native size.
+ * No register documentation is available: the geometry below was measured.
+ *
+ * Crop rectangles are expressed in the coordinates of the largest area of the
+ * pixel array that was measured to give image data, 2608x1964. The rows and
+ * columns around it are constant (black, or stuck at full scale), and the
+ * size of the full pixel array is not known, so this area is reported as the
+ * native size. Its origin is read out with the row start register at 4 and
+ * the column start register at 3.
+ *
+ * The row start register moves the image by one row per unit. The column
+ * start register moves it in steps of four columns, and its even values give
+ * corrupted images; a readout window narrower than the full width gives black
+ * images. The readout window therefore always covers the full width, from
+ * column start 1, and the horizontal crop is done by the output crop, which
+ * must end at least two columns before the end of the window. The vertical
+ * crop is done by the readout window itself, which shortens the frame.
+ *
+ * The default crop rectangle is the 2592x1944 image of the vendor register
+ * sequence, at (8, 8) in the area. Even offsets keep the GRBG order.
  */
-#define GC5035_WIN_LEFT			3
-#define GC5035_WIN_TOP			4
-#define GC5035_NATIVE_WIDTH		2608
-#define GC5035_NATIVE_HEIGHT		1960
+#define GC5035_AREA_WIDTH		2608
+#define GC5035_AREA_HEIGHT		1964
+#define GC5035_ROW_START_OFFSET		4
+#define GC5035_COL_START		1
+#define GC5035_WIN_WIDTH		2616
+#define GC5035_OUT_LEFT_OFFSET		4
 #define GC5035_CROP_LEFT		8
 #define GC5035_CROP_TOP			8
 #define GC5035_WIDTH			2592
 #define GC5035_HEIGHT			1944
+#define GC5035_MIN_WIDTH		64
+#define GC5035_MIN_HEIGHT		64
 
-/* The line length register counts units of 4 pixels. */
+/*
+ * The line length register counts units of 4 pixels. The frame length is the
+ * output height plus the vertical blanking; the vendor sequence uses 64 lines
+ * of blanking at full resolution, which is kept as the minimum. The frame
+ * period measured with every crop height tried, from 64 to 1964 lines, is
+ * (height + vblank) * HTS / pixel rate.
+ */
 #define GC5035_HTS			2920
-#define GC5035_VTS_DEF			2008
+#define GC5035_VBLANK_MIN		64
 
 #define GC5035_EXP_MIN			4
 #define GC5035_EXP_STEP			1
@@ -183,14 +209,18 @@
 
 	struct v4l2_ctrl_handler ctrls;
 	struct v4l2_ctrl *exposure;
+	struct v4l2_ctrl *vblank;
+	struct v4l2_ctrl *hblank;
 
 	struct regmap *regmap;
 };
 
 /*
  * The register sequence is the vendor one for the 2592x1944 mode, without the
- * registers written by the controls. No register documentation is available:
- * the names of the geometry registers are inferred from their values.
+ * registers written by the controls and without the geometry, which is
+ * computed from the crop rectangle. No register documentation is available:
+ * the names of the geometry registers are inferred from their values and from
+ * measurements.
  */
 static const struct cci_reg_sequence gc5035_regs[] = {
 	/* System */
@@ -224,10 +254,6 @@
 	/* Analog & CISCTL */
 	{ GC5035_REG_LINE_LENGTH, GC5035_HTS / 4 },
 	{ CCI_REG8(0x9d), 0x18 },
-	{ GC5035_REG_WIN_TOP, GC5035_WIN_TOP },
-	{ GC5035_REG_WIN_LEFT, GC5035_WIN_LEFT },
-	{ GC5035_REG_WIN_HEIGHT, GC5035_NATIVE_HEIGHT },
-	{ GC5035_REG_WIN_WIDTH, GC5035_NATIVE_WIDTH },
 	{ CCI_REG8(0x11), 0x02 },
 	{ CCI_REG8(0x17), 0x80 },
 	{ CCI_REG8(0x19), 0x05 },
@@ -326,12 +352,8 @@
 	{ CCI_REG8(0x4e), 0x3c },
 	{ CCI_REG8(0x44), 0x08 },
 	{ CCI_REG8(0x48), 0x02 },
-	/* CROP */
+	/* CROP, the geometry is written by gc5035_write_geometry() */
 	{ GC5035_REG_PAGE_SELECT, 0x01 },
-	{ GC5035_REG_CROP_TOP, GC5035_CROP_TOP },
-	{ GC5035_REG_CROP_LEFT, GC5035_CROP_LEFT },
-	{ GC5035_REG_OUT_HEIGHT, GC5035_HEIGHT },
-	{ GC5035_REG_OUT_WIDTH, GC5035_WIDTH },
 	{ CCI_REG8(0x99), 0x00 },
 	/* MIPI */
 	{ GC5035_REG_PAGE_SELECT, 0x03 },
@@ -444,28 +466,55 @@
 	if (fse->index > 0)
 		return -EINVAL;
 
-	fse->min_width = GC5035_WIDTH;
-	fse->max_width = GC5035_WIDTH;
-	fse->min_height = GC5035_HEIGHT;
-	fse->max_height = GC5035_HEIGHT;
+	/* The output size is the size of the crop rectangle. */
+	fse->min_width = GC5035_MIN_WIDTH;
+	fse->max_width = GC5035_AREA_WIDTH;
+	fse->min_height = GC5035_MIN_HEIGHT;
+	fse->max_height = GC5035_AREA_HEIGHT;
 
 	return 0;
 }
 
-static void gc5035_fill_state(struct v4l2_subdev_state *state)
+/*
+ * Update the controls that depend on the output size. Called with the state
+ * lock held, which is also the control handler lock.
+ */
+static int gc5035_update_ctrls(struct gc5035 *gc5035,
+			       const struct v4l2_mbus_framefmt *format)
 {
-	struct v4l2_mbus_framefmt *fmt;
-	struct v4l2_rect *crop;
+	s64 vblank_max, exposure_max;
+	int ret;
 
-	crop = v4l2_subdev_state_get_crop(state, 0);
-	crop->left = GC5035_CROP_LEFT;
-	crop->top = GC5035_CROP_TOP;
-	crop->width = GC5035_WIDTH;
-	crop->height = GC5035_HEIGHT;
+	ret = __v4l2_ctrl_modify_range(gc5035->hblank,
+				       GC5035_HTS - format->width,
+				       GC5035_HTS - format->width, 1,
+				       GC5035_HTS - format->width);
+	if (ret)
+		return ret;
 
-	fmt = v4l2_subdev_state_get_format(state, 0);
-	fmt->width = GC5035_WIDTH;
-	fmt->height = GC5035_HEIGHT;
+	vblank_max = GC5035_VBLANK_MIN +
+		     round_down(GC5035_VTS_MAX - format->height -
+				GC5035_VBLANK_MIN, GC5035_VBLANK_STEP);
+	ret = __v4l2_ctrl_modify_range(gc5035->vblank, GC5035_VBLANK_MIN,
+				       vblank_max, GC5035_VBLANK_STEP,
+				       GC5035_VBLANK_MIN);
+	if (ret)
+		return ret;
+
+	exposure_max = format->height + gc5035->vblank->val -
+		       GC5035_EXP_MARGIN;
+
+	return __v4l2_ctrl_modify_range(gc5035->exposure, GC5035_EXP_MIN,
+					exposure_max, GC5035_EXP_STEP,
+					min_t(s64, GC5035_EXP_DEF,
+					      exposure_max));
+}
+
+static void gc5035_fill_format(struct v4l2_mbus_framefmt *fmt,
+			       const struct v4l2_rect *crop)
+{
+	fmt->width = crop->width;
+	fmt->height = crop->height;
 	fmt->code = GC5035_MBUS_CODE;
 	fmt->field = V4L2_FIELD_NONE;
 	fmt->colorspace = V4L2_COLORSPACE_RAW;
@@ -493,8 +542,8 @@
 	case V4L2_SEL_TGT_NATIVE_SIZE:
 		sel->r.top = 0;
 		sel->r.left = 0;
-		sel->r.width = GC5035_NATIVE_WIDTH;
-		sel->r.height = GC5035_NATIVE_HEIGHT;
+		sel->r.width = GC5035_AREA_WIDTH;
+		sel->r.height = GC5035_AREA_HEIGHT;
 		break;
 	default:
 		return -EINVAL;
@@ -503,10 +552,101 @@
 	return 0;
 }
 
+static int gc5035_set_selection(struct v4l2_subdev *sd,
+				const struct v4l2_subdev_client_info *ci,
+				struct v4l2_subdev_state *state,
+				struct v4l2_subdev_selection *sel)
+{
+	struct gc5035 *gc5035 = to_gc5035(sd);
+	struct v4l2_mbus_framefmt *format;
+	struct v4l2_rect rect;
+
+	if (sel->target != V4L2_SEL_TGT_CROP)
+		return -EINVAL;
+
+	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
+	    v4l2_subdev_is_streaming(sd))
+		return -EBUSY;
+
+	/*
+	 * Even offsets keep the GRBG order. The sizes are multiples of 4: the
+	 * sensor rounds the frame length to a multiple of 4 lines.
+	 */
+	rect.left = ALIGN_DOWN(clamp(sel->r.left, 0,
+				     GC5035_AREA_WIDTH - GC5035_MIN_WIDTH), 2);
+	rect.top = ALIGN_DOWN(clamp(sel->r.top, 0,
+				    GC5035_AREA_HEIGHT - GC5035_MIN_HEIGHT), 2);
+	rect.width = ALIGN_DOWN(clamp_t(u32, sel->r.width, GC5035_MIN_WIDTH,
+					GC5035_AREA_WIDTH - rect.left), 4);
+	rect.height = ALIGN_DOWN(clamp_t(u32, sel->r.height, GC5035_MIN_HEIGHT,
+					 GC5035_AREA_HEIGHT - rect.top), 4);
+
+	*v4l2_subdev_state_get_crop(state, 0) = rect;
+	sel->r = rect;
+
+	/* No binning or scaling: the output size is the crop size. */
+	format = v4l2_subdev_state_get_format(state, 0);
+	gc5035_fill_format(format, &rect);
+
+	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE)
+		return gc5035_update_ctrls(gc5035, format);
+
+	return 0;
+}
+
+/*
+ * No binning or scaling: the output size is the size of the crop rectangle. A
+ * new size moves the crop rectangle to the centre of the area, for userspace
+ * that does not set the crop rectangle first.
+ */
+static int gc5035_set_fmt(struct v4l2_subdev *sd,
+			  const struct v4l2_subdev_client_info *ci,
+			  struct v4l2_subdev_state *state,
+			  struct v4l2_subdev_format *fmt)
+{
+	struct gc5035 *gc5035 = to_gc5035(sd);
+	struct v4l2_mbus_framefmt *format;
+	struct v4l2_rect *crop;
+	u32 width, height;
+
+	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
+	    v4l2_subdev_is_streaming(sd))
+		return -EBUSY;
+
+	width = ALIGN_DOWN(clamp_t(u32, fmt->format.width, GC5035_MIN_WIDTH,
+				   GC5035_AREA_WIDTH), 4);
+	height = ALIGN_DOWN(clamp_t(u32, fmt->format.height, GC5035_MIN_HEIGHT,
+				    GC5035_AREA_HEIGHT), 4);
+
+	crop = v4l2_subdev_state_get_crop(state, 0);
+	if (width != crop->width || height != crop->height) {
+		crop->left = ALIGN_DOWN((GC5035_AREA_WIDTH - width) / 2, 2);
+		crop->top = ALIGN_DOWN((GC5035_AREA_HEIGHT - height) / 2, 2);
+		crop->width = width;
+		crop->height = height;
+	}
+
+	format = v4l2_subdev_state_get_format(state, 0);
+	gc5035_fill_format(format, crop);
+	fmt->format = *format;
+
+	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE)
+		return gc5035_update_ctrls(gc5035, format);
+
+	return 0;
+}
+
 static int gc5035_init_state(struct v4l2_subdev *sd,
 			     struct v4l2_subdev_state *state)
 {
-	gc5035_fill_state(state);
+	struct v4l2_rect *crop = v4l2_subdev_state_get_crop(state, 0);
+
+	crop->left = GC5035_CROP_LEFT;
+	crop->top = GC5035_CROP_TOP;
+	crop->width = GC5035_WIDTH;
+	crop->height = GC5035_HEIGHT;
+
+	gc5035_fill_format(v4l2_subdev_state_get_format(state, 0), crop);
 
 	return 0;
 }
@@ -557,7 +697,9 @@
 			       GC5035_EXP_MARGIN;
 		ret = __v4l2_ctrl_modify_range(gc5035->exposure,
 					       GC5035_EXP_MIN, exposure_max,
-					       GC5035_EXP_STEP, GC5035_EXP_DEF);
+					       GC5035_EXP_STEP,
+					       min_t(s64, GC5035_EXP_DEF,
+						     exposure_max));
 		if (ret)
 			return ret;
 	}
@@ -618,6 +760,31 @@
 	return 0;
 }
 
+static int gc5035_write_geometry(struct gc5035 *gc5035,
+				 const struct v4l2_rect *crop)
+{
+	int ret = 0;
+
+	/* Readout window: full width, the rows of the crop rectangle. */
+	cci_write(gc5035->regmap, GC5035_REG_PAGE_SELECT, GC5035_PAGE_0, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_WIN_TOP,
+		  crop->top + GC5035_ROW_START_OFFSET, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_WIN_LEFT, GC5035_COL_START, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_WIN_HEIGHT, crop->height, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_WIN_WIDTH, GC5035_WIN_WIDTH, &ret);
+
+	/* Output crop: the columns of the crop rectangle. */
+	cci_write(gc5035->regmap, GC5035_REG_PAGE_SELECT, GC5035_PAGE_1, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_CROP_TOP, 0, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_CROP_LEFT,
+		  crop->left + GC5035_OUT_LEFT_OFFSET, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_OUT_HEIGHT, crop->height, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_OUT_WIDTH, crop->width, &ret);
+	cci_write(gc5035->regmap, GC5035_REG_PAGE_SELECT, GC5035_PAGE_0, &ret);
+
+	return ret;
+}
+
 static int gc5035_enable_streams(struct v4l2_subdev *sd,
 				 struct v4l2_subdev_state *state,
 				 u32 pad, u64 streams_mask)
@@ -634,6 +801,11 @@
 	if (ret)
 		goto err_rpm_put;
 
+	ret = gc5035_write_geometry(gc5035,
+				    v4l2_subdev_state_get_crop(state, 0));
+	if (ret)
+		goto err_rpm_put;
+
 	ret = __v4l2_ctrl_handler_setup(&gc5035->ctrls);
 	if (ret)
 		goto err_rpm_put;
@@ -675,7 +847,9 @@
 	.enum_mbus_code = gc5035_enum_mbus_code,
 	.enum_frame_size = gc5035_enum_frame_size,
 	.get_fmt = v4l2_subdev_get_fmt,
+	.set_fmt = gc5035_set_fmt,
 	.get_selection = gc5035_get_selection,
+	.set_selection = gc5035_set_selection,
 	.get_frame_desc = gc5035_get_frame_desc,
 	.enable_streams = gc5035_enable_streams,
 	.disable_streams = gc5035_disable_streams,
@@ -731,7 +905,7 @@
 {
 	struct v4l2_fwnode_device_properties props;
 	struct v4l2_ctrl_handler *ctrl_hdlr;
-	struct v4l2_ctrl *link_freq, *hblank;
+	struct v4l2_ctrl *link_freq;
 	s64 exposure_max;
 	int ret;
 
@@ -750,19 +924,23 @@
 			  GC5035_PIXEL_RATE, GC5035_PIXEL_RATE, 1,
 			  GC5035_PIXEL_RATE);
 
-	v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops, V4L2_CID_VBLANK,
-			  GC5035_VTS_DEF - GC5035_HEIGHT,
-			  GC5035_VTS_DEF - GC5035_HEIGHT +
-			  round_down(GC5035_VTS_MAX - GC5035_VTS_DEF,
-				     GC5035_VBLANK_STEP),
-			  GC5035_VBLANK_STEP, GC5035_VTS_DEF - GC5035_HEIGHT);
-
-	hblank = v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_HBLANK,
-				   GC5035_HTS - GC5035_WIDTH,
-				   GC5035_HTS - GC5035_WIDTH, 1,
-				   GC5035_HTS - GC5035_WIDTH);
+	/* Ranges for the default crop rectangle, see gc5035_update_ctrls(). */
+	gc5035->vblank = v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops,
+					   V4L2_CID_VBLANK, GC5035_VBLANK_MIN,
+					   GC5035_VBLANK_MIN +
+					   round_down(GC5035_VTS_MAX -
+						      GC5035_HEIGHT -
+						      GC5035_VBLANK_MIN,
+						      GC5035_VBLANK_STEP),
+					   GC5035_VBLANK_STEP,
+					   GC5035_VBLANK_MIN);
+
+	gc5035->hblank = v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_HBLANK,
+					   GC5035_HTS - GC5035_WIDTH,
+					   GC5035_HTS - GC5035_WIDTH, 1,
+					   GC5035_HTS - GC5035_WIDTH);
 
-	exposure_max = GC5035_VTS_DEF - GC5035_EXP_MARGIN;
+	exposure_max = GC5035_HEIGHT + GC5035_VBLANK_MIN - GC5035_EXP_MARGIN;
 	gc5035->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &gc5035_ctrl_ops,
 					     V4L2_CID_EXPOSURE, GC5035_EXP_MIN,
 					     exposure_max, GC5035_EXP_STEP,
@@ -782,7 +960,7 @@
 		return v4l2_ctrl_handler_free(ctrl_hdlr);
 
 	link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;
-	hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;
+	gc5035->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;
 
 	gc5035->sd.ctrl_handler = ctrl_hdlr;
 
--- driver-v1/gc8034.c	2026-10-08 19:28:26.718627053 +0200
+++ driver-v2/gc8034.c	2026-10-09 18:23:29.499141774 +0200
@@ -49,7 +49,7 @@
 #define GC8034_REG_EXPOSURE		CCI_REG16(0x03)
 #define GC8034_REG_LINE_LENGTH		CCI_REG16(0x05)
 #define GC8034_REG_BLANKING		CCI_REG16(0x07)
-#define GC8034_REG_WIN_TOP		CCI_REG8(0x0a)
+#define GC8034_REG_WIN_TOP		CCI_REG16(0x09)
 #define GC8034_REG_WIN_LEFT		CCI_REG16(0x0b)
 #define GC8034_REG_WIN_HEIGHT		CCI_REG16(0x0d)
 #define GC8034_REG_WIN_WIDTH		CCI_REG16(0x0f)
@@ -58,35 +58,69 @@
 #define GC8034_REG_STREAM		CCI_REG8(0x3f)
 #define GC8034_STREAM_ON		0xd0
 #define GC8034_STREAM_OFF		0x00
-#define GC8034_REG_CROP_TOP		CCI_REG8(0x92)
-#define GC8034_REG_CROP_LEFT		CCI_REG8(0x94)
+#define GC8034_REG_CROP_TOP		CCI_REG16(0x91)
+#define GC8034_REG_CROP_LEFT		CCI_REG16(0x93)
 #define GC8034_REG_OUT_HEIGHT		CCI_REG16(0x95)
 #define GC8034_REG_OUT_WIDTH		CCI_REG16(0x97)
 #define GC8034_REG_DIGITAL_GAIN	CCI_REG16(0xb1)
 #define GC8034_DIGITAL_GAIN_1X	0x100
 #define GC8034_REG_ANALOGUE_GAIN	CCI_REG8(0xb6)
 
+/* page 3 */
+#define GC8034_PAGE_3			0x03
+/* CSI-2 line length in bytes, low byte first */
+#define GC8034_REG_LINE_BYTES		CCI_REG16_LE(0x12)
+
 /*
- * The sensor reads out a 3284x2464 window starting at (4, 58) and crops
- * 3264x2448 from it at (9, 8). The odd crop column gives the RGGB order; the
- * vendor code moves it by one column when mirroring. The size of the full
- * pixel array is not documented, so the readout window is reported as the
- * native size.
+ * No register documentation is available: the geometry below was measured.
+ *
+ * Crop rectangles are expressed in the coordinates of a 3282x2500 area: the
+ * columns of the vendor readout window (column start 4, 3284 columns) from
+ * its second column, and rows 14 to 2513 of the sensor. Rows 14 to 2523 give
+ * image data; with the readout window reaching past row 2521 the frame
+ * timing changes, so the area stops there. The size of the full pixel array
+ * is not known, so this area is reported as the native size.
+ *
+ * The column start register only gives valid images at some values, so the
+ * readout window keeps the vendor columns and the horizontal crop is done by
+ * the output crop, at least 4 columns narrower than the window. The vertical
+ * crop is done by the readout window, 16 rows taller than the output and
+ * cropped at row 8 as in the vendor sequence; it shortens the frame. Even
+ * offsets in the area keep the RGGB order.
+ *
+ * The default crop rectangle is the 3264x2448 image of the vendor register
+ * sequence, at (8, 52) in the area.
+ *
+ * Output widths up to 384 pixels gave corrupted frames on the CSI-2 receiver,
+ * 448 pixels and above worked; 512 is kept as the minimum.
  */
+#define GC8034_AREA_WIDTH		3282
+#define GC8034_AREA_HEIGHT		2500
+#define GC8034_ROW_START_OFFSET		6
 #define GC8034_WIN_LEFT			4
-#define GC8034_WIN_TOP			58
-#define GC8034_NATIVE_WIDTH		3284
-#define GC8034_NATIVE_HEIGHT		2464
-#define GC8034_CROP_LEFT		9
-#define GC8034_CROP_TOP			8
+#define GC8034_WIN_WIDTH		3284
+#define GC8034_WIN_EXTRA_ROWS		16
+#define GC8034_OUT_TOP			8
+#define GC8034_OUT_LEFT_OFFSET		1
+#define GC8034_CROP_LEFT		8
+#define GC8034_CROP_TOP			52
 #define GC8034_WIDTH			3264
 #define GC8034_HEIGHT			2448
+#define GC8034_MIN_WIDTH		512
+#define GC8034_MIN_HEIGHT		64
+#define GC8034_MAX_WIDTH		(GC8034_WIN_WIDTH - 4)
+#define GC8034_MAX_HEIGHT		2448
 
 /*
- * The blanking register holds the frame length minus the active height and
- * 36 lines, as computed by the vendor code.
+ * The frame is the readout window plus 20 lines plus the blanking register.
+ * With the window 16 rows taller than the output, the frame length is the
+ * output height plus the vertical blanking, and the register holds the
+ * vertical blanking minus 36 lines. This was measured with output heights
+ * from 64 to 2448 lines. The vendor sequence uses 48 lines of blanking, which
+ * is kept as the minimum.
  */
-#define GC8034_VTS_OFFSET		(GC8034_HEIGHT + 36)
+#define GC8034_BLANKING_OFFSET		36
+#define GC8034_VBLANK_MIN		48
 #define GC8034_VTS_MAX			0x1fff
 
 /* The sensor only takes even exposure values. */
@@ -100,15 +134,15 @@
  * vendor code declares 336 MHz and 30 fps for a 24 MHz clock; at 19.2 MHz
  * everything runs at 0.8 times that: 268.8 MHz and 24 fps, as measured. The
  * PLL settings are not documented, so the pixel rate is not computed from
- * them: it is the one that gives the measured 24 fps with the line and frame
- * lengths below. The line length register counts units of 8 pixels.
+ * them: it is the one that gives the measured frame periods with the line
+ * length below, from 1.869 ms for 112 lines to 41.653 ms for 2496 lines. The
+ * line length register counts units of 8 pixels.
  */
 #define GC8034_XCLK_FREQ		(19200 * HZ_PER_KHZ)
 #define GC8034_LINK_FREQ		(268800 * HZ_PER_KHZ)
 #define GC8034_DATA_LANES		4
 #define GC8034_HTS			4272
-#define GC8034_VTS_DEF			2496
-#define GC8034_PIXEL_RATE		(GC8034_HTS * GC8034_VTS_DEF * 24)
+#define GC8034_PIXEL_RATE		(256 * HZ_PER_MHZ)
 
 /*
  * No datasheet is available. The power sequence and delays follow the vendor
@@ -184,6 +218,8 @@
 
 	struct v4l2_ctrl_handler ctrls;
 	struct v4l2_ctrl *exposure;
+	struct v4l2_ctrl *vblank;
+	struct v4l2_ctrl *hblank;
 
 	struct regmap *regmap;
 };
@@ -216,10 +252,6 @@
 	/* Cisctl&Analog */
 	{ GC8034_REG_PAGE_SELECT, 0x00 },
 	{ GC8034_REG_LINE_LENGTH, GC8034_HTS / 8 },
-	{ GC8034_REG_WIN_TOP, GC8034_WIN_TOP },
-	{ GC8034_REG_WIN_LEFT, GC8034_WIN_LEFT },
-	{ GC8034_REG_WIN_HEIGHT, GC8034_NATIVE_HEIGHT },
-	{ GC8034_REG_WIN_WIDTH, GC8034_NATIVE_WIDTH },
 	{ GC8034_REG_MIRROR, GC8034_MIRROR_NONE },
 	{ CCI_REG8(0x18), 0x02 },
 	{ CCI_REG8(0x19), 0x17 },
@@ -353,12 +385,8 @@
 	{ GC8034_REG_PAGE_SELECT, 0x00 },
 	{ CCI_REG8(0x80), 0x13 },
 	{ CCI_REG8(0xad), 0x00 },
-	/* Crop window */
+	/* Crop window, the geometry is written by gc8034_write_geometry() */
 	{ CCI_REG8(0x90), 0x01 },
-	{ GC8034_REG_CROP_TOP, GC8034_CROP_TOP },
-	{ GC8034_REG_CROP_LEFT, GC8034_CROP_LEFT },
-	{ GC8034_REG_OUT_HEIGHT, GC8034_HEIGHT },
-	{ GC8034_REG_OUT_WIDTH, GC8034_WIDTH },
 	/* DPC */
 	{ GC8034_REG_PAGE_SELECT, 0x01 },
 	{ CCI_REG8(0x62), 0x60 },
@@ -368,8 +396,6 @@
 	{ CCI_REG8(0x02), 0x03 },
 	{ CCI_REG8(0x04), 0x80 },
 	{ CCI_REG8(0x11), 0x2b },
-	{ CCI_REG8(0x12), 0xf0 },
-	{ CCI_REG8(0x13), 0x0f },
 	{ CCI_REG8(0x15), 0x10 },
 	{ CCI_REG8(0x16), 0x29 },
 	{ CCI_REG8(0x17), 0xff },
@@ -470,28 +496,52 @@
 	if (fse->index > 0)
 		return -EINVAL;
 
-	fse->min_width = GC8034_WIDTH;
-	fse->max_width = GC8034_WIDTH;
-	fse->min_height = GC8034_HEIGHT;
-	fse->max_height = GC8034_HEIGHT;
+	/* The output size is the size of the crop rectangle. */
+	fse->min_width = GC8034_MIN_WIDTH;
+	fse->max_width = GC8034_MAX_WIDTH;
+	fse->min_height = GC8034_MIN_HEIGHT;
+	fse->max_height = GC8034_MAX_HEIGHT;
 
 	return 0;
 }
 
-static void gc8034_fill_state(struct v4l2_subdev_state *state)
+/*
+ * Update the controls that depend on the output size. Called with the state
+ * lock held, which is also the control handler lock.
+ */
+static int gc8034_update_ctrls(struct gc8034 *gc8034,
+			       const struct v4l2_mbus_framefmt *format)
 {
-	struct v4l2_mbus_framefmt *fmt;
-	struct v4l2_rect *crop;
+	s64 exposure_max;
+	int ret;
 
-	crop = v4l2_subdev_state_get_crop(state, 0);
-	crop->left = GC8034_CROP_LEFT;
-	crop->top = GC8034_CROP_TOP;
-	crop->width = GC8034_WIDTH;
-	crop->height = GC8034_HEIGHT;
+	ret = __v4l2_ctrl_modify_range(gc8034->hblank,
+				       GC8034_HTS - format->width,
+				       GC8034_HTS - format->width, 1,
+				       GC8034_HTS - format->width);
+	if (ret)
+		return ret;
+
+	ret = __v4l2_ctrl_modify_range(gc8034->vblank, GC8034_VBLANK_MIN,
+				       GC8034_VTS_MAX - format->height, 1,
+				       GC8034_VBLANK_MIN);
+	if (ret)
+		return ret;
+
+	exposure_max = round_down(format->height + gc8034->vblank->val -
+				  GC8034_EXP_MARGIN, GC8034_EXP_STEP);
+
+	return __v4l2_ctrl_modify_range(gc8034->exposure, GC8034_EXP_MIN,
+					exposure_max, GC8034_EXP_STEP,
+					min_t(s64, GC8034_EXP_DEF,
+					      exposure_max));
+}
 
-	fmt = v4l2_subdev_state_get_format(state, 0);
-	fmt->width = GC8034_WIDTH;
-	fmt->height = GC8034_HEIGHT;
+static void gc8034_fill_format(struct v4l2_mbus_framefmt *fmt,
+			       const struct v4l2_rect *crop)
+{
+	fmt->width = crop->width;
+	fmt->height = crop->height;
 	fmt->code = GC8034_MBUS_CODE;
 	fmt->field = V4L2_FIELD_NONE;
 	fmt->colorspace = V4L2_COLORSPACE_RAW;
@@ -519,8 +569,8 @@
 	case V4L2_SEL_TGT_NATIVE_SIZE:
 		sel->r.top = 0;
 		sel->r.left = 0;
-		sel->r.width = GC8034_NATIVE_WIDTH;
-		sel->r.height = GC8034_NATIVE_HEIGHT;
+		sel->r.width = GC8034_AREA_WIDTH;
+		sel->r.height = GC8034_AREA_HEIGHT;
 		break;
 	default:
 		return -EINVAL;
@@ -529,10 +579,104 @@
 	return 0;
 }
 
+static int gc8034_set_selection(struct v4l2_subdev *sd,
+				const struct v4l2_subdev_client_info *ci,
+				struct v4l2_subdev_state *state,
+				struct v4l2_subdev_selection *sel)
+{
+	struct gc8034 *gc8034 = to_gc8034(sd);
+	struct v4l2_mbus_framefmt *format;
+	struct v4l2_rect rect;
+
+	if (sel->target != V4L2_SEL_TGT_CROP)
+		return -EINVAL;
+
+	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
+	    v4l2_subdev_is_streaming(sd))
+		return -EBUSY;
+
+	/*
+	 * Even offsets keep the RGGB order. The width is a multiple of 4 so
+	 * that RAW10 lines are a whole number of bytes; only heights that are
+	 * multiples of 4 have been tested.
+	 */
+	rect.left = ALIGN_DOWN(clamp(sel->r.left, 0,
+				     GC8034_AREA_WIDTH - GC8034_MIN_WIDTH), 2);
+	rect.top = ALIGN_DOWN(clamp(sel->r.top, 0,
+				    GC8034_AREA_HEIGHT - GC8034_MIN_HEIGHT), 2);
+	rect.width = ALIGN_DOWN(clamp_t(u32, sel->r.width, GC8034_MIN_WIDTH,
+					min(GC8034_MAX_WIDTH,
+					    GC8034_AREA_WIDTH - rect.left)), 4);
+	rect.height = ALIGN_DOWN(clamp_t(u32, sel->r.height, GC8034_MIN_HEIGHT,
+					 min(GC8034_MAX_HEIGHT,
+					     GC8034_AREA_HEIGHT - rect.top)), 4);
+
+	*v4l2_subdev_state_get_crop(state, 0) = rect;
+	sel->r = rect;
+
+	/* No binning or scaling: the output size is the crop size. */
+	format = v4l2_subdev_state_get_format(state, 0);
+	gc8034_fill_format(format, &rect);
+
+	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE)
+		return gc8034_update_ctrls(gc8034, format);
+
+	return 0;
+}
+
+/*
+ * No binning or scaling: the output size is the size of the crop rectangle. A
+ * new size moves the crop rectangle to the centre of the area, for userspace
+ * that does not set the crop rectangle first.
+ */
+static int gc8034_set_fmt(struct v4l2_subdev *sd,
+			  const struct v4l2_subdev_client_info *ci,
+			  struct v4l2_subdev_state *state,
+			  struct v4l2_subdev_format *fmt)
+{
+	struct gc8034 *gc8034 = to_gc8034(sd);
+	struct v4l2_mbus_framefmt *format;
+	struct v4l2_rect *crop;
+	u32 width, height;
+
+	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
+	    v4l2_subdev_is_streaming(sd))
+		return -EBUSY;
+
+	width = ALIGN_DOWN(clamp_t(u32, fmt->format.width, GC8034_MIN_WIDTH,
+				   GC8034_MAX_WIDTH), 4);
+	height = ALIGN_DOWN(clamp_t(u32, fmt->format.height, GC8034_MIN_HEIGHT,
+				    GC8034_MAX_HEIGHT), 4);
+
+	crop = v4l2_subdev_state_get_crop(state, 0);
+	if (width != crop->width || height != crop->height) {
+		crop->left = ALIGN_DOWN((GC8034_AREA_WIDTH - width) / 2, 2);
+		crop->top = ALIGN_DOWN((GC8034_AREA_HEIGHT - height) / 2, 2);
+		crop->width = width;
+		crop->height = height;
+	}
+
+	format = v4l2_subdev_state_get_format(state, 0);
+	gc8034_fill_format(format, crop);
+	fmt->format = *format;
+
+	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE)
+		return gc8034_update_ctrls(gc8034, format);
+
+	return 0;
+}
+
 static int gc8034_init_state(struct v4l2_subdev *sd,
 			     struct v4l2_subdev_state *state)
 {
-	gc8034_fill_state(state);
+	struct v4l2_rect *crop = v4l2_subdev_state_get_crop(state, 0);
+
+	crop->left = GC8034_CROP_LEFT;
+	crop->top = GC8034_CROP_TOP;
+	crop->width = GC8034_WIDTH;
+	crop->height = GC8034_HEIGHT;
+
+	gc8034_fill_format(v4l2_subdev_state_get_format(state, 0), crop);
 
 	return 0;
 }
@@ -581,7 +725,9 @@
 					  GC8034_EXP_MARGIN, GC8034_EXP_STEP);
 		ret = __v4l2_ctrl_modify_range(gc8034->exposure,
 					       GC8034_EXP_MIN, exposure_max,
-					       GC8034_EXP_STEP, GC8034_EXP_DEF);
+					       GC8034_EXP_STEP,
+					       min_t(s64, GC8034_EXP_DEF,
+						     exposure_max));
 		if (ret)
 			return ret;
 	}
@@ -605,8 +751,7 @@
 	case V4L2_CID_VBLANK:
 		/* The register holds an offset, not the VTS. */
 		ret = cci_write(gc8034->regmap, GC8034_REG_BLANKING,
-				format->height + ctrl->val -
-				GC8034_VTS_OFFSET, NULL);
+				ctrl->val - GC8034_BLANKING_OFFSET, NULL);
 		break;
 	default:
 		ret = -EINVAL;
@@ -641,6 +786,37 @@
 	return 0;
 }
 
+static int gc8034_write_geometry(struct gc8034 *gc8034,
+				 const struct v4l2_rect *crop)
+{
+	int ret = 0;
+
+	cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0, &ret);
+
+	/* Readout window: vendor columns, the rows of the crop rectangle. */
+	cci_write(gc8034->regmap, GC8034_REG_WIN_TOP,
+		  crop->top + GC8034_ROW_START_OFFSET, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_WIN_LEFT, GC8034_WIN_LEFT, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_WIN_HEIGHT,
+		  crop->height + GC8034_WIN_EXTRA_ROWS, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_WIN_WIDTH, GC8034_WIN_WIDTH, &ret);
+
+	/* Output crop: the columns of the crop rectangle. */
+	cci_write(gc8034->regmap, GC8034_REG_CROP_TOP, GC8034_OUT_TOP, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_CROP_LEFT,
+		  crop->left + GC8034_OUT_LEFT_OFFSET, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_OUT_HEIGHT, crop->height, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_OUT_WIDTH, crop->width, &ret);
+
+	/* RAW10: 5 bytes per 4 pixels. */
+	cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_3, &ret);
+	cci_write(gc8034->regmap, GC8034_REG_LINE_BYTES, crop->width * 5 / 4,
+		  &ret);
+	cci_write(gc8034->regmap, GC8034_REG_PAGE_SELECT, GC8034_PAGE_0, &ret);
+
+	return ret;
+}
+
 static int gc8034_enable_streams(struct v4l2_subdev *sd,
 				 struct v4l2_subdev_state *state,
 				 u32 pad, u64 streams_mask)
@@ -657,6 +833,11 @@
 	if (ret)
 		goto err_rpm_put;
 
+	ret = gc8034_write_geometry(gc8034,
+				    v4l2_subdev_state_get_crop(state, 0));
+	if (ret)
+		goto err_rpm_put;
+
 	ret = __v4l2_ctrl_handler_setup(&gc8034->ctrls);
 	if (ret)
 		goto err_rpm_put;
@@ -698,7 +879,9 @@
 	.enum_mbus_code = gc8034_enum_mbus_code,
 	.enum_frame_size = gc8034_enum_frame_size,
 	.get_fmt = v4l2_subdev_get_fmt,
+	.set_fmt = gc8034_set_fmt,
 	.get_selection = gc8034_get_selection,
+	.set_selection = gc8034_set_selection,
 	.get_frame_desc = gc8034_get_frame_desc,
 	.enable_streams = gc8034_enable_streams,
 	.disable_streams = gc8034_disable_streams,
@@ -754,7 +937,7 @@
 {
 	struct v4l2_fwnode_device_properties props;
 	struct v4l2_ctrl_handler *ctrl_hdlr;
-	struct v4l2_ctrl *link_freq, *hblank;
+	struct v4l2_ctrl *link_freq;
 	s64 exposure_max;
 	int ret;
 
@@ -773,17 +956,18 @@
 			  GC8034_PIXEL_RATE, GC8034_PIXEL_RATE, 1,
 			  GC8034_PIXEL_RATE);
 
-	v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops, V4L2_CID_VBLANK,
-			  GC8034_VTS_DEF - GC8034_HEIGHT,
-			  GC8034_VTS_MAX - GC8034_HEIGHT, 1,
-			  GC8034_VTS_DEF - GC8034_HEIGHT);
-
-	hblank = v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_HBLANK,
-				   GC8034_HTS - GC8034_WIDTH,
-				   GC8034_HTS - GC8034_WIDTH, 1,
-				   GC8034_HTS - GC8034_WIDTH);
+	/* Ranges for the default crop rectangle, see gc8034_update_ctrls(). */
+	gc8034->vblank = v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
+					   V4L2_CID_VBLANK, GC8034_VBLANK_MIN,
+					   GC8034_VTS_MAX - GC8034_HEIGHT, 1,
+					   GC8034_VBLANK_MIN);
+
+	gc8034->hblank = v4l2_ctrl_new_std(ctrl_hdlr, NULL, V4L2_CID_HBLANK,
+					   GC8034_HTS - GC8034_WIDTH,
+					   GC8034_HTS - GC8034_WIDTH, 1,
+					   GC8034_HTS - GC8034_WIDTH);
 
-	exposure_max = GC8034_VTS_DEF - GC8034_EXP_MARGIN;
+	exposure_max = GC8034_HEIGHT + GC8034_VBLANK_MIN - GC8034_EXP_MARGIN;
 	gc8034->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &gc8034_ctrl_ops,
 					     V4L2_CID_EXPOSURE, GC8034_EXP_MIN,
 					     exposure_max, GC8034_EXP_STEP,
@@ -798,7 +982,7 @@
 		return v4l2_ctrl_handler_free(ctrl_hdlr);
 
 	link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;
-	hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;
+	gc8034->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;
 
 	gc8034->sd.ctrl_handler = ctrl_hdlr;
 
```

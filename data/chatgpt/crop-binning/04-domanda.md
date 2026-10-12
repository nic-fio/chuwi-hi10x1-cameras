# Revisione di un cambio di semantica in set_fmt (GC5035, binning 2x2)

Contesto: driver V4L2 per il sensore GC5035 (2592x1944 attivi, area 2608x1964), serie upstream v2 non ancora inviata. Il crop è configurabile con set_selection (richiesta di Laurent Pinchart sulla v1). Il commit 7 aggiunge il binning 2x2 (1296x972, stesso campo del crop di default), con LINK_FREQ 175,2 MHz e PIXEL_RATE propri.

Regola vecchia: set_fmt a 1296x972 sceglie il binning solo se il crop corrente è quello di default (8,8,2592,1944). Altrimenti l'uscita è grande quanto il crop, e un nuovo width/height ricentra il crop.

Problema misurato oggi sul tablet: durante configure() libcamera (pipeline simple, CameraSensorLegacy) fa set_fmt ACTIVE 1296x972, poi 2608x1964 (che porta il crop all'area intera), poi di nuovo 1296x972. A quel punto il crop non è più quello di default e il driver dà un crop centrale 1296x972 senza binning: con libcamera il binning non si ottiene mai (28,8 fps e campo ridotto invece di 24 fps col campo intero).

Regola nuova (sotto il diff): set_fmt a 1296x972 sceglie il binning e riporta il crop al default, tranne quando il crop corrente è già 1296x972. Quel caso tiene il crop impostato prima (ordine media-ctl crop -> fmt) senza binning.

Misurato col modulo nuovo: libcamera a 1280x960 va a 24,01 fps (binning); crop 1296x972 + set_fmt 1296x972 resta non binnato; 2608x1964 -> 1296x972 dà il binning; 1296x972 ripetuto è idempotente; 2592x1944 torna al pieno. prova-binning 20/20, crop 0 KO, v4l2-compliance 54/54 in entrambi i modi.

Domande:
1. La regola nuova è difendibile per i maintainer media (Sakari, Laurent, Hans)? Ci sono casi in cui sorprende l'utente o viola la semantica dei subdev (TRY/ACTIVE, propagazione crop -> fmt, idempotenza di S_FMT con G_FMT)?
2. Rimane un caso ambiguo: in binning (crop 2592x1944) l'utente imposta un crop 1296x972, che riporta l'uscita a crop-size non binnata. È coerente?
3. Ci sono alternative migliori e mantenibili senza cambiare il core (ad esempio un controllo, oppure set_selection su V4L2_SEL_TGT_COMPOSE)? Rispondi in breve e indica i difetti concreti, se ce ne sono.

```diff
diff --git a/drivers/media/i2c/gc5035.c b/drivers/media/i2c/gc5035.c
index 4cfac6530..fbb1ac813 100644
--- a/drivers/media/i2c/gc5035.c
+++ b/drivers/media/i2c/gc5035.c
@@ -36,7 +36,6 @@
 #include <media/v4l2-common.h>
 #include <media/v4l2-ctrls.h>
 #include <media/v4l2-fwnode.h>
-#include <media/v4l2-rect.h>
 #include <media/v4l2-subdev.h>
 
 /*
@@ -732,12 +731,15 @@ static int gc5035_set_selection(struct v4l2_subdev *sd,
 }
 
 /*
- * Half the size of the default crop rectangle, when it is the current one,
- * selects 2x2 binning. Otherwise the output size is the size of the crop
- * rectangle: a new width or height centres the crop rectangle on the default
- * crop rectangle along that axis, within the area, for userspace that does
- * not set the crop rectangle first. The default size gives the default
- * rectangle back.
+ * Half the size of the default crop rectangle selects 2x2 binning and sets
+ * the default crop rectangle back, unless the crop rectangle already has
+ * that size: binning does not depend on the crop rectangle left by earlier
+ * calls (libcamera sets the largest size, then the one it wants), and a crop
+ * rectangle of that size set first is kept, without binning. Otherwise the
+ * output size is the size of the crop rectangle: a new width or height
+ * centres the crop rectangle on the default crop rectangle along that axis,
+ * within the area, for userspace that does not set the crop rectangle first.
+ * The default size gives the default rectangle back.
  */
 static int gc5035_set_fmt(struct v4l2_subdev *sd,
 			  const struct v4l2_subdev_client_info *ci,
@@ -767,8 +769,11 @@ static int gc5035_set_fmt(struct v4l2_subdev *sd,
 				    GC5035_AREA_HEIGHT), 4);
 
 	crop = v4l2_subdev_state_get_crop(state, 0);
-	bin = gc5035->binning && v4l2_rect_equal(crop, &crop_default) &&
-	      width == crop->width / 2 && height == crop->height / 2 ? 2 : 1;
+	bin = gc5035->binning && width == GC5035_WIDTH / 2 &&
+	      height == GC5035_HEIGHT / 2 &&
+	      (width != crop->width || height != crop->height) ? 2 : 1;
+	if (bin == 2)
+		*crop = crop_default;
 	if (bin == 1 && width != crop->width) {
 		pos = GC5035_CROP_LEFT + (GC5035_WIDTH - (int)width) / 2;
 		pos = clamp(pos, 0, GC5035_AREA_WIDTH - (int)width);
```

Funzioni di contorno (set_selection, set_fmt completo):
```c
static int gc5035_set_selection(struct v4l2_subdev *sd,
				const struct v4l2_subdev_client_info *ci,
				struct v4l2_subdev_state *state,
				struct v4l2_subdev_selection *sel)
{
	struct gc5035 *gc5035 = to_gc5035(sd);
	struct v4l2_mbus_framefmt *format;
	struct v4l2_rect rect;

	if (sel->target != V4L2_SEL_TGT_CROP)
		return -EINVAL;

	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
	    v4l2_subdev_is_streaming(sd))
		return -EBUSY;

	/*
	 * Even offsets keep the GRBG order. The sizes are multiples of 4: the
	 * sensor rounds the frame length to a multiple of 4 lines.
	 */
	rect.left = ALIGN_DOWN(clamp(sel->r.left, 0,
				     GC5035_AREA_WIDTH - GC5035_MIN_WIDTH), 2);
	rect.top = ALIGN_DOWN(clamp(sel->r.top, 0,
				    GC5035_AREA_HEIGHT - GC5035_MIN_HEIGHT), 2);
	rect.width = ALIGN_DOWN(clamp_t(u32, sel->r.width, GC5035_MIN_WIDTH,
					GC5035_AREA_WIDTH - rect.left), 4);
	rect.height = ALIGN_DOWN(clamp_t(u32, sel->r.height, GC5035_MIN_HEIGHT,
					 GC5035_AREA_HEIGHT - rect.top), 4);

	*v4l2_subdev_state_get_crop(state, 0) = rect;
	sel->r = rect;

	/* A new crop rectangle disables binning: the output is its size. */
	format = v4l2_subdev_state_get_format(state, 0);
	gc5035_fill_format(format, &rect, 1);

	if (sel->which == V4L2_SUBDEV_FORMAT_ACTIVE)
		return gc5035_update_ctrls(gc5035, &rect, format);

	return 0;
}

/*
 * Half the size of the default crop rectangle selects 2x2 binning and sets
 * the default crop rectangle back, unless the crop rectangle already has
 * that size: binning does not depend on the crop rectangle left by earlier
 * calls (libcamera sets the largest size, then the one it wants), and a crop
 * rectangle of that size set first is kept, without binning. Otherwise the
 * output size is the size of the crop rectangle: a new width or height
 * centres the crop rectangle on the default crop rectangle along that axis,
 * within the area, for userspace that does not set the crop rectangle first.
 * The default size gives the default rectangle back.
 */
static int gc5035_set_fmt(struct v4l2_subdev *sd,
			  const struct v4l2_subdev_client_info *ci,
			  struct v4l2_subdev_state *state,
			  struct v4l2_subdev_format *fmt)
{
	static const struct v4l2_rect crop_default = {
		.left = GC5035_CROP_LEFT,
		.top = GC5035_CROP_TOP,
		.width = GC5035_WIDTH,
		.height = GC5035_HEIGHT,
	};
	struct gc5035 *gc5035 = to_gc5035(sd);
	struct v4l2_mbus_framefmt *format;
	struct v4l2_rect *crop;
	u32 width, height;
	unsigned int bin;
	int pos;

	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE &&
	    v4l2_subdev_is_streaming(sd))
		return -EBUSY;

	width = ALIGN_DOWN(clamp_t(u32, fmt->format.width, GC5035_MIN_WIDTH,
				   GC5035_AREA_WIDTH), 4);
	height = ALIGN_DOWN(clamp_t(u32, fmt->format.height, GC5035_MIN_HEIGHT,
				    GC5035_AREA_HEIGHT), 4);

	crop = v4l2_subdev_state_get_crop(state, 0);
	bin = gc5035->binning && width == GC5035_WIDTH / 2 &&
	      height == GC5035_HEIGHT / 2 &&
	      (width != crop->width || height != crop->height) ? 2 : 1;
	if (bin == 2)
		*crop = crop_default;
	if (bin == 1 && width != crop->width) {
		pos = GC5035_CROP_LEFT + (GC5035_WIDTH - (int)width) / 2;
		pos = clamp(pos, 0, GC5035_AREA_WIDTH - (int)width);
		crop->left = ALIGN_DOWN(pos, 2);
		crop->width = width;
	}
	if (bin == 1 && height != crop->height) {
		pos = GC5035_CROP_TOP + (GC5035_HEIGHT - (int)height) / 2;
		pos = clamp(pos, 0, GC5035_AREA_HEIGHT - (int)height);
		crop->top = ALIGN_DOWN(pos, 2);
		crop->height = height;
	}

	format = v4l2_subdev_state_get_format(state, 0);
	gc5035_fill_format(format, crop, bin);
	fmt->format = *format;

	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE)
		return gc5035_update_ctrls(gc5035, crop, format);

	return 0;
}

static int gc5035_init_state(struct v4l2_subdev *sd,
```

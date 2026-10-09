#!/usr/bin/env python3
# mk-lab.py — genera la versione "da laboratorio" di gc5035.c / gc8034.c.
#
# SOLO PER ESPERIMENTI, MAI UPSTREAM. Aggiunge al driver spedito:
#  - set_fmt che accetta qualunque dimensione pari (16..4096) e uno dei
#    quattro codici Bayer a 10 bit, cosi' la pipeline IPU6 si adatta a quello
#    che i registri fanno uscire dal sensore;
#  - /sys/kernel/debug/<sensore>-lab/regs: lista di scritture "pagina reg
#    valore" (esadecimali o decimali), applicate dopo la tabella del driver e
#    prima dei controlli e dello stream on. Scrivere una riga vuota svuota.
#
# Uso: mk-lab.py gc5035 sorgente.c uscita.c

import sys

name, src, dst = sys.argv[1:4]
P = name.upper()
s = open(src, encoding="utf-8").read()


def sub(old, new, count=1):
    global s
    n = s.count(old)
    if n != count:
        sys.exit(f"{name}: atteso {count} occorrenze, trovate {n}: {old!r}")
    s = s.replace(old, new)


sub("#include <linux/units.h>\n",
    "#include <linux/units.h>\n"
    "#include <linux/debugfs.h>\n"
    "#include <linux/mutex.h>\n"
    "#include <linux/slab.h>\n"
    "#include <linux/string.h>\n"
    "#include <linux/uaccess.h>\n")

sub("\tstruct regmap *regmap;\n};\n",
    "\tstruct regmap *regmap;\n\n"
    "\t/* LAB */\n"
    "\tstruct dentry *lab_dir;\n"
    "\tstruct mutex lab_lock;\n"
    "\tunsigned int lab_nregs;\n"
    "\tu8 lab_regs[256][3];\n"
    "};\n")

# enum_mbus_code: i quattro ordini Bayer
sub(f"""\tif (code->index > 0)
		return -EINVAL;

	code->code = {P}_MBUS_CODE;
""", f"""\tif (code->index >= ARRAY_SIZE(lab_codes))
		return -EINVAL;

	code->code = lab_codes[code->index];
""")

sub(f"""\tif (fse->code != {P}_MBUS_CODE)
		return -EINVAL;

	if (fse->index > 0)
		return -EINVAL;

	fse->min_width = {P}_WIDTH;
	fse->max_width = {P}_WIDTH;
	fse->min_height = {P}_HEIGHT;
	fse->max_height = {P}_HEIGHT;
""", f"""\tif (fse->index > 0)
		return -EINVAL;

	fse->min_width = LAB_MIN;
	fse->max_width = LAB_MAX;
	fse->min_height = LAB_MIN;
	fse->max_height = LAB_MAX;
""")

lab_top = f"""
/* ------------------------------ LAB ------------------------------ */
#define LAB_MIN 16
#define LAB_MAX 4096

static const u32 lab_codes[] = {{
	{P}_MBUS_CODE,
	MEDIA_BUS_FMT_SRGGB10_1X10,
	MEDIA_BUS_FMT_SGRBG10_1X10,
	MEDIA_BUS_FMT_SGBRG10_1X10,
	MEDIA_BUS_FMT_SBGGR10_1X10,
}};

static int lab_set_fmt(struct v4l2_subdev *sd,
		       const struct v4l2_subdev_client_info *ci,
		       struct v4l2_subdev_state *state,
		       struct v4l2_subdev_format *fmt)
{{
	struct v4l2_mbus_framefmt *f = v4l2_subdev_state_get_format(state, 0);
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(lab_codes); i++)
		if (fmt->format.code == lab_codes[i])
			break;
	f->code = i < ARRAY_SIZE(lab_codes) ? lab_codes[i] : {P}_MBUS_CODE;
	f->width = clamp_t(u32, fmt->format.width & ~1U, LAB_MIN, LAB_MAX);
	f->height = clamp_t(u32, fmt->format.height & ~1U, LAB_MIN, LAB_MAX);
	fmt->format = *f;

	return 0;
}}

static ssize_t lab_regs_read(struct file *file, char __user *ubuf,
			     size_t count, loff_t *ppos)
{{
	struct {name} *s = file->private_data;
	unsigned int i, len = 0;
	ssize_t ret;
	char *buf;

	buf = kzalloc(256 * 16, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	mutex_lock(&s->lab_lock);
	for (i = 0; i < s->lab_nregs; i++)
		len += scnprintf(buf + len, 256 * 16 - len, "%u 0x%02x 0x%02x\\n",
				 s->lab_regs[i][0], s->lab_regs[i][1],
				 s->lab_regs[i][2]);
	mutex_unlock(&s->lab_lock);

	ret = simple_read_from_buffer(ubuf, count, ppos, buf, len);
	kfree(buf);

	return ret;
}}

static ssize_t lab_regs_write(struct file *file, const char __user *ubuf,
			      size_t count, loff_t *ppos)
{{
	struct {name} *s = file->private_data;
	char *buf, *p, *tok;
	unsigned int n = 0, v[3], k = 0;
	u8 regs[256][3];

	if (count > 8192)
		return -EINVAL;

	buf = memdup_user_nul(ubuf, count);
	if (IS_ERR(buf))
		return PTR_ERR(buf);

	p = buf;
	while ((tok = strsep(&p, " \\t\\n,")) != NULL) {{
		if (!*tok)
			continue;
		if (kstrtouint(tok, 0, &v[k]) || v[k] > 0xff) {{
			kfree(buf);
			return -EINVAL;
		}}
		if (++k == 3) {{
			if (n == ARRAY_SIZE(regs)) {{
				kfree(buf);
				return -ENOSPC;
			}}
			regs[n][0] = v[0];
			regs[n][1] = v[1];
			regs[n][2] = v[2];
			n++;
			k = 0;
		}}
	}}
	kfree(buf);
	if (k)
		return -EINVAL;

	mutex_lock(&s->lab_lock);
	memcpy(s->lab_regs, regs, sizeof(regs[0]) * n);
	s->lab_nregs = n;
	mutex_unlock(&s->lab_lock);

	return count;
}}

static const struct file_operations lab_regs_fops = {{
	.owner = THIS_MODULE,
	.open = simple_open,
	.read = lab_regs_read,
	.write = lab_regs_write,
	.llseek = default_llseek,
}};

static int lab_apply(struct {name} *s)
{{
	unsigned int i;
	int ret = 0;

	mutex_lock(&s->lab_lock);
	for (i = 0; i < s->lab_nregs; i++) {{
		cci_write(s->regmap, {P}_REG_PAGE_SELECT, s->lab_regs[i][0], &ret);
		cci_write(s->regmap, CCI_REG8(s->lab_regs[i][1]),
			  s->lab_regs[i][2], &ret);
	}}
	if (s->lab_nregs)
		cci_write(s->regmap, {P}_REG_PAGE_SELECT, 0, &ret);
	mutex_unlock(&s->lab_lock);

	if (s->lab_nregs)
		dev_info(s->dev, "lab: %u scritture, ret %d\\n", s->lab_nregs, ret);

	return ret;
}}
/* ---------------------------------------------------------------- */

static int {name}_enum_mbus_code("""

sub(f"\nstatic int {name}_enum_mbus_code(", lab_top)

# applicare le scritture dopo la tabella
sub(f"""\tret = cci_multi_reg_write({name}->regmap, {name}_regs,
""", f"""\tret = cci_multi_reg_write({name}->regmap, {name}_regs,
""")
old_after = f"ARRAY_SIZE({name}_regs), NULL);\n\tif (ret)\n\t\tgoto err_rpm_put;\n"
sub(old_after, old_after + f"\n\tret = lab_apply({name});\n\tif (ret)\n\t\tgoto err_rpm_put;\n")

sub("\t.get_fmt = v4l2_subdev_get_fmt,\n",
    "\t.get_fmt = v4l2_subdev_get_fmt,\n\t.set_fmt = lab_set_fmt,\n")

# debugfs dopo la registrazione
sub("\tpm_runtime_idle(dev);\n\n\treturn 0;\n",
    f"\tmutex_init(&{name}->lab_lock);\n"
    f"\t{name}->lab_dir = debugfs_create_dir(\"{name}-lab\", NULL);\n"
    f"\tdebugfs_create_file(\"regs\", 0600, {name}->lab_dir, {name},\n"
    "\t\t\t    &lab_regs_fops);\n\n"
    "\tpm_runtime_idle(dev);\n\n\treturn 0;\n")

sub("\tv4l2_async_unregister_subdev(sd);\n",
    f"\tdebugfs_remove_recursive({name}->lab_dir);\n"
    "\tv4l2_async_unregister_subdev(sd);\n")

sub('MODULE_LICENSE("GPL");', 'MODULE_LICENSE("GPL");\nMODULE_INFO(lab, "SOLO ESPERIMENTI");')

open(dst, "w", encoding="utf-8").write(s)
print(f"{dst}: scritto")

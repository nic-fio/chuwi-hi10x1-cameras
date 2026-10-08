import sys
n = sys.argv[1]
N = n.upper()
p = f"drivers/media/i2c/{n}.c"
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)
# solo la frequenza di clock provata
rep(f"#define {N}_LINK_FREQ_MULTIPLIER",
    f"/* The only external clock rate the register tables have been tested at. */\n"
    f"#define {N}_XCLK_FREQ\t\t\t(19200 * HZ_PER_KHZ)\n"
    f"#define {N}_LINK_FREQ_MULTIPLIER")
var = "freq" if n == "gc5035" else "gc8034->xclk_rate"
rep(f"\tif (!{var})\n\t\treturn dev_err_probe(dev, -EINVAL,\n"
    "\t\t\t\t     \"external clock rate is unknown\\n\");\n",
    f"\tif ({var} != {N}_XCLK_FREQ)\n\t\treturn dev_err_probe(dev, -EINVAL,\n"
    "\t\t\t\t     \"external clock %lu Hz not supported\\n\",\n"
    f"\t\t\t\t     {var});\n")
if "#include <linux/units.h>\n" not in s:
    rep("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/units.h>\n")
open(p, "w").write(s)

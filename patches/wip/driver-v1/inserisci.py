# Aggiunge Kconfig, Makefile, MAINTAINERS (per un driver) o la voce
# ipu-bridge. Si lancia dalla radice del sorgente del kernel.
import sys
quale = sys.argv[1]

def ins(path, after, text):
    s = open(path).read()
    assert s.count(after) == 1, (path, after)
    assert text not in s, (path, "gia' presente")
    s = s.replace(after, after + text)
    open(path, "w").write(s)

DESC = {"gc5035": "5 Mpixel", "gc8034": "8 Mpixel"}
PREV = {"gc5035": "gc2145", "gc8034": "gc5035"}

if quale in DESC:
    n, N, p = quale, quale.upper(), PREV[quale]
    ins("drivers/media/i2c/Kconfig",
        f"\t  module will be called {p}.\n\n",
        f"config VIDEO_{N}\n"
        f"\ttristate \"GalaxyCore {N} sensor support\"\n"
        "\tselect V4L2_CCI_I2C\n\thelp\n"
        f"\t  This is a Video4Linux2 sensor driver for the GalaxyCore {N}\n"
        f"\t  {DESC[n]} camera.\n\n"
        "\t  To compile this driver as a module, choose M here: the\n"
        f"\t  module will be called {n}.\n\n")
    ins("drivers/media/i2c/Makefile",
        f"obj-$(CONFIG_VIDEO_{p.upper()}) += {p}.o\n",
        f"obj-$(CONFIG_VIDEO_{N}) += {n}.o\n")
    anchor = (f"F:\tdrivers/media/i2c/{p}.c\n\n")
    ins("MAINTAINERS", anchor,
        f"GALAXYCORE {N} CAMERA SENSOR DRIVER\n"
        "M:\tNicola Fiorillo <nicfio@gmail.com>\n"
        "L:\tlinux-media@vger.kernel.org\n"
        "S:\tMaintained\n"
        f"F:\tdrivers/media/i2c/{n}.c\n\n")
elif quale == "ipu-bridge":
    ins("drivers/media/pci/intel/ipu-bridge.c",
        "static const struct ipu_sensor_config ipu_supported_sensors[] = {\n",
        "\t/* GalaxyCore GC5035 */\n"
        "\tIPU_SENSOR_CONFIG(\"GCTI5035\", 1, 422400000),\n"
        "\t/* GalaxyCore GC8034 */\n"
        "\tIPU_SENSOR_CONFIG(\"GCTI8034\", 1, 268800000),\n")
else:
    sys.exit("uso: inserisci.py gc5035|gc8034|ipu-bridge")

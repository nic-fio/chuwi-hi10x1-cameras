import sys
n = sys.argv[1]
p = f"drivers/media/i2c/{n}.c"
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)
# link_freq_bitmap: mai letto dopo la validazione, variabile locale
rep("\ts64 link_freq_menu[1];\n\tunsigned long link_freq_bitmap;\n", "\ts64 link_freq_menu[1];\n")
rep(f"\tstruct device *dev = {n}->dev;\n\tstruct fwnode_handle *endpoint;\n\tint ret;\n",
    f"\tstruct device *dev = {n}->dev;\n\tstruct fwnode_handle *endpoint;\n\tunsigned long link_freq_bitmap;\n\tint ret;\n")
rep(f"\t\t\t\t       &{n}->link_freq_bitmap);", "\t\t\t\t       &link_freq_bitmap);")
open(p, "w").write(s)

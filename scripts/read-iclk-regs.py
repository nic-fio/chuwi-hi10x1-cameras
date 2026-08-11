#!/usr/bin/env python3
import re, sys

DSL = "/tmp/claude-1000/-home-nicfio-INTEL-CAMERA/3696b950-c5a7-4e7e-8e80-d1e58be442e2/scratchpad/dsdt.dsl"
PNVB, PNVL = 0x758BFB18, 0x0371

lines = open(DSL).readlines()
# il Field (PNVA...) comincia alla riga 10038 (1-based) -> indice 10037
i = 10037
assert "Field (PNVA" in lines[i], lines[i]
i += 2  # salta "{"
bitpos, table = 0, {}
while "}" not in lines[i].strip()[:1] and i < len(lines):
    s = lines[i].strip()
    if s == "}":
        break
    m = re.match(r'Offset \(0x([0-9A-Fa-f]+)\)', s)
    if m:
        bitpos = int(m.group(1), 16) * 8
    else:
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)?\s*,\s*(\d+)\s*,?', s)
        if m:
            if m.group(1):
                table[m.group(1)] = (bitpos // 8, int(m.group(2)))
            bitpos += int(m.group(2))
    i += 1

fh = open("/dev/mem", "rb")
def rd(addr, n):
    fh.seek(addr); return fh.read(n)

blob = rd(PNVB, PNVL)
def val(name):
    if name not in table:
        return None
    off, w = table[name]
    return int.from_bytes(blob[off:off + w // 8], "little")

pchs, sbrg, ickp = val("PCHS"), val("SBRG"), val("ICKP")
print("campi PNVA risolti: %d" % len(table))
print("PCHS = 0x%02x  (PCHN=0x03 Alder Lake-N, PCHP=0x05)" % pchs)
print("SBRG = 0x%08X   (SBREG_BAR)" % sbrg)
print("ICKP = 0x%02X       (port ID ISCLK)" % ickp)

base = sbrg + (ickp << 16) + 0x8000
print("\nICLK/CKOR @ 0x%08X" % base)
reg = rd(base, 0x40)
names = [("CLK0", 0x00), ("CLK1", 0x0C), ("CLK2", 0x18), ("CLK3", 0x24)]
print("%-6s %-8s %-10s %-14s %s" % ("reg", "offset", "valore", "bit0=freq", "bit1=enable"))
for n, o in names:
    v = reg[o]
    print("%-6s 0x%02x     0x%02x       %-14s %s" % (n, o, v, v & 1, (v >> 1) & 1))
fh.close()

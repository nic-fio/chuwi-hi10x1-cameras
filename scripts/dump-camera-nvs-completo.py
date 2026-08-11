#!/usr/bin/env python3
import os, sys
sys.path.insert(0, "/home/nicfio/INTEL-CAMERA/scripts")
GNVS_ADDR = 0x75886000; GNVS_LEN = 0x0CE1
tbl = {}
for line in open("/home/nicfio/INTEL-CAMERA/data/dsdt-analisi/gnvs-offsets.txt"):
    p = line.split()
    if len(p) == 4:
        tbl[p[0]] = (int(p[1]), int(p[3]))
fh = open("/dev/mem", "rb"); fh.seek(GNVS_ADDR); data = fh.read(GNVS_LEN); fh.close()
def v(n):
    if n not in tbl: return None
    o, w = tbl[n]; return int.from_bytes(data[o:o+w//8], "little")
names = ["SM","PL","DI","BS","DV","CV","LU","NL","EE","VC","FS","LE","DG","CK","CL","PP","VR","FD","LC","FI"]
for s in (0,1):
    print("--- L%d ---" % s)
    for n in names:
        k = "L%d%s" % (s, n); x = v(k)
        print("  %-4s = %-12s (0x%x)" % (k, x, x) if x is not None else "  %-4s = assente" % k)
    print("  indirizzi I2C:", ", ".join("0x%02x" % v("L%dA%X" % (s,i)) for i in range(6) if v("L%dA%X" % (s,i))))
    print("  L%dD*:" % s, ", ".join("D%X=0x%02x" % (i, v("L%dD%X" % (s,i))) for i in range(6) if v("L%dD%X" % (s,i)) is not None))
    print("  _HID bytes L%dH0..H8:" % s, " ".join("%02x" % (v("L%dH%d"%(s,i)) or 0) for i in range(9)))
    print("  L%dM0..MF:" % s, " ".join("%02x" % (v("L%dM%X"%(s,i)) or 0) for i in range(16)))
for c in (0,1):
    print("--- C%d ---" % c)
    for n in ["VE","TP","CV","IC","GP","IB","IA","PL","SP","CS"]:
        k = "C%d%s" % (c,n); x = v(k)
        print("  %-4s = %-12s (0x%x)" % (k, x, x) if x is not None else "  %-4s = assente" % k)
    print("  W0..W5:", " ".join(str(v("C%dW%d"%(c,i))) for i in range(6)))
    print("  I0..I5:", " ".join(str(v("C%dI%d"%(c,i))) for i in range(6)))
    print("  A0..A5:", " ".join(str(v("C%dA%d"%(c,i))) for i in range(6)))

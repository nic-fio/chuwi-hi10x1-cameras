#!/usr/bin/env python3
# verifica-posizione.py — un crop sta nel punto atteso dell'area?
#
#   verifica-posizione.py LIMITI CROP LEFT TOP [LEFT_LIMITI TOP_LIMITI]
#
# LIMITI e' una cattura dell'area intera (crop = limiti), CROP una cattura
# con crop (LEFT, TOP). Confronta tutto CROP (media dei fotogrammi, media
# mobile 2x2) con la regione di LIMITI nel punto atteso e negli spostamenti
# fino a +-4 px. Esito OK se la correlazione massima e' nel punto atteso.
import re, sys
import numpy as np

def carica(base):
    t = open(base + ".txt").read()
    m = re.search(r"formato (\d+)x(\d+) (\w+) bpl (\d+)", t)
    w, h, bpl = int(m[1]), int(m[2]), int(m[4])
    r = np.fromfile(base + ".raw", dtype=np.uint16)
    per = bpl * h // 2
    n = r.size // per
    f = r[: n * per].reshape(n, h, bpl // 2)[:, :, :w].astype(np.float64).mean(0)
    return (f[:-1, :-1] + f[1:, :-1] + f[:-1, 1:] + f[1:, 1:]) / 4

A = carica(sys.argv[1])
B = carica(sys.argv[2])
l, t = int(sys.argv[3]), int(sys.argv[4])
l0, t0 = (int(sys.argv[5]), int(sys.argv[6])) if len(sys.argv) > 6 else (0, 0)
x, y = l - l0, t - t0
bz = (B - B.mean()) / B.std()
best, tab = None, {}
for dy in range(-4, 5):
    for dx in range(-4, 5):
        yy, xx = y + dy, x + dx
        if yy < 0 or xx < 0 or yy + B.shape[0] > A.shape[0] or xx + B.shape[1] > A.shape[1]:
            continue
        s = A[yy: yy + B.shape[0], xx: xx + B.shape[1]]
        r = float(((s - s.mean()) / s.std() * bz).mean())
        tab[(dx, dy)] = r
        if best is None or r > best[0]:
            best = (r, dx, dy)
r0 = tab.get((0, 0))
seconda = max(v for k, v in tab.items() if k != (best[1], best[2]))
ok = best[1] == 0 and best[2] == 0 and best[0] > 0.9
print(f"{'OK' if ok else 'KO'} massimo a ({best[1]:+d},{best[2]:+d}) r {best[0]:.4f}; "
      f"nel punto atteso r {r0:.4f}; secondo valore {seconda:.4f}")

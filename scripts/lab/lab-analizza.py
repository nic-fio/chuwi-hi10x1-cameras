#!/usr/bin/env python3
# lab-analizza.py — analisi di una cattura di lab-cattura.sh.
#
#   lab-analizza.py USCITA [--rif ALTRA] [--frame K]
#
# Legge USCITA.txt (formato, bytesperline, timestamp) e USCITA.raw. Stampa:
#  - media e deviazione standard delle quattro fasi 2x2 (riga, colonna pari o
#    dispari): (0,0) (0,1) (1,0) (1,1);
#  - periodo medio fra i fotogrammi dai timestamp;
#  - rumore temporale: deviazione standard della differenza fra due
#    fotogrammi consecutivi, divisa per sqrt(2), nella zona centrale;
#  - con --rif: spostamento (dx, dy) di questa cattura rispetto all'altra,
#    dalla correlazione dei profili di colonna e di riga (fasi sommate 2x2).
import argparse, re, sys
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--rif")
ap.add_argument("--frame", type=int, default=-1)
a = ap.parse_args()


def carica(base, k):
    txt = open(base + ".txt").read()
    m = re.search(r"formato (\d+)x(\d+) (\w+) bpl (\d+) n (\d+)", txt)
    w, h, code, bpl, n = int(m[1]), int(m[2]), m[3], int(m[4]), int(m[5])
    raw = np.fromfile(base + ".raw", dtype=np.uint16)
    per = bpl * h // 2
    nf = raw.size // per
    fr = raw[: nf * per].reshape(nf, h, bpl // 2)[:, :, :w].astype(np.float64)
    ts = [float(x) for x in re.findall(r"^(\d+\.\d+)$", txt, re.M)]
    return fr, (w, h, code, bpl, nf), ts


fr, (w, h, code, bpl, nf), ts = carica(a.out, a.frame)
if nf == 0:
    sys.exit("nessun fotogramma")
f = fr[a.frame]
print(f"{a.out}: {w}x{h} {code}, {nf} fotogrammi, uso il {a.frame % nf}")
for dy in (0, 1):
    for dx in (0, 1):
        p = f[dy::2, dx::2]
        print(f"  fase ({dy},{dx}): media {p.mean():8.2f}  sd {p.std():7.2f}")
print(f"  media {f.mean():.2f}, max {f.max():.0f}, saturi(>=1023) {(f >= 1023).mean()*100:.3f}%")
if len(ts) >= 3:
    d = np.diff(ts[1:])
    print(f"  periodo {d.mean()*1000:.3f} ms (sd {d.std()*1000:.3f}), {1/d.mean():.3f} fps")
if nf >= 2:
    c = (slice(h // 4, 3 * h // 4), slice(w // 4, 3 * w // 4))
    dd = fr[-1][c] - fr[-2][c]
    print(f"  rumore temporale {dd.std() / np.sqrt(2):.3f} LSB (centro)")


def profili(img):
    b = img[0::2, 0::2] + img[0::2, 1::2] + img[1::2, 0::2] + img[1::2, 1::2]
    return b.mean(axis=0), b.mean(axis=1)


def sposta(p, q):
    # spostamento s tale che p[i] ~ q[i + s], in unita' 2x2, con raffinamento
    p = (p - p.mean()) / (p.std() + 1e-9)
    q = (q - q.mean()) / (q.std() + 1e-9)
    n = min(len(p), len(q))
    best = None
    for s in range(-n // 4, n // 4 + 1):
        if s >= 0:
            x, y = p[: n - s], q[s:n]
        else:
            x, y = p[-s:n], q[: n + s]
        r = float(np.mean(x * y))
        if best is None or r > best[1]:
            best = (s, r)
    return best


if a.rif:
    g, (w2, h2, *_), _ = carica(a.rif, -1)
    g = g[-1]
    cx, cy = profili(f)
    gx, gy = profili(g)
    sx, rx = sposta(cx, gx)
    sy, ry = sposta(cy, gy)
    print(f"  rispetto a {a.rif}: dx {2*sx:+d} px (r {rx:.3f}), dy {2*sy:+d} px (r {ry:.3f})")
    print("  (passo 2 px: la correlazione e' sulle celle 2x2; il pixel singolo si legge dalle fasi)")

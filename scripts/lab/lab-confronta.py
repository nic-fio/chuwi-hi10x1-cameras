#!/usr/bin/env python3
# lab-confronta.py — geometria di una cattura rispetto a un'altra, al pixel.
#
#   lab-confronta.py RIF ALTRA [ALTRA...]
#
# Ogni fotogramma (l'ultimo) passa per una media mobile 2x2: ogni finestra 2x2
# contiene R, B e due G qualunque sia la fase, quindi il risultato non dipende
# dal pattern Bayer e si puo' confrontare con spostamenti di un pixel. Per
# ognuna delle quattro trasformazioni (nessuna, mirror H, flip V, entrambe)
# cerca lo spostamento (dx, dy) che massimizza la correlazione normalizzata
# della zona centrale; stampa la migliore, riferita all'angolo in alto a
# sinistra (vale anche fra catture di dimensioni diverse). Convenzione: ALTRA[y, x] ~
# RIF[y + dy, x + dx] (dx > 0: ALTRA mostra la scena spostata verso sinistra,
# cioe' parte da una colonna piu' a destra del sensore).
import os, re, sys
import numpy as np


def carica(base):
    txt = open(base + ".txt").read()
    m = re.search(r"formato (\d+)x(\d+) (\w+) bpl (\d+) n (\d+)", txt)
    w, h, bpl = int(m[1]), int(m[2]), int(m[4])
    raw = np.fromfile(base + ".raw", dtype=np.uint16)
    per = bpl * h // 2
    nf = raw.size // per
    if nf == 0:
        return None
    f = raw[(nf - 1) * per: nf * per].reshape(h, bpl // 2)[:, :w].astype(np.float64)
    return (f[:-1, :-1] + f[1:, :-1] + f[:-1, 1:] + f[1:, 1:]) / 4


def migliore(a, b, r=int(os.environ.get("LAB_R", 64))):
    # zona centrale di b (2H x 2W) cercata in a con spostamenti fino a r,
    # correlazione normalizzata via FFT sulla zona di a allargata di r
    hy = min(a.shape[0], b.shape[0]) // 4
    hx = min(a.shape[1], b.shape[1]) // 4
    cy, cx = b.shape[0] // 2, b.shape[1] // 2
    t = b[cy - hy: cy + hy, cx - hx: cx + hx]
    t = (t - t.mean()) / (t.std() + 1e-9)
    ay, ax = a.shape[0] // 2, a.shape[1] // 2
    ry, rx = min(r, ay - hy), min(r, ax - hx)
    s = a[ay - hy - ry: ay + hy + ry, ax - hx - rx: ax + hx + rx]
    # correlazione incrociata di t su s (valida), con normalizzazione locale
    F = np.fft.rfft2
    sh = s.shape
    c = np.fft.irfft2(F(s, sh) * np.conj(F(t, sh)), sh)
    n = t.size
    ii = np.cumsum(np.cumsum(np.pad(s, ((1, 0), (1, 0))), 0), 1)
    i2 = np.cumsum(np.cumsum(np.pad(s * s, ((1, 0), (1, 0))), 0), 1)
    def box(I, y, x):
        return I[y + 2 * hy, x + 2 * hx] - I[y, x + 2 * hx] - I[y + 2 * hy, x] + I[y, x]
    ys = np.arange(2 * ry + 1)[:, None]
    xs = np.arange(2 * rx + 1)[None, :]
    m = box(ii, ys, xs) / n
    v = box(i2, ys, xs) / n - m * m
    rr = c[: 2 * ry + 1, : 2 * rx + 1] / n / np.sqrt(np.maximum(v, 1e-12))
    y, x = np.unravel_index(np.argmax(rr), rr.shape)
    best = (float(rr[y, x]), int(y) - ry, int(x) - rx)
    # da spostamento fra i centri a spostamento fra gli angoli in alto a sinistra
    return best[0], best[1] + ay - cy, best[2] + ax - cx


rif = carica(sys.argv[1])
for alt in sys.argv[2:]:
    b = carica(alt)
    nome = alt.split("/")[-1]
    if b is None:
        print(f"{nome}: nessun fotogramma")
        continue
    ris = []
    for tn, tf in (("diretta", lambda x: x), ("mirror", lambda x: x[:, ::-1]),
                   ("flip", lambda x: x[::-1, :]), ("mirror+flip", lambda x: x[::-1, ::-1])):
        c, dy, dx = migliore(rif, tf(b))
        ris.append((c, tn, dx, dy))
    ris.sort(reverse=True)
    c, tn, dx, dy = ris[0]
    print(f"{nome:16s} {tn:12s} dx {dx:+4d} dy {dy:+4d}  r {c:.3f}"
          f"  (seconda: {ris[1][1]} r {ris[1][0]:.3f})")

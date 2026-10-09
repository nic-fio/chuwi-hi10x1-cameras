#!/usr/bin/env python3
# prova-posizione.py — posizione al pixel dei crop piccoli, dove c'e' dettaglio.
#
#   sudo python3 -I scripts/v2/prova-posizione.py gc5035|gc8034
#
# Cattura l'area intera, sceglie per ogni dimensione di prova le zone con piu'
# dettaglio (gradiente medio piu' alto, offset pari), poi per ogni crop cattura
# di nuovo l'area intera subito prima (la scena puo' spostarsi di un pixel in
# un minuto) e il crop, e controlla con verifica-posizione.py che il crop stia
# esattamente nel punto atteso. Esito OK/KO per crop e riepilogo.
import os, re, subprocess, sys, time
import numpy as np

S = sys.argv[1]
QUI = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(QUI, "..", "..", "data", f"v2-posizione-{S}-" + time.strftime("%Y%m%d-%H%M%S"))
os.makedirs(D, exist_ok=True)
if S == "gc5035":
    LIM = (0, 0, 2608, 1964); SIZES = [(64, 64), (128, 96), (640, 480)]
else:
    LIM = (0, 0, 3280, 2448); SIZES = [(512, 64), (512, 256), (640, 480)]


def cattura(nome, r):
    subprocess.run(["bash", os.path.join(QUI, "cattura-crop.sh"), S, *map(str, r), "6",
                    os.path.join(D, nome)], capture_output=True)


def carica(base):
    t = open(base + ".txt").read()
    m = re.search(r"formato (\d+)x(\d+) (\w+) bpl (\d+)", t)
    w, h, bpl = int(m[1]), int(m[2]), int(m[4])
    r = np.fromfile(base + ".raw", dtype=np.uint16)
    per = bpl * h // 2
    n = r.size // per
    f = r[: n * per].reshape(n, h, bpl // 2)[:, :, :w].astype(np.float64).mean(0)
    return (f[:-1, :-1] + f[1:, :-1] + f[:-1, 1:] + f[1:, 1:]) / 4


cattura("scelta", LIM)
A = carica(os.path.join(D, "scelta"))
g = np.zeros_like(A)
g[1:, :] += np.abs(np.diff(A, axis=0))
g[:, 1:] += np.abs(np.diff(A, axis=1))
ii = np.pad(g, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
prove = []
for w, h in SIZES:
    # somma del gradiente in ogni finestra, a passo 16; le 3 migliori distinte
    best = []
    for y in range(0, A.shape[0] - h, 16):
        for x in range(0, A.shape[1] - w, 16):
            v = ii[y + h, x + w] - ii[y, x + w] - ii[y + h, x] + ii[y, x]
            best.append((v / (w * h), x, y))
    best.sort(reverse=True)
    scelti = []
    for v, x, y in best:
        if all(abs(x - a) > w or abs(y - b) > h for _, a, b in scelti):
            scelti.append((v, x, y))
        if len(scelti) == 3:
            break
    for v, x, y in scelti:
        prove.append((f"{w}x{h}-{x}-{y}", (x & ~1, y & ~1, w, h), v))

ko = 0
righe = []
for nome, r, v in prove:
    cattura(nome + "-rif", LIM)
    cattura(nome, r)
    txt = open(os.path.join(D, nome + ".txt")).read()
    got = tuple(map(int, re.search(r"crop Left (\d+), Top (\d+), Width (\d+), Height (\d+)", txt).groups()))
    out = subprocess.run(["python3", "-I", os.path.join(QUI, "verifica-posizione.py"),
                          os.path.join(D, nome + "-rif"), os.path.join(D, nome),
                          str(got[0]), str(got[1])], capture_output=True, text=True).stdout.strip()
    esito = out.split()[0] if out else "KO"
    ko += esito != "OK"
    righe.append(f"{nome:22s} crop {got} dettaglio {v:5.1f}: {out}")
    print(righe[-1], flush=True)
open(os.path.join(D, "esito.txt"), "w").write("\n".join(righe) + f"\nKO: {ko}\n")
print(f"KO: {ko}   ({D})")

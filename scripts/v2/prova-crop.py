#!/usr/bin/env python3
# prova-crop.py — prove del crop dei driver v2, con esito automatico.
#
#   sudo python3 -I scripts/v2/prova-crop.py gc5035|gc8034 [CARTELLA]
#
# Per ogni richiesta: cattura con cattura-crop.sh, poi controlla
#  - che il rettangolo applicato sia quello previsto dalle regole di
#    arrotondamento del driver;
#  - che il periodo (mediana) sia quello del modello dei tempi misurato;
#  - che i fotogrammi siano tutti arrivati e completi;
#  - che la posizione al pixel rispetto al crop di default sia
#    (left - left_def, top - top_def) (solo dove la correlazione e' > 0,9).
# Stampa OK/KO per ogni controllo e un riepilogo finale.
import os, re, subprocess, sys, time

S = sys.argv[1]
QUI = os.path.dirname(os.path.abspath(__file__))
D = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    QUI, "..", "..", "data", f"v2-crop-{S}-" + time.strftime("%Y%m%d-%H%M%S"))
os.makedirs(D, exist_ok=True)
os.environ["LAB_R"] = "3300"   # spostamenti fino a tutta l'area

if S == "gc5035":
    AREA = (2608, 1964); DEF = (8, 8, 2592, 1944)
    MIN = (64, 64); AL = (2, 2, 4, 4)
    VBMIN = 64; RIGA = 2920 / 168960000          # s per riga
    PROVE = [("default", DEF), ("limiti", (0, 0, 2608, 1964)),
             ("centro", (1000, 700, 640, 480)), ("angolo", (2480, 1868, 128, 96)),
             ("minimo", (0, 0, 64, 64)), ("arrotonda", (7, 9, 2593, 1945)),
             ("fuori", (3000, 3000, 5000, 5000))]
else:
    AREA = (3282, 2500); DEF = (8, 52, 3264, 2448)
    MIN = (512, 64); AL = (2, 2, 4, 4)
    VBMIN = 48; RIGA = 4272 / 256000000
    PROVE = [("default", DEF), ("limiti", (0, 0, 3280, 2448)), ("cima", (8, 0, 3264, 2448)),
             ("striscia", (0, 2436, 3280, 64)), ("centro", (1200, 900, 640, 480)),
             ("fondo", (1200, 2404, 640, 96)), ("minimo", (0, 0, 512, 64)),
             ("arrotonda", (9, 53, 3265, 2449)), ("fuori", (5000, 5000, 6000, 6000))]


def atteso(r):
    """Regole di arrotondamento dei driver v2 (stesse del codice C)."""
    l, t, w, h = r
    maxw = AREA[0] if S == "gc5035" else 3280
    maxh = AREA[1] if S == "gc5035" else 2448
    l = max(0, min(l, AREA[0] - MIN[0])) // AL[0] * AL[0]
    t = max(0, min(t, AREA[1] - MIN[1])) // AL[1] * AL[1]
    w = max(MIN[0], min(w, maxw, AREA[0] - l)) // AL[2] * AL[2]
    h = max(MIN[1], min(h, maxh, AREA[1] - t)) // AL[3] * AL[3]
    return (l, t, w, h)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


ko = 0
righe = []
for nome, req in PROVE:
    out = os.path.join(D, nome)
    run(["bash", os.path.join(QUI, "cattura-crop.sh"), S, *map(str, req), "6", out])
    txt = open(out + ".txt").read()
    m = re.search(r"crop Left (\d+), Top (\d+), Width (\d+), Height (\d+)", txt)
    got = tuple(map(int, m.groups()))
    exp = atteso(req)
    # periodo: intervalli che valgono un solo fotogramma (entro il 2% del
    # piu' corto plausibile); i multipli sono fotogrammi persi in cattura.
    # Timestamp non crescenti o nulli (IPU6 oltre ~500 fps): non misurabile.
    ts = [float(x) for x in re.findall(r"^(\d+\.\d+)$", txt.split("timestamp:")[-1], re.M)]
    d = [b - a for a, b in zip(ts[1:], ts[2:])]
    per, persi = None, None
    if d and min(d) > 0:
        p0 = min(d)
        uno = sorted(x for x in d if x < p0 * 1.02)
        per = round(uno[len(uno) // 2] * 1000, 3)
        persi = sum(round(x / p0) - 1 for x in d)
    model = (got[3] + VBMIN) * RIGA * 1000
    size = os.path.getsize(out + ".raw")
    bpl = int(re.search(r"bpl (\d+)", txt)[1])
    c1 = got == exp
    c2 = per is not None and abs(per - model) < 0.01
    c3 = size == bpl * got[3] * 6
    esito = [("crop", c1, f"{got} atteso {exp}"),
             ("periodo", c2 if per is not None else None,
              f"{per} ms modello {model:.3f}" if per is not None else "timestamp non crescenti: non misurabile"),
             ("fotogrammi", c3, f"{size} byte, persi in cattura {persi}")]
    if nome != "default":
        # riferimento catturato subito dopo: la scena o il supporto possono
        # spostarsi di un pixel in un minuto
        rif = out + "-rif"
        run(["bash", os.path.join(QUI, "cattura-crop.sh"), S, *map(str, DEF), "6", rif])
        cf = run(["python3", "-I", os.path.join(QUI, "..", "lab", "lab-confronta.py"),
                  rif, out])
        q = re.search(r"diretta\s+dx\s+([+-]\d+) dy\s+([+-]\d+)\s+r ([0-9.]+)", cf)
        if q:
            dx, dy, r = int(q[1]), int(q[2]), float(q[3])
            ex = (got[0] - DEF[0], got[1] - DEF[1])
            if r > 0.9:
                esito.append(("posizione", (dx, dy) == ex, f"({dx},{dy}) attesa {ex} r {r}"))
            else:
                esito.append(("posizione", None, f"non misurabile (r {r}), ({dx},{dy}) attesa {ex}"))
    for k, ok, msg in esito:
        tag = "OK" if ok else ("--" if ok is None else "KO")
        ko += ok is False
        righe.append(f"{nome:10s} {k:10s} {tag}  {msg}")
        print(righe[-1], flush=True)

open(os.path.join(D, "esito.txt"), "w").write("\n".join(righe) + f"\nKO: {ko}\n")
print(f"KO: {ko}   ({D})")

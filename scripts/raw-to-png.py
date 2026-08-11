#!/usr/bin/env python3
"""raw-to-png.py — da RAW Bayer 10 bit (in parole da 16 bit) a PNG guardabile.

Progetto INTEL-CAMERA. Serve a rispondere alla domanda "il fotogramma e'
riconoscibile?", che e' il criterio di completamento delle Fasi 2 e 3, senza
tirare dentro un ISP: demosaicing 2x2 (ogni quadrupla Bayer -> un pixel RGB),
white balance grigio-mondo e gamma. Il risultato e' meta' risoluzione ed e'
volutamente grezzo: e' una verifica, non una pipeline immagine.

Uso:
  raw-to-png.py FILE.raw LARGHEZZA ALTEZZA PATTERN [uscita.png] [--frame N]

PATTERN e' l'ordine Bayer del sensore: grbg (GC5035), rggb (GC8034).
"""
import sys

import numpy as np
from PIL import Image

BLACK_LEVEL = 64          # pedestal a 10 bit, comune ai due GalaxyCore
MAX_LEVEL = 1023


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    frame = 0
    if "--frame" in sys.argv:
        frame = int(sys.argv[sys.argv.index("--frame") + 1])
        args = [a for a in args if a != str(frame)]

    if len(args) < 4:
        sys.exit(__doc__)

    path, width, height, pattern = args[0], int(args[1]), int(args[2]), args[3].lower()
    out = args[4] if len(args) > 4 else path.rsplit(".", 1)[0] + ".png"

    count = width * height
    raw = np.fromfile(path, dtype="<u2", count=count, offset=frame * count * 2)
    if raw.size != count:
        sys.exit(f"{path}: frame {frame} incompleto ({raw.size} di {count} pixel)")
    bayer = raw.reshape(height, width).astype(np.float32)

    # Sottrazione del nero e normalizzazione, prima del demosaicing: farlo dopo
    # falserebbe il bilanciamento, perche' il pedestal non e' segnale.
    bayer = np.clip(bayer - BLACK_LEVEL, 0, None) / (MAX_LEVEL - BLACK_LEVEL)

    # I quattro fotositi di ogni quadrupla, nell'ordine in cui stanno sul
    # sensore. Le chiavi seguono la convenzione V4L2: il pattern nomina la
    # prima riga e poi la seconda.
    q = {
        "tl": bayer[0::2, 0::2], "tr": bayer[0::2, 1::2],
        "bl": bayer[1::2, 0::2], "br": bayer[1::2, 1::2],
    }
    layout = {
        "grbg": ("tr", ("tl", "br"), "bl"),
        "rggb": ("tl", ("tr", "bl"), "br"),
        "bggr": ("br", ("tr", "bl"), "tl"),
        "gbrg": ("bl", ("tl", "br"), "tr"),
    }
    if pattern not in layout:
        sys.exit(f"pattern sconosciuto: {pattern} (attesi: {', '.join(layout)})")
    r_key, g_keys, b_key = layout[pattern]
    r, b = q[r_key], q[b_key]
    g = (q[g_keys[0]] + q[g_keys[1]]) / 2

    # White balance grigio-mondo: senza di questo il raw esce verdissimo,
    # perche' i fotositi verdi sono il doppio e piu' sensibili.
    rgb = np.dstack([r, g, b])
    means = rgb.reshape(-1, 3).mean(axis=0)
    if means.min() > 0:
        rgb *= means.mean() / means

    # Autoscala sul 99,5° percentile invece che sul massimo: un solo pixel
    # caldo altrimenti schiaccia tutta l'immagine.
    top = np.percentile(rgb, 99.5)
    if top > 0:
        rgb = np.clip(rgb / top, 0, 1)

    rgb = rgb ** (1 / 2.2)                      # gamma sRGB approssimata
    Image.fromarray((rgb * 255).astype(np.uint8)).save(out)

    print(f"{out}  {rgb.shape[1]}x{rgb.shape[0]}  "
          f"(da {path}, frame {frame}, {pattern.upper()})")


if __name__ == "__main__":
    main()

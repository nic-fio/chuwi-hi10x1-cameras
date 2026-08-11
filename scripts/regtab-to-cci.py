#!/usr/bin/env python3
"""
regtab-to-cci.py — converte una tabella registri vendor in cci_reg_sequence.

Progetto INTEL-CAMERA.

I driver BSP (Rockchip) e la patch Intel dichiarano le sequenze come

    static const struct regval gc8034_global_regs_4lane[] = {
        /*SYS*/
        {0xf2, 0x00},
        ...
    };

mentre mainline vuole, per un sensore a registri di un byte:

    static const struct cci_reg_sequence gc8034_init_regs[] = {
        /* SYS */
        { CCI_REG8(0xf2), 0x00 },
        ...
    };

Lo script fa questa traduzione **senza toccare i valori**: e' una riscrittura
sintattica, verificabile confrontando le due liste byte per byte (opzione
--check). I commenti di sezione vengono conservati perche' in review servono a
spiegare cosa fa ogni blocco.

USO
    regtab-to-cci.py <file.c> <nome_tabella_sorgente> <nome_tabella_uscita>
    regtab-to-cci.py --check <file.c> <tabella> <file_generato.c> <tabella>
"""

import re
import sys


def extract(path, name):
    """Ritorna [(reg, val)] piu' i commenti, nell'ordine originale."""
    src = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r'\w+\s+%s\[\]\s*=\s*\{(.*?)\n\};' % re.escape(name), src, re.S)
    if not m:
        sys.exit("tabella %s non trovata in %s" % (name, path))

    items = []
    for line in m.group(1).splitlines():
        s = line.strip()
        if not s:
            continue
        # le direttive del preprocessore non hanno senso in mainline:
        # i modi si scelgono a runtime, non a compile-time
        if s.startswith("#"):
            items.append(("skip", s))
            continue
        c = re.match(r'/\*\s*(.*?)\s*\*/$', s)
        if c:
            items.append(("comment", c.group(1)))
            continue
        # forma vendor:   {0xfe, 0x00},
        # forma mainline: { CCI_REG8(0xfe), 0x00 },
        # riconosciamo entrambe, cosi' --check confronta sorgente e generato
        r = re.match(r'\{\s*(?:CCI_REG8\(\s*)?0x([0-9a-fA-F]{2})\s*\)?\s*,'
                     r'\s*0x([0-9a-fA-F]{2})\s*\}\s*,?', s)
        if r:
            items.append(("reg", (r.group(1).lower(), r.group(2).lower())))
    return items


def regs_only(items):
    return [v for k, v in items if k == "reg"]


def emit(items, out_name):
    lines = ["static const struct cci_reg_sequence %s[] = {" % out_name]
    for kind, v in items:
        if kind == "comment":
            lines.append("\t/* %s */" % v)
        elif kind == "reg":
            lines.append("\t{ CCI_REG8(0x%s), 0x%s }," % v)
    lines.append("};")
    return "\n".join(lines)


def main():
    if sys.argv[1:2] == ["--check"]:
        _, _, f1, t1, f2, t2 = sys.argv
        a = regs_only(extract(f1, t1))
        b = regs_only(extract(f2, t2))
        if a == b:
            print("OK  %s (%d reg) == %s (%d reg)" % (t1, len(a), t2, len(b)))
            return 0
        print("DIVERSE: %d vs %d registri" % (len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y:
                print("  primo scostamento a indice %d: %s vs %s" % (i, x, y))
                break
        return 1

    path, src_name, out_name = sys.argv[1], sys.argv[2], sys.argv[3]
    items = extract(path, src_name)
    skipped = [v for k, v in items if k == "skip"]
    if skipped:
        sys.stderr.write("attenzione: %d direttive del preprocessore ignorate; "
                         "verificare a mano quale ramo e' quello giusto:\n" % len(skipped))
        for s in skipped[:10]:
            sys.stderr.write("    %s\n" % s)
    print(emit(items, out_name))
    sys.stderr.write("%d registri convertiti\n" % len(regs_only(items)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

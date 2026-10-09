#!/usr/bin/env python3
# stato-tabelle.py — stato finale dei registri (pagina, reg) dopo una o piu'
# tabelle vendor scritte in ordine, e differenza fra due sequenze.
#   stato-tabelle.py FILE.c "tabA1,tabA2" "tabB1,tabB2"
# Pagina = bit [2:0] di 0xfe (0x10 ecc. non sono pagine). I registri 0xf0-0xff
# sono comuni a tutte le pagine.
import re, sys

src = open(sys.argv[1]).read()

def tabella(nome):
    m = re.search(r"\b%s\[\]\s*=\s*\{(.*?)\n\};" % re.escape(nome), src, re.S)
    if not m:
        sys.exit("tabella %s non trovata" % nome)
    corpo = re.sub(r"//[^\n]*|/\*.*?\*/", "", m[1], flags=re.S)
    defs = dict(re.findall(r"#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)", src))
    out = []
    for r, v in re.findall(r"\{\s*(0x[0-9a-fA-F]+)\s*,\s*(\w+)\s*\}", corpo):
        v = defs.get(v, v)
        out.append((int(r, 16), int(v, 0)))
    return out

def stato(nomi):
    st, page = {}, 0
    for n in nomi.split(","):
        for r, v in tabella(n):
            if r == 0xfe:
                page = v & 7
                continue
            st[(None if r >= 0xf0 else page, r)] = v
    return st

a, b = stato(sys.argv[2]), stato(sys.argv[3])
for k in sorted(set(a) | set(b), key=lambda k: (-1 if k[0] is None else k[0], k[1])):
    if a.get(k) != b.get(k):
        p = "S" if k[0] is None else k[0]
        fa = "--" if a.get(k) is None else "%02x" % a[k]
        fb = "--" if b.get(k) is None else "%02x" % b[k]
        print("P%s 0x%02x: %s -> %s" % (p, k[1], fa, fb))

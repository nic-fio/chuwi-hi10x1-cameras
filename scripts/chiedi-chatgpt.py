#!/usr/bin/env python3
# chiedi-chatgpt.py — secondo parere tramite l'API OpenAI (Responses).
#
#   chiedi-chatgpt.py FILO DOMANDA.md [--nuovo] [--modello gpt-5.5]
#
# FILO e' un nome breve (es. crop-binning): domande e risposte vanno in
# data/chatgpt/FILO/NN-domanda.md e NN-risposta.md, e l'id dell'ultima
# risposta in data/chatgpt/FILO/ultimo-id, cosi' la domanda successiva
# continua la stessa conversazione (--nuovo la ricomincia).
# La chiave si legge da ~/openai.key a ogni chiamata e non viene mai
# scritta altrove. ChatGPT e' un revisore di ipotesi: i fatti restano le
# misure (docs/14, regola sulle fonti).
import argparse, json, os, sys, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("filo")
ap.add_argument("domanda")
ap.add_argument("--nuovo", action="store_true")
ap.add_argument("--modello", default="gpt-5.5")
ap.add_argument("--sforzo", default="high")
a = ap.parse_args()

qui = os.path.dirname(os.path.abspath(__file__))
dir_ = os.path.join(qui, "..", "data", "chatgpt", a.filo)
os.makedirs(dir_, exist_ok=True)
fid = os.path.join(dir_, "ultimo-id")
prec = None if a.nuovo or not os.path.exists(fid) else open(fid).read().strip()
n = len([f for f in os.listdir(dir_) if f.endswith("-domanda.md")]) + 1

testo = open(a.domanda, encoding="utf-8").read()
corpo = {"model": a.modello, "input": testo, "reasoning": {"effort": a.sforzo}}
if prec:
    corpo["previous_response_id"] = prec

chiave = open(os.path.expanduser("~/openai.key")).read().strip()
req = urllib.request.Request(
    "https://api.openai.com/v1/responses", data=json.dumps(corpo).encode(),
    headers={"Authorization": "Bearer " + chiave, "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.load(r)
except urllib.error.HTTPError as e:
    sys.exit(f"errore HTTP {e.code}: {e.read().decode()[:2000]}")

risposta = "".join(c.get("text", "") for o in d.get("output", []) if o.get("type") == "message"
                   for c in o.get("content", []))
open(os.path.join(dir_, f"{n:02d}-domanda.md"), "w", encoding="utf-8").write(testo)
open(os.path.join(dir_, f"{n:02d}-risposta.md"), "w", encoding="utf-8").write(
    f"<!-- {d.get('model')} {d.get('id')} uso {json.dumps(d.get('usage', {}).get('total_tokens'))} token -->\n"
    + risposta + "\n")
open(fid, "w").write(d["id"])
print(risposta)
print(f"\n[{d.get('model')}, {d.get('usage', {}).get('total_tokens')} token; "
      f"salvata in data/chatgpt/{a.filo}/{n:02d}-risposta.md]", file=sys.stderr)

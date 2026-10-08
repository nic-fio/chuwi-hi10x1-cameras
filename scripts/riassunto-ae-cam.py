# riassunto-ae-cam.py — da un log di `cam --metadata` stampa guadagno ed
# esposizione solo quando cambiano, piu' il black level dell'ultimo fotogramma.
# Uso: python3 scripts/riassunto-ae-cam.py data/ae-libcamera-*/cam-*.log
import sys,re
for f in sys.argv[1:]:
    rows=[];cur=None
    for l in open(f):
        m=re.search(r'seq: (\d+)',l)
        if m:
            cur={'seq':int(m.group(1))};rows.append(cur)
        m=re.match(r'\s+(AnalogueGain|ExposureTime|SensorBlackLevels) = (.*)',l)
        if m and cur is not None: cur[m.group(1)]=m.group(2).strip()
    out=[]; prev=None
    for r in rows:
        k=(r.get('AnalogueGain'),r.get('ExposureTime'))
        if k!=prev: out.append('%d:g%.3f/e%s'%(r['seq'],float(k[0] or 0),k[1])); prev=k
    print(f.split('/')[-1],len(rows),'bl',rows[-1].get('SensorBlackLevels'),'\n   ',' '.join(out[:25]))

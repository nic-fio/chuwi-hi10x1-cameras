import array, subprocess, sys, statistics as st, time
SD, NODE, RAW = "/dev/v4l-subdev4", "/dev/video16", sys.argv[1]
CYC = int(sys.argv[2])
def ctl(*a): subprocess.run(["v4l2-ctl", "-d", SD] + [f"--set-ctrl={x}" for x in a], check=True)
def frames(e, n=4):
    ctl(f"exposure={e}")
    subprocess.run(["timeout", "60", "v4l2-ctl", "-d", NODE, "--stream-mmap", f"--stream-count={n}",
                    f"--stream-to={RAW}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    d = open(RAW, "rb").read(); L = len(d)//n//2*2; out = []
    for k in range(1, n):
        a = array.array("H"); a.frombytes(d[k*L:(k+1)*L]); out.append(a[::11])
    return out
ctl("analogue_gain=16")
ref = frames(250, 2)[0]
mask = [i for i, v in enumerate(ref) if v < 900]
print(f"maschera: {100*len(mask)/len(ref):.1f}% dei pixel", flush=True)
def mean(e): return st.mean(sum(f[i] for i in mask)/len(mask) for f in frames(e))
E = [150] + list(range(200, 209)) + [250]
r = []; t0 = time.time()
for c in range(CYC):
    order = E if c % 2 == 0 else E[::-1]          # avanti e indietro: la deriva lineare si annulla
    m = {e: mean(e) for e in order}; r.append(m)
    print(f"ciclo {c+1:2} ({time.time()-t0:4.0f} s): " + " ".join(f"{m[e]:.3f}" for e in E), flush=True)
def se(v): return st.stdev(v)/len(v)**.5
lunga = [(m[250]-m[150])/100 for m in r]
locale = [(m[208]-m[200])/8 for m in r]
dentro = [st.mean(m[e+1]-m[e] for e in (200, 202, 204, 206)) for m in r]
fra = [st.mean(m[e+1]-m[e] for e in (201, 203, 205, 207)) for m in r]
diff = [b-a for a, b in zip(dentro, fra)]
print(f"pendenza 150->250: {st.mean(lunga):.4f} ± {se(lunga):.4f} LSB/riga")
print(f"pendenza 200->208: {st.mean(locale):.4f} ± {se(locale):.4f} LSB/riga")
print(f"passo dentro coppia (2k->2k+1): {st.mean(dentro):+.4f} ± {se(dentro):.4f}")
print(f"passo fra coppie  (2k+1->2k+2): {st.mean(fra):+.4f} ± {se(fra):.4f}")
print(f"fra - dentro: {st.mean(diff):+.4f} ± {se(diff):.4f}")
p = st.mean(lunga)
print(f"attesi con p={p:.4f}: arrotonda -> dentro 0, fra {2*p:.4f}, differenza {2*p:+.4f}; accetta -> dentro {p:.4f}, fra {p:.4f}, differenza 0")
ctl("analogue_gain=0", "exposure=984")

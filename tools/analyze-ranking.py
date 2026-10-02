import json, statistics as st
d = json.load(open(__import__("sys").argv[1] if len(__import__("sys").argv) > 1 else "simdata.json"))["verified"]
SIZES = [30, 60, 90, 120]

def band(vs, t, tol):
    return [v for v in vs if v["hw"] <= .15 and t*(1-tol) <= v["min"] <= t*(1+tol)]

def rank(vs, t, thr):
    key = lambda v: ((thr is not None and v["rt"] > thr), (v["rt"] if thr is not None and v["rt"] > thr else 0), v["hw"], abs(v["min"] - t))
    return sorted(vs, key=key)[:3]

def generate(vs, t, thr, retry_on_dirty):
    r1 = [v for v in vs if v["seed"] <= 12]
    top = rank(band(r1, t, .25), t, thr)
    dirty = thr is not None and sum(v["rt"] > thr for v in top) > 0
    retried = len(top) < 3 or (retry_on_dirty and dirty)
    if retried:
        top = rank(band(vs, t, .40), t, thr)
    return top, retried

for thr_by_size, label in [({}, "TODAY"),
        ({30:.20,60:.10,90:.10,120:.10}, "rerank 20/10"),
        ({30:.15,60:.10,90:.10,120:.10}, "rerank 15/10"),
        ({30:.10,60:.10,90:.10,120:.10}, "rerank 10 all")]:
    for retry in ([False] if not thr_by_size else [False, True]):
        print(f"\n== {label}{' +retry-if-dirty' if retry else ''}")
        print(f"{'size':>5} {'empty':>6} {'retry%':>7} {'mean top3':>10} {'worst':>7} {'slots>10%':>10} {'slots>20%':>10}")
        for m in SIZES:
            keys = [k for k in d if k.endswith(f"|{m}")]
            tops, retries, empties = [], 0, 0
            for k in keys:
                top, r = generate(d[k], m, thr_by_size.get(m), retry)
                retries += r; empties += not top; tops += [v["rt"] for v in top]
            n = len(keys)
            print(f"{m:>4}m {empties:>4}/{n} {retries/n*100:>6.0f}% {st.mean(tops)*100:>9.1f}% {max(tops)*100:>6.1f}% "
                  f"{sum(x>.10 for x in tops)/len(tops)*100:>9.0f}% {sum(x>.20 for x in tops)/len(tops)*100:>9.0f}%")

print("\n30m by origin, TODAY vs rerank 15 +retry (mean / worst top-3 retrace)")
for k in sorted(k for k in d if k.endswith("|30")):
    a,_ = generate(d[k], 30, None, False); b,_ = generate(d[k], 30, .15, True)
    f = lambda t: f"{st.mean(x['rt'] for x in t)*100:5.1f}/{max(x['rt'] for x in t)*100:5.1f}" if t else "  empty  "
    print(f"  {k.split('|')[0]:<15} {f(a)}  ->  {f(b)}")

print("\nDuration drift of shown loops, |minutes - target| / target")
for m in SIZES:
    keys = [k for k in d if k.endswith(f"|{m}")]
    a = [abs(v["min"]-m)/m for k in keys for v in generate(d[k], m, None, False)[0]]
    b = [abs(v["min"]-m)/m for k in keys for v in generate(d[k], m, .10, True)[0]]
    print(f"  {m:>3}m  today median {st.median(a)*100:4.1f}% max {max(a)*100:4.1f}%   new median {st.median(b)*100:4.1f}% max {max(b)*100:4.1f}%")

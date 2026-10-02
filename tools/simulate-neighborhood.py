#!/usr/bin/env python3
"""Simulate Neighborhood mode end to end, used to tune it on 2026-10-01.

Per origin and request size: 24 round-trip seeds, the 6 most residential of each
12 verified with handoff stops placed on residential street (res_stops mirrors
Handoff.residentialWaypoints), then the app's ranking. Prints empties, retries,
residential share, duration and retrace per request size.
Run through a tunnel:
  ssh -i ~/.ssh/aimless_oracle -f -N -L 18080:127.0.0.1:8080 ubuntu@129.213.20.151
  python3 tools/simulate-neighborhood.py
"""
import json, math, urllib.request, statistics
from concurrent.futures import ThreadPoolExecutor

ORS = "http://127.0.0.1:18080/ors/v2/directions/driving-car/geojson"
WAYPOINTS = 8          # Handoff.waypointCount
GRID_M = 25            # retrace grid cell size
HIGHWAY_BIT = 1

ORIGINS = [
    ("Marlboro NJ", 40.4001, -74.3457),
    ("Denver CO",   39.7392, -104.9903),
    ("Austin TX",   30.2672, -97.7431),
]
SIZES = [(30, 6500), (60, 33000), (90, 70000), (120, 85000)]
SEEDS = list(range(1, 11))


def post(body):
    req = urllib.request.Request(
        ORS, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return json.load(r)
    except Exception:
        return None


def haversine(a, b):
    lat1, lon1 = a[1], a[0]
    lat2, lon2 = b[1], b[0]
    p = math.pi / 180
    x = (0.5 - math.cos((lat2 - lat1) * p) / 2
         + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2)
    return 12742000 * math.asin(math.sqrt(max(0.0, x)))


def round_trip(lat, lon, meters, seed):
    return post({
        "coordinates": [[lon, lat]],
        "options": {"round_trip": {"length": meters, "points": 8, "seed": seed}},
        "extra_info": ["waytype", "waycategory"],
        "instructions": False,
    })


def reroute(coords):
    return post({
        "coordinates": coords,
        "extra_info": ["waytype", "waycategory"],
        "instructions": False,
    })


def downsample(coords, count=WAYPOINTS):
    """Exactly Handoff.waypoints: every total/(count+1) m, interpolated."""
    if len(coords) < 3:
        return []
    cum = [0.0]
    for i in range(1, len(coords)):
        cum.append(cum[-1] + haversine(coords[i - 1], coords[i]))
    total = cum[-1]
    if total <= 0:
        return []
    step = total / (count + 1)
    out, cursor = [], 1
    for k in range(1, count + 1):
        target = step * k
        while cursor < len(cum) - 1 and cum[cursor] < target:
            cursor += 1
        prev = cursor - 1
        span = cum[cursor] - cum[prev]
        t = (target - cum[prev]) / span if span > 0 else 0.0
        a, b = coords[prev], coords[cursor]
        out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
    return out


def stats(feat):
    """Replicates RouteService.roadStats: highway = waycategory bit0 / waytype total."""
    props = feat["properties"]
    extras = props.get("extras", {})

    def by_value(block):
        d = {}
        for row in (extras.get(block, {}) or {}).get("summary", []):
            d[int(row["value"])] = d.get(int(row["value"]), 0) + row["distance"]
        return d

    wt, wc = by_value("waytype"), by_value("waycategory")
    total = sum(wt.values())
    hw = sum(v for k, v in wc.items() if k & HIGHWAY_BIT)
    return {
        "distance": props["summary"]["distance"],
        "duration": props["summary"]["duration"],
        "highway": (hw / total) if total else 0.0,
    }


def retrace_pct(coords):
    """% of driven length spent on road covered on a separate pass.

    Snap points to a ~25 m grid; a cell entered in two non-contiguous runs is
    retraced. Counts both passes, matching "11% of the drive retracing road".
    """
    if len(coords) < 3:
        return 0.0
    lat0 = coords[0][1]
    dlat = GRID_M / 111320.0
    dlon = GRID_M / (111320.0 * max(0.2, math.cos(lat0 * math.pi / 180)))
    cells = {}
    for i, c in enumerate(coords):
        key = (int(round(c[1] / dlat)), int(round(c[0] / dlon)))
        cells.setdefault(key, []).append(i)

    retraced = set()
    for key, idxs in cells.items():
        runs = 1
        for j in range(1, len(idxs)):
            if idxs[j] - idxs[j - 1] > 3:   # gap = a separate pass
                runs += 1
        if runs >= 2:
            retraced.add(key)

    total = repeat = 0.0
    for i in range(len(coords) - 1):
        d = haversine(coords[i], coords[i + 1])
        total += d
        key = (int(round(coords[i][1] / dlat)), int(round(coords[i][0] / dlon)))
        if key in retraced:
            repeat += d
    return (repeat / total * 100.0) if total else 0.0


def one(origin, minutes, meters, seed):
    name, lat, lon = origin
    rt = round_trip(lat, lon, meters, seed)
    if not rt or not rt.get("features"):
        return None
    coords = rt["features"][0]["geometry"]["coordinates"]
    wps = downsample(coords)
    if len(wps) != WAYPOINTS:
        return None
    start = [lon, lat]

    fwd = reroute([start] + wps + [start])
    rev = reroute([start] + list(reversed(wps)) + [start])
    if not fwd or not fwd.get("features"):
        return None
    f = stats(fwd["features"][0])
    f["retrace"] = retrace_pct(fwd["features"][0]["geometry"]["coordinates"])

    r = None
    if rev and rev.get("features"):
        r = stats(rev["features"][0])
        r["retrace"] = retrace_pct(rev["features"][0]["geometry"]["coordinates"])

    return {"origin": name, "minutes": minutes, "seed": seed, "fwd": f, "rev": r}


import sys, statistics as st
ORIGINS = [("Marlboro NJ",40.4001,-74.3457),("Naperville IL",41.7508,-88.1535),("Plano TX",33.0198,-96.6989),
 ("Cary NC",35.7915,-78.7811),("Levittown NY",40.7259,-73.5143),("Overland Pk KS",38.9822,-94.6708),
 ("Roseville CA",38.7521,-121.2880),("Marietta GA",33.9526,-84.5499),("Scottsdale AZ",33.4942,-111.9261),("Denver CO",39.7392,-104.9903)]
SIZES=[(30,6500),(45,15000),(60,33000)]
def wt_mask(f):
    n=len(f["geometry"]["coordinates"]); m=[0]*n
    for a,b,v in (f["properties"]["extras"]["waytype"]["values"]):
        for i in range(a,min(b,n-1)+1): m[i]=v
    return m
def share(f):
    rows=f["properties"]["extras"]["waytype"]["summary"]; t=sum(r["distance"] for r in rows) or 1
    return sum(r["distance"] for r in rows if r["value"]==3)/t
def res_stops(coords, mask, count=8):
    cum=[0.0]
    for i in range(1,len(coords)): cum.append(cum[-1]+haversine(coords[i-1],coords[i]))
    total=cum[-1]; step=total/(count+1); out=[]
    # residential run depth: distance to nearest non-residential point
    depth=[0.0]*len(coords); last=-1e18
    for i in range(len(coords)):
        if mask[i]!=3: last=cum[i]
        depth[i]=cum[i]-last
    last=1e18
    for i in range(len(coords)-1,-1,-1):
        if mask[i]!=3: last=cum[i]
        depth[i]=min(depth[i], last-cum[i]) if mask[i]==3 else 0
    for k in range(1,count+1):
        lo,hi=step*(k-0.5),step*(k+0.5)
        idx=[i for i in range(len(coords)) if lo<=cum[i]<=hi and mask[i]==3]
        if idx:
            i=max(idx,key=lambda i:depth[i]); out.append(coords[i])
        else:
            t=step*k; i=min(range(len(cum)),key=lambda i:abs(cum[i]-t)); out.append(coords[i])
    return out
def one(o,m,meters,seed):
    n,lat,lon=o; rt=round_trip(lat,lon,meters,seed)
    if not rt or not rt.get("features"): return None
    f=rt["features"][0]; c=f["geometry"]["coordinates"]; s0=c[0]; res={}
    for name,w in (("uniform",downsample(c)),("residential",res_stops(c,wt_mask(f)))):
        if len(w)!=8: return None
        r=reroute([s0]+w+[s0])
        if not r or not r.get("features"): return None
        g=r["features"][0]; s=stats(g)
        res[name]={"min":s["duration"]/60,"hw":s["highway"],"street":share(g),"rt":retrace_pct(g["geometry"]["coordinates"])}
    return {"o":n,"m":m,"seed":seed,"rt_street":share(f),**res}
ORIGINS += [("Austin TX",30.2672,-97.7431),("Dyker Hts NY",40.6215,-74.0151)]
T=45
def cand(o,meters,seed):
    n,lat,lon=o; rt=round_trip(lat,lon,meters,seed)
    if not rt or not rt.get("features"): return None
    f=rt["features"][0]; s=stats(f)
    return {"o":n,"req":meters,"seed":seed,"f":f,"est":s["duration"]/60*0.75,"hw":s["highway"],"cstreet":share(f)}
def verify(c):
    co=c["f"]["geometry"]["coordinates"]; w=res_stops(co,wt_mask(c["f"]))
    r=reroute([co[0]]+w+[co[0]])
    if not r or not r.get("features"): return None
    g=r["features"][0]; s=stats(g)
    return {"seed":c["seed"],"min":s["duration"]/60,"hw":s["highway"],"street":share(g),"rt":retrace_pct(g["geometry"]["coordinates"])/100}
REQS=[13000,15000,17000]
jobs=[(o,m,s) for o in ORIGINS for m in REQS for s in range(1,25)]
with ThreadPoolExecutor(max_workers=6) as ex: C=[c for c in ex.map(lambda a:cand(*a),jobs) if c]
def worth(cs):
    ok=[c for c in cs if c["hw"]<=.20 and T*.55<=c["est"]<=T*1.45]
    return sorted(ok,key=lambda c:-c["cstreet"])[:6]
todo=[]
for o in ORIGINS:
    for m in REQS:
        cs=[c for c in C if c["o"]==o[0] and c["req"]==m]
        todo+=worth([c for c in cs if c["seed"]<=12])+worth([c for c in cs if c["seed"]>12])
with ThreadPoolExecutor(max_workers=6) as ex: V=list(ex.map(verify,todo))
band=lambda L,tol:[v for v in L if v["hw"]<=.15 and T*(1-tol)<=v["min"]<=T*(1+tol)]
rank=lambda L:sorted(L,key=lambda v:(v["rt"]>.10, v["rt"] if v["rt"]>.10 else 0, -v["street"], abs(v["min"]-T)))[:3]
for m in REQS:
    tops=[];E=0;retry=0
    for o in ORIGINS:
        vs=[v for c,v in zip(todo,V) if v and c["o"]==o[0] and c["req"]==m]
        top=rank(band([v for v in vs if v["seed"]<=12],.25))
        if len(top)<3 or any(v["rt"]>.10 for v in top):
            retry+=1; top=rank(band(vs,.40))
        E+=not top; tops+=top
    print(f"{m} m: empty {E}/{len(ORIGINS)}  retry {retry}/{len(ORIGINS)}  residential {st.mean(v['street'] for v in tops)*100:.0f}%  minutes median {st.median(v['min'] for v in tops):.0f} (range {min(v['min'] for v in tops):.0f}-{max(v['min'] for v in tops):.0f})  repeated {st.mean(v['rt'] for v in tops)*100:.1f}%  shown {len(tops)}")

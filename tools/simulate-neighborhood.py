#!/usr/bin/env python3
"""Measure (1) retrace % and (2) forward-vs-reversed differences on real loops.

Runs on the Oracle box against local ORS. Replicates the app's pipeline exactly:
round_trip -> downsample to 8 waypoints (Handoff.swift) -> reroute -> that is the Loop.
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
SIZES = [(15, 4000)]
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



# ---------------- generate simulation ----------------
import sys
ORIGINS = [
    ("Marlboro NJ", 40.4001, -74.3457), ("Denver CO", 39.7392, -104.9903),
    ("Austin TX", 30.2672, -97.7431), ("Naperville IL", 41.7508, -88.1535),
    ("Plano TX", 33.0198, -96.6989), ("Cary NC", 35.7915, -78.7811),
    ("Levittown NY", 40.7259, -73.5143), ("Dyker Hts NY", 40.6215, -74.0151),
    ("Scottsdale AZ", 33.4942, -111.9261), ("Overland Pk KS", 38.9822, -94.6708),
    ("Roseville CA", 38.7521, -121.2880), ("Marietta GA", 33.9526, -84.5499),
]
SEEDS = range(1, 25)

def street(f):
    rows = (f["properties"].get("extras", {}).get("waytype", {}) or {}).get("summary", [])
    t = sum(r["distance"] for r in rows) or 1
    return sum(r["distance"] for r in rows if int(r["value"]) == 3) / t

def cand(o, minutes, meters, seed):
    name, lat, lon = o
    rt = round_trip(lat, lon, meters, seed)
    if not rt or not rt.get("features"):
        return None
    f = rt["features"][0]
    s = stats(f)
    return {"o": name, "m": minutes, "seed": seed, "coords": f["geometry"]["coordinates"],
            "est": s["duration"] / 60 * 0.75, "hw": s["highway"], "street": street(f)}

def verify(c):
    wps = downsample(c["coords"])
    if len(wps) != WAYPOINTS:
        return None
    start = c["coords"][0]
    r = reroute([start] + wps + [start])
    if not r or not r.get("features"):
        return None
    f = r["features"][0]; s = stats(f)
    return {"seed": c["seed"], "min": s["duration"] / 60, "hw": s["highway"], "street": street(f), "cstreet": c["street"],
            "rt": retrace_pct(f["geometry"]["coordinates"]) / 100}

jobs = [(o, m, me, s) for o in ORIGINS for (m, me) in SIZES for s in SEEDS]
with ThreadPoolExecutor(max_workers=6) as ex:
    cands = [c for c in ex.map(lambda a: cand(*a), jobs) if c]

def worth(cs, target):
    lo, hi = target * 0.55, target * 1.45
    ok = [c for c in cs if c["hw"] <= 0.20 and lo <= c["est"] <= hi]
    return ok

groups = {}
for c in cands:
    groups.setdefault((c["o"], c["m"]), []).append(c)
to_verify = []
for (o, m), cs in groups.items():
    for rnd in (range(1, 13), range(13, 25)):
        to_verify += worth([c for c in cs if c["seed"] in rnd], m)
with ThreadPoolExecutor(max_workers=6) as ex:
    vs = list(ex.map(verify, to_verify))
verified = {}
for c, v in zip(to_verify, vs):
    if v:
        verified.setdefault((c["o"], c["m"]), []).append(v)

json.dump({"cands": len(cands), "verified": {f"{k[0]}|{k[1]}": v for k, v in verified.items()}},
          open(sys.argv[1], "w"))
print("candidates", len(cands), "verified", sum(map(len, verified.values())))

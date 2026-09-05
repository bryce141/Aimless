#!/usr/bin/env python3
"""Measure (1) retrace % and (2) forward-vs-reversed differences on real loops.

Runs on the Oracle box against local ORS. Replicates the app's pipeline exactly:
round_trip -> downsample to 8 waypoints (Handoff.swift) -> reroute -> that is the Loop.
"""
import json, math, urllib.request, statistics
from concurrent.futures import ThreadPoolExecutor

ORS = "http://127.0.0.1:8080/ors/v2/directions/driving-car/geojson"
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


jobs = [(o, m, meters, s) for o in ORIGINS for (m, meters) in SIZES for s in SEEDS]
with ThreadPoolExecutor(max_workers=8) as ex:
    results = [x for x in ex.map(lambda a: one(*a), jobs) if x]

print(f"loops measured: {len(results)} of {len(jobs)} attempted\n")

# ---- 1. RETRACE, by duration option -------------------------------------
print("=" * 62)
print("RETRACE — % of drive on road covered twice (forward route)")
print("=" * 62)
print(f"{'size':>6} {'n':>4} {'median':>8} {'mean':>7} {'p90':>7} {'max':>7}  {'>10%':>6} {'>20%':>6}")
for m, _ in SIZES:
    v = sorted(x["fwd"]["retrace"] for x in results if x["minutes"] == m)
    if not v:
        continue
    p90 = v[min(len(v) - 1, int(len(v) * 0.9))]
    over10 = sum(1 for z in v if z > 10) / len(v) * 100
    over20 = sum(1 for z in v if z > 20) / len(v) * 100
    print(f"{m:>4}m {len(v):>4} {statistics.median(v):>7.1f}% {statistics.mean(v):>6.1f}% "
          f"{p90:>6.1f}% {max(v):>6.1f}%  {over10:>5.0f}% {over20:>5.0f}%")

print("\nby origin, 30-minute option only:")
for o, _, _ in ORIGINS:
    v = [x["fwd"]["retrace"] for x in results if x["minutes"] == 30 and x["origin"] == o]
    if v:
        print(f"  {o:<12} n={len(v):<3} median {statistics.median(v):>5.1f}%  max {max(v):>5.1f}%")

# ---- 2. REVERSAL --------------------------------------------------------
print("\n" + "=" * 62)
print("REVERSAL — forward vs reversed waypoint order")
print("=" * 62)
paired = [x for x in results if x["rev"]]
print(f"reversed route returned a result: {len(paired)} of {len(results)} "
      f"({len(paired)/len(results)*100:.0f}%)\n")

print(f"{'size':>6} {'n':>4} {'|Δdur| med':>11} {'|Δdur| max':>11} {'|Δdist| med':>12} {'Δhwy max':>9}")
for m, _ in SIZES:
    p = [x for x in paired if x["minutes"] == m]
    if not p:
        continue
    dd = sorted(abs(x["rev"]["duration"] - x["fwd"]["duration"]) / x["fwd"]["duration"] * 100 for x in p)
    ds = sorted(abs(x["rev"]["distance"] - x["fwd"]["distance"]) / x["fwd"]["distance"] * 100 for x in p)
    dh = max(abs(x["rev"]["highway"] - x["fwd"]["highway"]) * 100 for x in p)
    print(f"{m:>4}m {len(p):>4} {statistics.median(dd):>10.1f}% {max(dd):>10.1f}% "
          f"{statistics.median(ds):>11.1f}% {dh:>8.1f}pt")

alldd = [abs(x["rev"]["duration"] - x["fwd"]["duration"]) / x["fwd"]["duration"] * 100 for x in paired]
alldist = [abs(x["rev"]["distance"] - x["fwd"]["distance"]) / x["fwd"]["distance"] * 100 for x in paired]
print(f"\nduration within 5%: {sum(1 for d in alldd if d <= 5)/len(alldd)*100:.0f}% of loops")
print(f"duration within 10%: {sum(1 for d in alldd if d <= 10)/len(alldd)*100:.0f}%")
print(f"distance within 5%: {sum(1 for d in alldist if d <= 5)/len(alldist)*100:.0f}%")

# would reversal break the app's own filters?
broke = [x for x in paired if x["fwd"]["highway"] <= 0.15 and x["rev"]["highway"] > 0.15]
print(f"passed 15% highway forward but FAILED reversed: {len(broke)} of {len(paired)}")

worst = sorted(paired, key=lambda x: -abs(x["rev"]["duration"] - x["fwd"]["duration"]) / x["fwd"]["duration"])[:5]
print("\nworst 5 duration divergences:")
for x in worst:
    d = (x["rev"]["duration"] - x["fwd"]["duration"]) / x["fwd"]["duration"] * 100
    print(f"  {x['origin']:<12} {x['minutes']:>3}m seed {x['seed']:<3} "
          f"fwd {x['fwd']['duration']/60:>5.1f}m  rev {x['rev']['duration']/60:>5.1f}m  {d:>+6.1f}%")

# retrace forward vs reversed - should be identical if reversal is clean
rt_delta = [abs(x["rev"]["retrace"] - x["fwd"]["retrace"]) for x in paired]
print(f"\nretrace differs fwd vs rev by >2pt: "
      f"{sum(1 for d in rt_delta if d > 2)} of {len(paired)} loops")

json.dump(results, open("/tmp/loopdata.json", "w"))
print("\nraw -> /tmp/loopdata.json")

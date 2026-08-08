#!/usr/bin/env python3
"""
loopgen_ors.py - batch-generate round trips via OpenRouteService and dump GeoJSON.

round_trip works on the ORS free tier (GraphHopper's is paid-only).

usage:
    export ORS_KEY=your_ors_key
    python3 loopgen_ors.py --lat 40.4001 --lon -74.3457 --km 60 --n 10

writes loops.geojson -> drag onto https://geojson.io
note: ORS caps round trips at 100km.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.openrouteservice.org/v2/directions/driving-car/geojson"

# ORS waytype codes
WAYTYPE = {
    0: "unknown", 1: "state road", 2: "road", 3: "street",
    4: "path", 5: "track", 6: "cycleway", 7: "footway",
    8: "steps", 9: "ferry", 10: "construction",
}
# what we want on an aimless drive vs what we don't
GOOD_WAYTYPES = {2, 3}        # road, street
BAD_WAYTYPES = {1}            # state road
HIGHWAY_CATEGORY = 1          # waycategory bit for motorway


def fetch(key, lat, lon, meters, seed, points=5):
    body = {
        "coordinates": [[lon, lat]],
        "options": {
            "avoid_features": ["highways"],
            "round_trip": {
                "length": meters,
                "points": points,
                "seed": seed,
            }
        },
        "extra_info": ["waytype", "waycategory"],
        "instructions": False,
    }
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": key,
            "Content-Type": "application/json",
            "Accept": "application/geo+json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"  seed {seed}: HTTP {e.code} - "
              f"{e.read().decode('utf-8', 'replace')[:300]}", file=sys.stderr)
    except Exception as e:
        print(f"  seed {seed}: {e}", file=sys.stderr)
    return None


def summarize(extras, name):
    """ORS gives a ready-made distance summary per extra_info type"""
    block = (extras or {}).get(name, {})
    out = {}
    for row in block.get("summary", []):
        out[int(row["value"])] = row.get("distance", 0.0)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--km", type=float, default=60, help="target length, max 100")
    ap.add_argument("--n", type=int, default=10, help="how many seeds")
    ap.add_argument("--points", type=int, default=5,
                    help="waypoints in the loop, higher = wanderier")
    ap.add_argument("--out", default="loops.geojson")
    args = ap.parse_args()

    key = os.environ.get("ORS_KEY")
    if not key:
        sys.exit("set ORS_KEY first:  export ORS_KEY=your_ors_key")
    if args.km > 100:
        sys.exit("ORS caps round trips at 100km")

    meters = int(args.km * 1000)
    features = []

    print(f"{'seed':>5} {'km':>7} {'min':>5} {'backroad':>9} {'stateroad':>10} "
          f"{'hwy':>5}  top types")
    print("-" * 76)

    for seed in range(1, args.n + 1):
        data = fetch(key, args.lat, args.lon, meters, seed, args.points)
        if not data or not data.get("features"):
            continue

        feat = data["features"][0]
        props = feat["properties"]
        summ = props.get("summary", {})
        km = summ.get("distance", 0) / 1000
        mins = summ.get("duration", 0) / 60

        wt = summarize(props.get("extras"), "waytype")
        wc = summarize(props.get("extras"), "waycategory")
        total = sum(wt.values()) or 1.0

        good = sum(v for k, v in wt.items() if k in GOOD_WAYTYPES) / total
        state = sum(v for k, v in wt.items() if k in BAD_WAYTYPES) / total
        hwy = wc.get(HIGHWAY_CATEGORY, 0.0) / total

        top = sorted(wt.items(), key=lambda x: -x[1])[:3]
        top_s = ", ".join(f"{WAYTYPE.get(k, k)} {v/1000:.0f}km" for k, v in top)

        print(f"{seed:>5} {km:>7.1f} {mins:>5.0f} {good:>8.0%} {state:>9.0%} "
              f"{hwy:>4.0%}  {top_s}")

        features.append({
            "type": "Feature",
            "geometry": feat["geometry"],
            "properties": {
                "seed": seed,
                "km": round(km, 1),
                "minutes": round(mins),
                "backroad_pct": round(good * 100),
                "state_road_pct": round(state * 100),
                "highway_pct": round(hwy * 100),
                "stroke": "#d33" if (state + hwy) > 0.35 else "#2a8",
                "stroke-width": 3,
            },
        })

    features.append({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [args.lon, args.lat]},
        "properties": {"name": "start", "marker-color": "#000"},
    })

    with open(args.out, "w") as f:
        json.dump({"type": "FeatureCollection", "features": features}, f)

    print(f"\nwrote {args.out} ({len(features)-1} loops)")
    print("drag onto https://geojson.io - red = highway/state road heavy, green = back roads")


if __name__ == "__main__":
    main()

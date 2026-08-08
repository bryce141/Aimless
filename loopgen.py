#!/usr/bin/env python3
"""
loopgen.py - pull a batch of GraphHopper round trips and dump them as GeoJSON.

usage:
    export GH_KEY=your_api_key
    python3 loopgen.py --lat 40.4001 --lon -74.3457 --km 60 --n 10

writes loops.geojson -> drag it onto https://geojson.io to view.
prints a road-class breakdown per loop so you can spot the garbage ones
without opening the map.
"""

import argparse
import json
import math
import os
import sys
import urllib.parse
import urllib.request

API = "https://graphhopper.com/api/1/route"

# how much you probably care about each road type for an aimless drive.
# tweak these once you have opinions.
GOOD = {"secondary", "tertiary", "unclassified", "residential", "living_street"}
BAD = {"motorway", "motorway_link", "trunk", "trunk_link"}


def haversine(a, b):
    """meters between two [lon, lat] pairs"""
    lon1, lat1 = a
    lon2, lat2 = b
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def fetch(key, lat, lon, meters, seed, heading=None):
    params = [
        ("point", f"{lat},{lon}"),
        ("profile", "car"),
        ("algorithm", "round_trip"),
        ("round_trip.distance", str(meters)),
        ("round_trip.seed", str(seed)),
        ("ch.disable", "true"),
        ("points_encoded", "false"),
        ("instructions", "false"),
        ("details", "road_class"),
        ("key", key),
    ]
    if heading is not None:
        params.append(("heading", str(heading)))

    url = API + "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:300]
        print(f"  seed {seed}: HTTP {e.code} - {body}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  seed {seed}: {e}", file=sys.stderr)
        return None


def road_breakdown(coords, intervals):
    """intervals are [start_idx, end_idx, road_class] over the coord list"""
    dist = {}
    for start, end, cls in intervals:
        d = 0.0
        for i in range(start, min(end, len(coords) - 1)):
            d += haversine(coords[i], coords[i + 1])
        dist[cls] = dist.get(cls, 0.0) + d
    return dist


def score(dist):
    total = sum(dist.values()) or 1.0
    good = sum(v for k, v in dist.items() if k in GOOD)
    bad = sum(v for k, v in dist.items() if k in BAD)
    return good / total, bad / total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--km", type=float, default=60, help="target loop length")
    ap.add_argument("--n", type=int, default=10, help="how many seeds to try")
    ap.add_argument("--heading", type=int, default=None,
                    help="0-360, forces initial direction. 270 = head west")
    ap.add_argument("--out", default="loops.geojson")
    args = ap.parse_args()

    key = os.environ.get("GH_KEY")
    if not key:
        sys.exit("set GH_KEY first:  export GH_KEY=your_api_key")

    meters = int(args.km * 1000)
    features = []

    print(f"{'seed':>5} {'km':>7} {'min':>5} {'backroad':>9} {'highway':>8}  top road types")
    print("-" * 78)

    for seed in range(1, args.n + 1):
        data = fetch(key, args.lat, args.lon, meters, seed, args.heading)
        if not data or not data.get("paths"):
            continue

        path = data["paths"][0]
        coords = path["points"]["coordinates"]
        km = path["distance"] / 1000
        mins = path["time"] / 60000

        intervals = path.get("details", {}).get("road_class", [])
        dist = road_breakdown(coords, intervals) if intervals else {}
        good_pct, bad_pct = score(dist) if dist else (0, 0)

        top = sorted(dist.items(), key=lambda x: -x[1])[:3]
        top_s = ", ".join(f"{k} {v/1000:.0f}km" for k, v in top)

        print(f"{seed:>5} {km:>7.1f} {mins:>5.0f} {good_pct:>8.0%} {bad_pct:>7.0%}  {top_s}")

        features.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": coords},
            "properties": {
                "seed": seed,
                "km": round(km, 1),
                "minutes": round(mins),
                "backroad_pct": round(good_pct * 100),
                "highway_pct": round(bad_pct * 100),
                # geojson.io colors lines by these
                "stroke": "#d33" if bad_pct > 0.25 else "#2a8",
                "stroke-width": 3,
            },
        })

    # start marker
    features.append({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [args.lon, args.lat]},
        "properties": {"name": "start", "marker-color": "#000"},
    })

    with open(args.out, "w") as f:
        json.dump({"type": "FeatureCollection", "features": features}, f)

    print(f"\nwrote {args.out} ({len(features)-1} loops)")
    print("drag it onto https://geojson.io - red = lots of highway, green = mostly back roads")


if __name__ == "__main__":
    main()

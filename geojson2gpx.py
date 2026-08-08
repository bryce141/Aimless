#!/usr/bin/env python3
"""
geojson2gpx.py - turn loops.geojson into GPX files.

two uses:
  1. drop into Xcode as a simulated location source (Product > Scheme >
     Edit Scheme > Run > Options > Default Location)
  2. open on your phone in Gaia / Guru Maps to follow the actual track

usage:
    python3 geojson2gpx.py loops.geojson
    python3 geojson2gpx.py p8.geojson --seed 4
    python3 geojson2gpx.py loops.geojson --seed 4 --kmh 45 --timestamps

--timestamps paces the simulated drive. without them Xcode moves you along
at its own default speed, which is fine for checking the plumbing works.
"""

import argparse
import datetime as dt
import json
import math
import os
import sys
import xml.sax.saxutils as esc


def haversine(a, b):
    lon1, lat1 = a
    lon2, lat2 = b
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def thin(coords, min_meters):
    """drop points closer together than min_meters, keeps file size sane"""
    if not coords:
        return coords
    out = [coords[0]]
    for c in coords[1:]:
        if haversine(out[-1], c) >= min_meters:
            out.append(c)
    if out[-1] != coords[-1]:
        out.append(coords[-1])
    return out


def write_gpx(path, name, coords, kmh=None):
    start = dt.datetime.now(dt.timezone.utc)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="loopgen" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
        f"  <trk><name>{esc.escape(name)}</name><trkseg>",
    ]

    elapsed = 0.0
    for i, (lon, lat) in enumerate(coords):
        if kmh:
            if i > 0:
                d = haversine(coords[i - 1], coords[i])
                elapsed += d / (kmh * 1000 / 3600)
            ts = (start + dt.timedelta(seconds=elapsed)).strftime("%Y-%m-%dT%H:%M:%SZ")
            lines.append(f'    <trkpt lat="{lat:.6f}" lon="{lon:.6f}">'
                         f"<time>{ts}</time></trkpt>")
        else:
            lines.append(f'    <trkpt lat="{lat:.6f}" lon="{lon:.6f}"></trkpt>')

    lines += ["  </trkseg></trk>", "</gpx>"]
    with open(path, "w") as f:
        f.write("\n".join(lines))


def waypoint_url(coords, n=8):
    """the google maps handoff url, for testing shape fidelity in a browser"""
    total = sum(haversine(coords[i], coords[i + 1]) for i in range(len(coords) - 1))
    step = total / (n + 1)
    picks, acc, target = [], 0.0, step
    for i in range(len(coords) - 1):
        acc += haversine(coords[i], coords[i + 1])
        if acc >= target and len(picks) < n:
            picks.append(coords[i + 1])
            target += step
    start = coords[0]
    wp = "|".join(f"{lat:.5f},{lon:.5f}" for lon, lat in picks)
    return ("https://www.google.com/maps/dir/?api=1"
            f"&origin={start[1]:.5f},{start[0]:.5f}"
            f"&destination={start[1]:.5f},{start[0]:.5f}"
            f"&waypoints={wp}&travelmode=driving")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("infile")
    ap.add_argument("--seed", type=int, help="export only this seed")
    ap.add_argument("--kmh", type=float, default=45)
    ap.add_argument("--timestamps", action="store_true",
                    help="pace the track at --kmh")
    ap.add_argument("--thin", type=float, default=25,
                    help="min meters between points")
    ap.add_argument("--outdir", default="gpx")
    args = ap.parse_args()

    if not os.path.exists(args.infile):
        sys.exit(f"no such file: {args.infile}")

    with open(args.infile) as f:
        data = json.load(f)

    os.makedirs(args.outdir, exist_ok=True)
    made = 0

    for feat in data.get("features", []):
        if feat.get("geometry", {}).get("type") != "LineString":
            continue
        props = feat.get("properties", {})
        seed = props.get("seed", made + 1)
        if args.seed and seed != args.seed:
            continue

        coords = thin(feat["geometry"]["coordinates"], args.thin)
        name = f"loop_seed{seed}_{props.get('km', '?')}km"
        out = os.path.join(args.outdir, f"{name}.gpx")
        write_gpx(out, name, coords, args.kmh if args.timestamps else None)
        made += 1

        print(f"\n{out}  ({len(coords)} points)")
        print("  google maps handoff url, paste in a browser to check shape:")
        print("  " + waypoint_url(coords))

    if not made:
        sys.exit("nothing exported, check --seed matches a loop in the file")
    print(f"\n{made} gpx file(s) in {args.outdir}/")


if __name__ == "__main__":
    main()

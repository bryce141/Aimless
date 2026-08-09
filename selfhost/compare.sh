#!/usr/bin/env bash
# Fires the app's real request shape at the local instance and at HeiGIT, on the
# same seeds, and prints what came back side by side.
#
# The question this exists to answer is narrow: does `round_trip` work on a
# self-hosted instance at all? Everything about the app is built on that one
# parameter, so if the answer is no, nothing else about self-hosting matters.
#
# Secondary: do the two agree closely enough that swapping the backend doesn't
# silently change the durations the app prints?
set -uo pipefail
cd "$(dirname "$0")"

LOCAL="http://localhost:8080/ors/v2/directions/driving-car/geojson"
# Through our Worker rather than straight at ORS: the ORS key no longer exists
# outside the Worker's secret store, and this is the exact path the app takes,
# which makes it the honest thing to compare against.
REMOTE="https://aimless-routing.bdrp777.workers.dev/v2/directions/driving-car/geojson"

# Marlboro NJ — the origin used for the store screenshots.
LON=-74.3457
LAT=40.4001
# The app's 60-minute request size. See DurationOption.
METERS=${METERS:-33000}
SEEDS=${SEEDS:-"1 2 3 4"}

TOKEN=$(sed -n 's/.*clientToken *= *"\([^"]*\)".*/\1/p' ../Aimless/Config.swift 2>/dev/null)

body() {
  cat <<EOF
{"coordinates":[[$LON,$LAT]],
 "options":{"round_trip":{"length":$METERS,"points":8,"seed":$1}},
 "extra_info":["waytype","waycategory"],
 "instructions":false}
EOF
}

# Pulls the numbers the app actually uses out of a GeoJSON response: duration,
# distance, highway share (waycategory bit 0), and the polyline point count.
summarize() {
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("unparseable"); sys.exit()
if "features" not in d:
    print("ERROR", json.dumps(d.get("error", d))[:110]); sys.exit()
f=d["features"][0]; s=f["properties"]["summary"]
ex=f["properties"].get("extras",{})
def by(v):
    out={}
    for r in ex.get(v,{}).get("summary",[]): out[int(r["value"])]=out.get(int(r["value"]),0)+r["distance"]
    return out
wt,wc=by("waytype"),by("waycategory")
tot=sum(wt.values())
hw=sum(v for k,v in wc.items() if k&1)
print("%6.1f min %6.1f mi  hwy %4.1f%%  pts %5d  waytype_keys %s" % (
    s["duration"]/60, s["distance"]/1609.34, (hw/tot*100 if tot else -1),
    len(f["geometry"]["coordinates"]), sorted(wt) or "NONE"))
'
}

printf '%-6s %-8s %s\n' "seed" "backend" "result"
for seed in $SEEDS; do
  out=$(curl -s -m 60 -X POST "$LOCAL" \
        -H 'Content-Type: application/json' -H 'Accept: application/geo+json' \
        -d "$(body "$seed")" | summarize)
  printf '%-6s %-8s %s\n' "$seed" "local" "$out"

  if [ -n "$TOKEN" ]; then
    out=$(curl -s -m 60 -X POST "$REMOTE" \
          -H "X-Aimless-Client: $TOKEN" \
          -H 'Content-Type: application/json' -H 'Accept: application/geo+json' \
          -d "$(body "$seed")" | summarize)
    printf '%-6s %-8s %s\n' "$seed" "heigit" "$out"
    # HeiGIT allows 40/min. Stay well clear.
    sleep 2
  fi
  echo
done

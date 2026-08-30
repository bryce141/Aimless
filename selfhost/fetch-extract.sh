#!/usr/bin/env bash
# Downloads every region we self-host and merges them into one extract.
#
# TWO SEPARATE IDEAS ARE IN THIS LIST, and mixing them up produces wrong routes.
#
# 1. Regions we *serve*: New Jersey and California. Those are the boxes in
#    REGIONS in worker/src/index.js, and they are where the Worker sends traffic
#    to us instead of to HeiGIT.
#
# 2. Regions we *build*: the served ones plus their neighbours. A graph ends at
#    the edge of its extract, and a route generated near that edge is clipped
#    against roads that simply stop existing — it comes back plausible-looking
#    and too short, with no error at all. Montague NJ returned a loop 19% short
#    against a NJ-only graph.
#
#    So New Jersey is built with PA, NY and DE around it. California is built
#    alone, and the served box is inset from its land borders instead — the
#    state is 1,200 km tall and adding Nevada, Oregon and Arizona to cover its
#    edges would roughly double an extract that already dominates the build.
#
# California is here because App Review is: four reviews, four iPads, all of
# them somewhere around Cupertino, every one of them routed to HeiGIT and its
# shared daily quota. See DEPLOY.md, "Widening coverage".
#
# Geofabrik regenerates these daily, so re-running this is also how you refresh
# stale road data, followed by REBUILD_GRAPHS=True on the next start.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

base=https://download.geofabrik.de/north-america/us
regions=(new-jersey pennsylvania new-york delaware california)

for s in "${regions[@]}"; do
  curl -L --fail -o "data/$s.osm.pbf" "$base/$s-latest.osm.pbf"
done

# osmium merge: brew install osmium-tool / apt install osmium-tool
#
# The two groups are geographically disjoint and stay that way in the graph —
# there is no road between them inside this extract. That is fine: a round trip
# never leaves the component it started in, and both components are far larger
# than the size at which ORS prunes disconnected subnetworks.
inputs=()
for s in "${regions[@]}"; do inputs+=("data/$s.osm.pbf"); done

osmium merge "${inputs[@]}" --overwrite -o data/coverage.osm.pbf

# Keep only the merged file. The inputs are 2 GB of nothing once merged, and the
# box has other things to do with its disk.
for s in "${regions[@]}"; do rm -f "data/$s.osm.pbf"; done

ls -lh data/coverage.osm.pbf

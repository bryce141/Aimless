#!/usr/bin/env bash
# Builds the merged extract the routing graph is built from.
#
# TWO SEPARATE IDEAS ARE IN HERE, and mixing them up produces wrong routes.
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
# EVERYTHING COMES FROM GEOFABRIK, and the reason is not brand loyalty.
#
# Geofabrik clips with *complete ways*: every node referenced by a way in the
# file is also in the file. Not every extract service does, and one that does
# not is unusable here — GraphHopper reads a way, looks for a node that was
# never included, and fails the entire build with
# "Could not parse OSM file", four minutes in, naming nothing.
#
# Measured on 2026-08-30, `osmium check-refs -r`, "nodes in ways missing":
#
#   Geofabrik north-east bundle        0
#   OpenStreetMap France California    13,085
#
# Geofabrik was down for hours that day — their own proxy returning
# ERR_CONNECT_FAIL — so California was taken from the OSMfr mirror instead. It
# cost two failed graph builds before the check below existed. OSMfr is a fine
# service and its file is a valid PBF; it simply clips differently, and the
# difference is invisible until an hour-long build dies without a cause.
#
# If Geofabrik is down again, waiting is cheaper than substituting. Any
# replacement must show 0 missing nodes in ways, and the check below enforces
# that rather than trusting it.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

geofabrik=https://download.geofabrik.de/north-america/us

# Fails the build early on an extract that would fail it late. `check-refs`
# reads the whole file, which is minutes; the build it saves is over an hour.
#
# Only nodes-in-ways is fatal. Missing *relation* members are normal and present
# in the bundle that serves today — a relation routinely names things outside
# any extract's boundary. A way missing its nodes is a hole in the road network.
require_complete_ways() {
  local f=$1 out missing
  # check-refs exits non-zero when *anything* is missing, including the relation
  # members that are missing from every extract ever clipped. Its exit status is
  # therefore useless here and `|| true` is load-bearing: without it `set -e`
  # kills the script before the number below is ever read.
  out=$(osmium check-refs -r "$f" 2>&1) || true
  missing=$(printf '%s\n' "$out" |
            sed -n 's/^Nodes *in ways *missing: *\([0-9]*\)/\1/p')
  if [[ -z $missing ]]; then
    echo "FAIL: could not read check-refs output for $f" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  if (( missing != 0 )); then
    echo "FAIL: $f has $missing ways referencing nodes it does not contain." >&2
    echo "      GraphHopper cannot build from this. Use a complete-ways extract." >&2
    exit 1
  fi
  echo "verified: $f has complete ways"
}

# The northeast bundle, pre-merged. Delete data/nj-region.osm.pbf to re-fetch;
# otherwise an existing one is reused, which is what makes adding a region cheap
# and what makes this runnable while Geofabrik is having a bad day.
northeast=(new-jersey pennsylvania new-york delaware)

if [[ -f data/nj-region.osm.pbf ]]; then
  echo "reusing data/nj-region.osm.pbf ($(du -h data/nj-region.osm.pbf | cut -f1))"
else
  for s in "${northeast[@]}"; do
    curl -L --fail -o "data/$s.osm.pbf" "$geofabrik/$s-latest.osm.pbf"
  done
  inputs=()
  for s in "${northeast[@]}"; do inputs+=("data/$s.osm.pbf"); done
  osmium merge "${inputs[@]}" --overwrite -o data/nj-region.osm.pbf
  for s in "${northeast[@]}"; do rm -f "data/$s.osm.pbf"; done
fi

# California. Same rule: delete the file to refresh it.
if [[ -f data/california.osm.pbf ]]; then
  echo "reusing data/california.osm.pbf ($(du -h data/california.osm.pbf | cut -f1))"
else
  curl -L --fail -o data/california.osm.pbf "$geofabrik/california-latest.osm.pbf"
fi

require_complete_ways data/nj-region.osm.pbf
require_complete_ways data/california.osm.pbf

# DEDUPE BEFORE MERGING, or the graph build dies.
#
# The two extracts are generated on different days. Anything edited in between
# that appears in both of them lands in the merge twice, at two versions. The
# PBF header still says "not a history file", and GraphHopper throws
# "Could not parse OSM file" on the whole thing — five minutes in, with no
# indication of which object caused it. That is what happened on 2026-08-30:
# r148838, the United States national boundary (admin_level=2), at v1043 from
# the Geofabrik bundle and v1044 from OSMfr, because someone edited the US
# border on 2026-08-25.
#
# Only relations need checking, and that is a fact about geometry rather than a
# shortcut: a node has a location and a way is a list of nodes, so neither can
# appear in two extracts that do not overlap. A relation is only a membership
# list, so a continent-sized one lands in every extract on the continent. The
# node and way counts across the 2026-08-30 merge were exactly additive —
# 290,651,982 and 32,033,580 — which is that argument holding in practice.
#
# Duplicates are dropped from the northeast bundle rather than California, so
# the surviving copy is the newer of the two.
osmium cat -t relation data/nj-region.osm.pbf  -f opl -o - | awk '{print $1}' | sort -u > data/.rel-ne.ids
osmium cat -t relation data/california.osm.pbf -f opl -o - | awk '{print $1}' | sort -u > data/.rel-ca.ids
comm -12 data/.rel-ne.ids data/.rel-ca.ids > data/.rel-dupe.ids
dupes=$(wc -l < data/.rel-dupe.ids)

northeast_input=data/nj-region.osm.pbf
if (( dupes > 0 )); then
  echo "dropping $dupes relation(s) present in both extracts:"
  sed 's/^/  /' data/.rel-dupe.ids
  osmium removeid data/nj-region.osm.pbf -i data/.rel-dupe.ids \
    --overwrite -o data/nj-region-deduped.osm.pbf
  northeast_input=data/nj-region-deduped.osm.pbf
fi
rm -f data/.rel-ne.ids data/.rel-ca.ids

# osmium merge: brew install osmium-tool / apt install osmium-tool
#
# A round trip never leaves the component it started in, and both components are
# far larger than the size at which ORS prunes disconnected subnetworks, so the
# gap between them costs nothing.
osmium merge "$northeast_input" data/california.osm.pbf \
  --overwrite -o data/coverage.osm.pbf

# Prove the thing that killed the last build is gone before spending an hour
# finding out the slow way. Anything but "no" here means the merge is unusable.
if osmium fileinfo -e data/coverage.osm.pbf | grep -q "Multiple versions of same object: yes"; then
  echo "FAIL: coverage.osm.pbf still contains multiple versions of an object." >&2
  exit 1
fi
echo "verified: no duplicate objects in coverage.osm.pbf"

rm -f data/nj-region-deduped.osm.pbf

# The two inputs are deliberately kept. Together they are the cache that makes a
# rebuild cheap, and nj-region.osm.pbf is also the rollback source — the graph
# serving today was built from it, so a failed California build can go straight
# back to a New Jersey one without downloading anything.

ls -lh data/coverage.osm.pbf

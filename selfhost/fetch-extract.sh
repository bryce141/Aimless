#!/usr/bin/env bash
# Downloads the New Jersey OSM extract that the graph is built from.
# Geofabrik regenerates these daily, so a re-fetch is also how you refresh
# stale road data — followed by REBUILD_GRAPHS=True on the next start.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data
curl -L --fail -o data/new-jersey-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/new-jersey-latest.osm.pbf
ls -lh data/new-jersey-latest.osm.pbf

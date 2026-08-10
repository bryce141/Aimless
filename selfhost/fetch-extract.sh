#!/usr/bin/env bash
# Downloads New Jersey and its neighbours and merges them into one extract.
#
# The neighbours are not optional. A NJ-only graph ends at the state line, and
# routes near the border either fail outright or come back silently short —
# Montague returned a loop 19% shorter than reality with no error. See README.
#
# Geofabrik regenerates these daily, so re-running this is also how you refresh
# stale road data, followed by REBUILD_GRAPHS=True on the next start.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

base=https://download.geofabrik.de/north-america/us
for s in new-jersey pennsylvania new-york delaware; do
  curl -L --fail -o "data/$s.osm.pbf" "$base/$s-latest.osm.pbf"
done

# osmium merge: brew install osmium-tool
osmium merge data/new-jersey.osm.pbf data/pennsylvania.osm.pbf \
             data/new-york.osm.pbf data/delaware.osm.pbf \
             -o data/nj-region.osm.pbf --overwrite

rm -f data/pennsylvania.osm.pbf data/new-york.osm.pbf data/delaware.osm.pbf
ls -lh data/nj-region.osm.pbf

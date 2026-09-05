#!/bin/bash
# Cross-checks Aimless/Services/Geometry.swift against the Python reference in
# tools/measure-geometry.py, on real ORS routes.
#
# Deliberately does NOT use the Xcode project: Aimless.xcodeproj is hand-written
# with a single target and no test target, and adding one would mean editing the
# fragile project file. These are pure functions, so swiftc alone is enough.
#
# Fixtures are generated on the Oracle box (see tools/measure-geometry.py) and
# cached at tools/geometry-check/fixtures.json.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

if [ ! -f fixtures.json ]; then
  echo "fixtures.json missing — regenerate with:" >&2
  echo "  scp tools/measure-geometry.py box:/tmp/ && ssh box python3 /tmp/fixtures.py" >&2
  exit 2
fi

echo "compiling..."
swiftc -O \
  "$ROOT/Aimless/Services/Geometry.swift" \
  main.swift \
  -o "$OUT/geometry-check"

echo "running..."
"$OUT/geometry-check" fixtures.json

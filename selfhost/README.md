# Self-hosted openrouteservice

A local ORS instance built from the New Jersey OSM extract, run to answer one
question before spending money on a VPS:

> **Does `round_trip` work on a self-hosted instance?**

Everything the app does rests on that one parameter. If the answer were no,
nothing else about self-hosting would matter.

**The answer is yes**, and the results match HeiGIT closely enough to swap
backends without changing the numbers the app prints.

## Running it

```
./fetch-extract.sh          # 155 MB from Geofabrik
docker compose up -d        # first start builds the graph, ~4 min
curl localhost:8080/ors/v2/health
./compare.sh                # same seeds, local vs the Worker, side by side
```

Requires a Docker runtime. On macOS, `brew install colima docker docker-compose`
then `colima start --cpu 6 --memory 10 --disk 40` — Colima needs no GUI and
raises no Docker Desktop licensing question. `docker compose` only finds the
Homebrew plugin after
`ln -s /opt/homebrew/bin/docker-compose ~/.docker/cli-plugins/docker-compose`.

Set `REBUILD_GRAPHS: "True"` in `docker-compose.yml` to force a rebuild after
changing the extract or anything under `build:` in `ors-config.yml`. Changes
under `service:` only need a restart.

## What it cost to build

Measured on an M-series Mac, 6 CPUs and 10 GB given to the VM, `driving-car`
only:

| | |
|---|---|
| Extract | 155 MB (New Jersey, Geofabrik) |
| Graph build | **219 s** |
| Peak heap | **1.7 GB** |
| Graph on disk | 285 MB |
| Elevation cache | 1.2 GB |

The peak heap is the number that sizes the box. 1.7 GB for a state means a
**4 GB VPS is enough** and 8 GB is comfortable — roughly €7/month at Hetzner,
whose Ashburn VA region is a few milliseconds from New Jersey.

Note the elevation cache is four times the size of the graph. It's SRTM tiles,
it's reusable across rebuilds, and it's the reason to give the box 20 GB of disk
rather than 10.

## What it answered

### 1. `round_trip` works, and agrees with HeiGIT

Same origin (Marlboro NJ), same seeds, same 33 km request the app uses for its
60-minute option:

| Seed | | Duration | Distance | Highway |
|---|---|---|---|---|
| 1 | local | 79.1 min | 29.4 mi | 0.0% |
| 1 | HeiGIT | 78.2 min | 29.1 mi | 0.0% |
| 2 | local | 71.9 min | 31.2 mi | 0.0% |
| 2 | HeiGIT | 71.0 min | 30.9 mi | 0.0% |
| 3 | local | 86.8 min | 41.0 mi | 27.5% |
| 3 | HeiGIT | 86.0 min | 40.7 mi | 27.7% |
| 4 | local | 89.3 min | 35.7 mi | 0.0% |
| 4 | HeiGIT | 88.6 min | 35.6 mi | 0.0% |

Within ~1% on every seed, and the highway share — the signal the whole filter
runs on — tracks to within 0.2 points. `waytype` and `waycategory` come back
populated, so `RouteService.roadStats` needs no changes.

The small consistent gap is explained: the local extract is a daily snapshot
taken 2026-08-06, HeiGIT's is whenever they last rebuilt, and the elevation
provider differs (see below). Local reading *slightly longer* on all four seeds
is a bias worth re-checking if it ever matters, but it is far inside the
duration filter's tolerance.

**Seeds stay deterministic self-hosted.** Same seed, same result, as with
HeiGIT — so the retry logic's requirement for *fresh* seed numbers still holds.

### 2. It is 30-50x faster, and there is no rate limit

| | Per request | 12-request burst |
|---|---|---|
| Through the Worker to HeiGIT | 430-970 ms | rate-limited at 40/min |
| Local | **12-23 ms** | **0.11 s, twelve 200s** |

Discount that some — localhost has no network in it. A Hetzner box in Ashburn
adds maybe 15-30 ms RTT from New Jersey, so call it ~50 ms per request in
practice. Still an order of magnitude, and a generate would go from 1-2 s to
near-instant.

**This dissolves the concurrency problem rather than solving it.** The reason
`generateRoundTrips` firing 12 at once is a licence risk is that the 12 land on
someone else's server. On our own box, twelve concurrent requests finished in
110 ms and the throttle discussion is moot for any traffic we route locally.

### 3. The 100 km ceiling is ours to move

`RouteService.maxRequestMeters = 100_000` was found empirically, by hitting
HTTP 400 against HeiGIT. It turns out to be `maximum_distance_round_trip_routes`
in ORS's default config — not a property of the algorithm.

Raised it to 200 km here and re-tested (restart only, no rebuild):

| Request | HeiGIT | Local, raised |
|---|---|---|
| 100 km | 169 min, 71.9 mi | same |
| 120 km | HTTP 400 | **192 min, 97.8 mi** |
| 150 km | HTTP 400 | **210 min, 116.4 mi** |

So a 3-hour duration option is possible self-hosted and simply is not on the
public instance. That's a product capability, not just an optimisation.

## Gotcha worth its own section: elevation

The first build failed after 37 seconds with:

```
java.lang.RuntimeException: Could not parse OSM file: /home/ors/files/new-jersey-latest.osm.pbf
```

The OSM file was fine — byte-identical to Geofabrik's published MD5, and a
container read it end to end in 0.27 s.

The real cause is the elevation provider. ORS defaults to `multi`, which selects
CGIAR at this latitude, and `srtm.csi.cgiar.org` does not respond — connections
hang for the full 30 s timeout with zero bytes. GraphHopper catches that
somewhere inside OSM reading and rethrows it as a parse error, which points
every debugging instinct at the wrong file.

`provider: skadi` — the same SRTM data from AWS S3 — returns HTTP 200 and the
build completes. That one line is the difference between working and a
misleading error.

**If a self-hosted build fails to "parse" a checksum-verified extract, suspect
elevation first.**

## Incidental find

ORS's own default config, extracted from the image, contains:

```yaml
attribution: © openrouteservice by HeiGIT | Data from OpenStreetMap
```

Independent confirmation of the attribution string, from the software rather
than from the terms of service or from secondary sources — which disagreed with
both. See `example-ors-config.yml`.

## What this does not answer

- **Coverage.** This box knows New Jersey. The shipped app works anywhere on
  Earth because HeiGIT hosts the planet. Self-hosting is only viable as a *tier*
  in front of HeiGIT, not a replacement — route by bounding box, fall back on
  timeout. North America is a ~14 GB extract needing far more RAM than €7/month
  buys; the planet is not realistic on any single cheap box.
- **Sustained load.** Twelve concurrent requests once is not the same as
  sustained traffic, and nothing here measured a cold JVM under real use.
- **Staleness.** Geofabrik regenerates daily; nothing here refreshes the extract
  or rebuilds on a schedule. That's operational work HeiGIT currently does for
  free.

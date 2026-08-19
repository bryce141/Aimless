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

## Measured on Oracle, 2026-08-19

Deployed to an Oracle Cloud always-free instance: `VM.Standard.A1.Flex`,
2 OCPU / 12 GB Ampere, Ubuntu 24.04 aarch64, US East (Ashburn) AD-2.
`DEPLOY.md` is the runbook.

| | M-series, 6 cores | **Ampere, 2 cores** |
|---|---|---|
| Extract | 0.98 GB | 0.98 GB |
| Graph build | 955 s | **1742 s** |
| Graph on disk | 1.3 GB | 1.3 GB |
| Single request | 12-44 ms | **38-80 ms** |
| 12 concurrent | 0.11 s | **0.73 s** |

**Build time scaled with cores rather than collapsing** — 1.8x longer on a third
the cores, because much of the graph build is single-threaded. Half an hour
unattended, which is nothing.

**Read the container's memory figure carefully.** `docker stats` reports 6.1 GB,
which looks alarming on a 12 GB box until you check the host: 2.8 GB actually
used, 7.7 GB in page cache, 8.8 GB available. That is `MMAP` working exactly as
intended — the graph lives in reclaimable page cache, not in the heap. Sizing a
box on the `docker stats` number would triple the requirement for no reason.

**The 12-concurrent figure is the one that matters, and it is the honest one.**
A generate is ~18 requests, so 0.73 s for 12 puts a full generate near 1.1 s and
sustained throughput around 16 requests/second — call it **50 generates per
minute against HeiGIT's 2**. That is the entire point of the exercise. Note it
is throughput, not latency, that was bought: a single request got faster, but
under a real burst two Ampere cores queue where six M-series cores did not.

### Parity against HeiGIT, eight seeds

Same origin (Marlboro NJ), same 33 km request, run simultaneously:

| Seed | Duration delta | Highway share |
|---|---|---|
| 1, 2, 4, 8 | <1% | 0.0 vs 0.0 |
| 3 | 0.9% | **27.5 vs 27.7** |
| 5 | 0.6% | 9.2 vs 9.2 |
| 6 | 0.1% | 3.2 vs 3.2 |
| 7 | 0.6% | 26.0 vs 25.5 |

Within ~1% on duration and 0.6 points on highway share across all eight. Safe to
swap.

**One trap worth writing down, because it cost a false alarm.** A first pass at
this comparison matched `waycategory == 1` for motorway and reported seed 3 as
9.0% locally against 27.7% from HeiGIT — a scary-looking regression in the exact
signal the app filters on. The bug was in the comparison, not the graph.
**`waycategory` is a bitmask**, and a tolled motorway comes back as `1|16 = 17`,
which an equality test silently drops. In New Jersey that is most of the highway
network. `RouteService.roadStats` has always done this correctly (`value &
highwayBit != 0`); only the throwaway test script was wrong. Any future
comparison must mask, not compare.

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

## Could this cover the whole US?

Yes, and the reason it's affordable is that **building and serving are separate
jobs with very different costs.** ORS treats them as separable on purpose:
`preparation_mode` builds a graph and exits, and `graphs_data_access` decides
whether serving loads the graph into heap or maps it from disk.

Measured here, same graph, restart only:

| Serving mode | Container memory | Latency after warmup |
|---|---|---|
| `RAM_STORE` (default) | 1.12 GB | 12-23 ms |
| `MMAP` | **573 MB** | 12-44 ms (first request 200 ms) |

Half the memory for no meaningful latency cost, because the OS page cache does
the work the heap was doing. `MMAP` is set in `ors-config.yml` for that reason.

So the cost of *serving* New Jersey is ~570 MB, while *building* it peaked at
1.7 GB — 3x more. That gap is what makes national coverage tractable: rent a big
machine for the hours it takes to build, then serve the result from a small one.

### Build memory barely grows with the extract

This is the finding that matters, and extrapolation got it badly wrong.

| | New Jersey | NJ + PA + NY + DE |
|---|---|---|
| PBF | 0.16 GB | 0.98 GB (6x) |
| Graph on disk | 285 MB | 1.3 GB |
| **Peak heap** | 1.7 GB | **1.96 GB** |
| Build time | 219 s | 955 s |
| Serving memory | 573 MB | 1.12 GB |

A 6x larger extract cost **15% more heap**. Scaling New Jersey's 1.7 GB linearly
predicted ~10 GB and was wrong by 5x, because `graphs_data_access: MMAP` keeps
the graph off-heap during the build too — the JVM heap holds working state, not
the graph, so it stays roughly flat while disk and page cache absorb the growth.

Disk and build time do scale with the extract. Heap does not. Anyone sizing a
box should budget for the first two and stop worrying about the third.

Extrapolating the whole US from this is still unwise, but the direction is
clear: the binding constraints are disk (~21 GB of graph) and build hours, not
RAM.

### New Jersey needs its neighbours

The Geofabrik NJ extract's bounds are the state outline with no buffer, so roads
stop dead at the state line. Measured against HeiGIT from a NJ-only graph:

| Origin | NJ-only graph | HeiGIT |
|---|---|---|
| Marlboro (interior) | 79.1 min | 78.2 min |
| Lambertville (PA edge) | **error** | 91.9 min |
| Jersey City (NY edge) | **error** | 109.7 min |
| Montague (NW corner) | **113.2 min / 47.1 mi** | 139.3 min / 60.1 mi |

The errors are survivable — the app already swallows dead seeds. Montague is
not: it returned a loop 19% short with no error, because the router worked
inside a box whose roads ended. Nothing at runtime could detect that.

Merging PA, NY and DE in (`osmium merge`, 977 MB combined) fixes all three —
every border origin now matches HeiGIT exactly. Cape May still fails on both,
which is geography rather than coverage: it is a peninsula tip with water on
three sides.

**A bounding box is the wrong shape for routing decisions here.** New Jersey is
not a rectangle, and its bbox contains large parts of three other states. With
the neighbours merged in, that stops mattering — the graph covers everything the
bbox does.

### Two ways to cover more than one region

**One national graph.** Build on a rented high-memory machine, keep the ~21 GB
result, serve it with `MMAP` from an ordinary box. The build machine is needed
only for the build and for periodic refreshes, so it's rented by the hour rather
than owned. This is the simpler architecture and has no border seams.

**Shard by region.** Several instances, each holding a few states, routed by
bounding box. Every shard builds in minutes on cheap hardware, rebuilds
independently, and a dead shard degrades to a HeiGIT fallback for that region
instead of taking everything down. The cost is a real quality problem: **routes
near an extract's edge get clipped**, because the graph simply ends there. A
loop generated near a state line would be wrong in a way that is hard to notice.
Sharding by large multi-state regions rather than by state reduces how often that
happens without eliminating it.

Neither is expensive in money. Both are ongoing operational work — a stale
extract is a wrong route, and refreshing means rebuilding.

## What this still does not answer

- **Whether it's worth doing.** Nothing above is a reason to self-host; it only
  establishes that national coverage is affordable rather than impossible. The
  app currently has no users and no rate-limit problem in production.
- **Sustained load.** Twelve concurrent requests once is not sustained traffic,
  and nothing here measured a cold JVM under real use.
- **Staleness.** Geofabrik regenerates daily; nothing here refreshes the extract
  or rebuilds on a schedule. That's operational work HeiGIT currently does for
  free.
- **Edge behaviour.** Every route tested started in interior New Jersey. Nothing
  here measured what a loop near the Delaware River does when the graph stops at
  the state line.

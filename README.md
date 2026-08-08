# Aimless

An iOS app that generates a circular driving route starting and ending where you
are. You pick roughly how long you want to be out; it hands you three loops and
opens one in Google Maps.

It exists to solve a specific annoyance: you drive somewhere with no
destination, get too far out, and the return leg is dead time retracing roads
you just covered.

## How it works

The interesting problem isn't asking a routing API for a round trip. It's that
**the route you'd display is not the route you'd drive**, and the gap is large
enough to make the app lie to you.

Aimless hands Google Maps a set of waypoints, because Google is what actually
navigates. Google then re-routes between those waypoints, taking straighter and
faster paths than the wandering original — measured at **72–82% of the round
trip's duration**. An app that generates a 90-minute loop and hands off a
64-minute drive is wrong in the only number the user cares about.

The fix was to stop producing the wrong number rather than correct it. A round
trip is treated as a *candidate*, never a result:

1. Ask OpenRouteService for 12 round-trip candidates, concurrently.
2. Pre-filter cheaply on data already in hand — highway share, rough duration.
   Keep at most 6.
3. Downsample each to 8 waypoints and re-route *through those waypoints* — the
   same thing Google will do.
4. That rerouted path is the `Loop`. Its polyline gets drawn, its duration gets
   printed, its waypoints get handed off.
5. Filter and rank on the verified duration and highway share.

`RoundTrip` and `Loop` are deliberately separate types. Conflating them is what
let an earlier version display a duration nobody would drive.

Cost: ~18 requests and about a second per generate. All three duration options
land within 4% of target.

## What measurement changed

The design is built on roughly 400 live API requests rather than assumptions.
Most of what the first draft assumed turned out to be wrong:

| Assumption | Reality |
|---|---|
| Distance overshoots by a flat 30% | Overshoot scales inversely with request size — 3.2× at 4km, 1.4× at 63km |
| Back roads average 45 km/h | 25–27 km/h on small loops, ~44 km/h on large ones |
| Duration is computable from request size | Per-seed variance is enormous — one 13km request returned drives from 40 to 90 minutes |
| ~1 in 3 requests fail | 6–10%, clustered at the largest sizes, and some are HTTP 500 rather than 404 |
| Seeds are random | Fully deterministic — same seed, origin and size returns byte-identical results forever, failures included |

Two of those compounded into a real bug: a wrong speed constant multiplied by a
wrong overshoot constant turned "30 minutes" into a 62-minute drive. The fix was
to stop computing duration from the request entirely and instead filter on the
duration the API actually returns.

The deterministic-seed finding has a non-obvious consequence: a retry round must
request *fresh* seed numbers. Re-rolling the same ones re-fetches the identical
failures for the identical cost.

## Design decisions worth explaining

**No 30-minute option.** Not a limitation — geometry. Landing at 30 minutes from
a fixed origin needs a ~4km request, and those loops spend 87% of their length
within 2km of the start. It's a lap around the block. The picker floors at 60.

**No Apple Maps fallback.** Apple exposes no multi-stop routing API — MapKit
Directions handles source and destination only, and the URL scheme has no
waypoints parameter. A single-destination fallback would navigate you to where
you already are, which is worse than nothing. The universal Google link opens in
Safari when the app isn't installed.

**Filter on highway share, not road class.** In New Jersey, OpenRouteService
classifies Route 9 as a state road alongside genuinely pleasant county roads, so
`waytype` is a poor signal. The `waycategory` motorway bit is the one that
matters.

## Building

Requires Xcode 16+ and iOS 17+.

```
cp Config.example.swift Aimless/Config.swift
# paste an OpenRouteService key into Aimless/Config.swift
open Aimless.xcodeproj
```

`Aimless/Config.swift` is gitignored. The template lives at the repo root rather
than inside `Aimless/` so Xcode's synchronized folders don't compile it as a
duplicate.

The app icon is generated, not drawn — `swift tools/makeicon.swift out.png`
reproduces it.

## Status

v1 is built and running. Known limitations are documented honestly in
[SPEC.md](SPEC.md) and [HANDOFF.md](HANDOFF.md), which are the real design
record; this README is the summary.

The largest open item: the reroute step uses OpenRouteService as a proxy for
Google's routing. It's a good proxy, not ground truth.

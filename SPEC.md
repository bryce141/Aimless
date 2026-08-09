# Loop, MVP spec

## What it is

An iOS app that generates a circular driving route starting and ending at your
current location. For aimless drives with a friend. You pick roughly how long you
want to be out, it hands you a loop, you drive it while talking and listening to
music.

The problem it solves: you drive somewhere with no destination, get too far out,
and the return leg is dead time retracing the same roads.

## MVP scope

Generate loops, show them on a map, hand off to Google Maps for navigation.

That's it. The goal of v1 is to make it possible to actually drive one of these
and find out whether the experience is good. Everything else waits.

### Explicitly out of scope for v1

- Turn-by-turn navigation of our own
- CarPlay (requires a special Apple entitlement, approval process, will sink the project)
- Accounts, sync, saved loops, history
- Music integration
- Sharing, social, anything multiplayer
- Backend of any kind

## Validated findings from prototyping

These came out of a Python prototype hitting the live API. Don't re-derive them.

Revised 2026-08-07 after a second round of live checks at the Marlboro origin
(40.4001, -74.3457): 80 requests across request sizes from 4km to 63km, using
this spec's parameters (`points: 8`, no `avoid_features`). That round corrected
the overshoot rule, the speed assumption, and the failure rate, and killed the
30 minute picker option. Corrections are marked below.

**Provider: OpenRouteService.** GraphHopper's hosted `round_trip` requires
flexible mode, which is paid-only. ORS does round trips on the free tier
(2,000 requests/day).

**Endpoint:** `POST https://api.openrouteservice.org/v2/directions/driving-car/geojson`

Headers: `Authorization: <key>`, `Content-Type: application/json`

Body:
```json
{
  "coordinates": [[lon, lat]],
  "options": {
    "round_trip": { "length": 45000, "points": 8, "seed": 1 }
  },
  "extra_info": ["waytype", "waycategory"],
  "instructions": false
}
```

Note coordinates are `[lon, lat]`, not lat/lon.

**`points: 8` is the key parameter.** At `points: 3` the generator produces spiky
polygons with hairpins and backtracking, plus more highway. At `points: 8` it
produces clean closed rings with little repetition. Don't lower it.

**Distance overshoots, and the overshoot is not a constant.** An earlier draft of
this spec said "scale the request down 30%." That is wrong. Measured overshoot
scales inversely with request size:

| request | actual (median) | overshoot |
|---------|-----------------|-----------|
| 4 km    | 13 km           | 3.2x      |
| 16 km   | 31 km           | 1.9x      |
| 31 km   | 51 km           | 1.7x      |
| 47 km   | 64 km           | 1.5x      |
| 63 km   | 84 km           | 1.4x      |

**Speed is not 45 km/h either.** An earlier draft assumed a flat 45 km/h for back
roads. Measured: 25-27 km/h on small loops, ~44 km/h on large ones. Small loops
are residential streets, so they are slower. Also not a constant.

**Therefore: do not compute the request size from duration.** Two wrong constants
multiplied together is how "30 minutes" became a 62 minute drive. Use the
calibrated table in the UI section instead.

**Per-seed duration variance is enormous.** The same 13km request returned drives
ranging from 40 to 90 minutes. No formula survives that spread, so no amount of
recalibration will let you predict a loop's duration from the request. Don't try.
Use the `duration` ORS returns in the response and filter on it. See LoopScorer.

**`avoid_features: ["highways"]` is silently ignored inside `round_trip`.** Don't
bother sending it. Filter for highway content in the response instead.

**Expect failures, but fewer than an earlier draft claimed.** That draft said
roughly 1 in 3 seeds fails. Measured at the Marlboro origin, 48 seeds at
`points: 8`: 45 succeeded (94%). Failures were 0/12 at 16km, 31km, and 47km
requests, and 3/12 at 63km. Failures cluster at the top of the range.

**Not all failures are 404.** Two of the three were
`HTTP 500 "Could not find a valid point after 3 tries"`. One was the expected
`HTTP 404 "Route could not be found"`. Swallow both, and any 5xx.

**Requests are fast.** 0.5 to 1.0 seconds each. Twelve concurrent seeds is 1 to 2
seconds of wall clock, not twenty. A second retry round is cheap, so don't
contort the design to avoid one.

The seed budget is therefore not driven by HTTP failures. It's driven by duration
spread, see LoopScorer.

**Seeds are deterministic, and this matters.** A seed is not a dice roll. The
same seed at the same origin and request size returns the byte-identical result
every time, failures included. Seed 3 failed at 75km, 85km and 100km; seed 6
failed at 63km in two separate runs hours apart.

Consequence: a retry round must ask for *fresh* seed numbers. Re-rolling 1...12
re-fetches the identical twelve results, including the identical failures, for
the identical cost.

**Rate limit: 40 requests/minute on the free tier.** This bites, because one
generate costs ~18 requests. Two back-to-back are fine; a third inside the same
minute gets throttled. A throttled round is indistinguishable from "no loop
matched" unless you look for HTTP 429, so `RouteService` reports rate limiting
separately and the UI says so rather than blaming the search.

Discovered the hard way: an early test ran all three picker options back to back
and concluded the 2 hour option was broken. It wasn't. Requests 37 onward were
simply being refused.

**ORS caps round trips at 100km.** At back-road speeds that's roughly a two hour
ceiling. Longer drives are not reachable on the hosted API, see Known ceilings.

**Google Maps handoff preserves the route shape. Tested and confirmed.** A 70km
loop downsampled to 8 waypoints, opened in Google Maps, came back as the same
ring. Google stayed on county roads through Marlboro and Englishtown and did not
grab Route 9, 18, or 33 despite all three being faster and adjacent. The
downsample-and-hand-off approach is viable at MVP distances.

One cosmetic artifact: Google reverse-geocodes waypoints into street addresses,
so the user sees a stop list of random houses like "52 Sandpiper Drive". Harmless
but looks strange. No fix in v1.

**Response parsing:** `features[0].geometry` is a GeoJSON LineString, usable
directly as a polyline. `features[0].properties.summary` has `distance` (meters)
and `duration` (seconds). `features[0].properties.extras.waytype.summary` and
`.waycategory.summary` are arrays of `{value, distance, amount}` giving meters
per road class.

**Road class codes:**
- waytype: 1 = state road, 2 = road, 3 = street (2 and 3 are what we want, 1 is mixed)
- waycategory: bit 1 = highway (this is the one to filter on)

In New Jersey, "state road" is not a reliable signal, it lumps Route 9 in with
pleasant county roads. Highway percentage is the signal that matters.

## Architecture

Single SwiftUI app, no backend, MVVM.

```
LoopApp/
  Models/
    Loop.swift            // coordinates, distance, duration, road stats, seed
    RoadStats.swift       // highwayPct, backroadPct, stateRoadPct
  Services/
    RouteService.swift    // ORS client, async/await, URLSession
    LoopScorer.swift      // filter + rank candidates
    Handoff.swift         // build Google Maps URL, open it
  Views/
    GenerateView.swift    // duration picker, direction picker, generate button
    LoopMapView.swift     // MapKit, polyline, stats overlay, drive button
  ViewModels/
    LoopViewModel.swift
```

### RouteService

- `func generateLoops(from: CLLocationCoordinate2D, requestMeters: Int, seeds: Int) async throws -> [Loop]`
- Fires N seed requests concurrently with a TaskGroup
- Swallows individual failures and returns whatever succeeded. Swallow 404 *and*
  5xx, not just 404. Only throw if every seed failed.
- Takes a request size in meters, not a target. The duration-to-request-size
  mapping lives in the UI layer, see the table there. This service does not
  know about the duration picker.
- API key from a gitignored config file for now, not committed

### LoopScorer

**Two phases.** A round trip is a candidate, not a result. What the user drives
is Google's route through the 8 handoff waypoints, which runs 72-82% of the round
trip's duration. So:

1. Ask for 12 round-trip candidates.
2. Pre-filter cheaply on what we already have — reject highway share above 20%,
   and anything whose estimated driven duration is more than 45% off target.
   Keep at most 6, best first.
3. Verify those by downsampling to 8 waypoints and asking ORS to route through
   them. That rerouted path is the `Loop`: its polyline goes on the map, its
   duration is what we print, its waypoints are what we hand to Google.
4. Filter and rank the verified loops.

The pre-filter exists because verification costs one request each. Its thresholds
are deliberately looser than the real ones, since a candidate's round-trip
numbers only approximate its driven ones — driven highway share tracks the
round-trip figure closely but usually runs a little higher.

Cost: ~18 requests per generate, about a second. Watch the 40/minute rate limit.

**Filter on duration, not distance.** The user picks minutes, so minutes is what
we judge against. Neither request size nor distance predicts drive time (see the
variance finding above), but the verified route's own duration is exact.

Filter and rank the verified loops. Reject:
- highway share above 15%
- returned duration outside +/-25% of the picked duration
- if fewer than 3 survive, retry with new seeds. A retry round costs about a
  second, so this is cheap. Widen the duration band to +/-40% on the retry
  rather than firing the same filter at new seeds.

Rank surviving loops by highway share ascending, then by how close the returned
duration is to the picked duration.

Show the top 3.

**Seed count: 12.** Not because of HTTP failures, which are rare, but because
duration spread is wide. Measured in-band rates at +/-25% were 8/12, 6/12, 9/12
and 8/9 across the four sizes, roughly 60%. Twelve seeds clears 3 survivors
comfortably and costs 1 to 2 seconds.

The 15% highway threshold is well calibrated, leave it. It rejects exactly the
blowout seeds, which are the same ones that overshoot distance badly.

### Handoff to Google Maps

We are not writing navigation. Open Google Maps with the loop as a waypoint route.

```
comgooglemaps://?saddr=<lat>,<lon>&daddr=<lat>,<lon>+to:<lat>,<lon>+to:...
```

Or the universal link form:
```
https://www.google.com/maps/dir/?api=1&origin=LAT,LON&destination=LAT,LON&waypoints=LAT,LON|LAT,LON|...
```

**Downsampling is required.** The ORS geometry has thousands of points. Google's
URL API accepts around 9 waypoints. Pick waypoints by walking the polyline and
taking a point every `totalDistance / 8` meters. Origin and destination are both
the start point.

Google re-routes between those waypoints, so the driven route differs slightly
from what we display. Tested at 70km with 8 waypoints and the shape held. Use the
universal link form, it works whether or not the Google Maps app is installed.

**There is no Apple Maps fallback.** The Maps app supports multi-stop routes in
its own UI, but Apple exposes no API for it. MapKit Directions handles source and
destination only, the URL scheme has no waypoints parameter, and
`MKMapItem.openMaps(with:)` does not treat an array as a sequential route. A
single-destination fallback would navigate the user to where they already are,
which is worse than nothing.

Google Maps is therefore a hard dependency. If the app isn't installed, the
universal link opens in Safari, which still works. Don't build a fake fallback.

### UI

Two screens.

**Generate:** current location shown on a small map, a duration picker
(60 / 90 / 120 minutes), a Generate button.

No direction picker in v1, cut per HANDOFF.md. See Direction bias.

**The picker floor is 60 minutes, not 30.** See Known floors below.

**Map duration to request size with this table, don't compute it.** Sizes target
the **driven** duration, so they're larger than the drive itself implies:

| picked | request | measured result |
|--------|---------|-----------------|
| 60 min | 33 km   | 58 min driven |
| 90 min | 70 km   | 93 min driven |
| 120 min| 85 km   | 124 min driven |

All three land within 4% of target. Do not raise past 100km — ORS rejects it
with HTTP 400. The table only has to land in the right ballpark, because the
duration filter in LoopScorer does the real work; table error costs candidates,
not accuracy.

**Results:** the three loops as a swipeable card stack or segmented picker, each
drawing its polyline on a MapKit view. Per loop show actual distance, estimated
time, and highway percentage. A Drive This button triggers handoff.

Keep it plain. Map, one number, one button.

## Direction bias

Prototyping showed generated loops cluster toward developed suburban corridors
rather than farmland. ORS has a `bearings` option that may help force initial
direction. If it doesn't work inside `round_trip`, the fallback is to offset the
request origin a few km in the desired direction, generate from there, and accept
that the loop won't start exactly at the user.

Try `bearings` first. Timebox it.

## Definition of done for v1

Bryce can stand in his driveway, open the app, tap 60 minutes, get three loops,
tap one, and have Google Maps start navigating it.

Then he drives it with a friend and decides whether any of this is worth continuing.

## Testing without leaving the house

Nothing in v1 requires motion. Generate, display, hand off.

- **Static location:** Simulator → Features → Location → Custom Location,
  40.4001 / -74.3457.
- **Handoff fidelity:** Google Maps isn't installed on the simulator. Build the
  URL, paste it in a desktop browser. Web Google Maps renders the same route the
  app would.
- **Simulated movement** (only needed for v2 follow-the-line): add a GPX to the
  project, then Product → Scheme → Edit Scheme → Run → Options → Default Location.
  `geojson2gpx.py` from prototyping converts loop output to GPX with optional
  timestamps for pacing.

## Known floors

**A 30 minute option is not worth shipping.** This was tested against the live
API, it isn't a guess.

Short requests don't fail, contrary to what we feared. 8/8 seeds succeeded at
every size down to a 4km request, with 0% highway throughout. Hairpins were not
the problem either.

The problem is that a 30 minute drive from a fixed start is a lap around the
block. To actually land at 30 minutes you need roughly a 4km request, and those
loops spend **87% of their length within 2km of the start**, with a maximum
radius of 2.3km and 11% of the drive retracing road already covered. Compare a
16km request: 30% within 2km, 5.7km radius, 2% retrace.

This isn't a bug to fix. It's what a 30 minute round trip from a fixed origin
geometrically is. Floor the picker at 60 minutes.

45 minutes is defensible if a short option turns out to matter, it's the last
size before the neighborhood-lap effect takes over. Don't add it before the
first real drive.

## Known ceilings

These are structural, not bugs. They bound what v1 can be.

**Two hour ceiling on drive length, though this may be conservative.** ORS caps
the requested round trip `length` at 100km. The original two hour figure came
from applying the old 45 km/h assumption to that 100km cap, and both inputs were
wrong: the cap applies to the *requested* length, and actual distance overshoots
it by ~1.4x at that scale. A 63km request already yields ~84km and 113 minutes,
so a 100km request would plausibly return ~130km and close to three hours.

Untested. Don't build against it. And note the binding constraint at that range
is handoff fidelity, not ORS, see below. Keep the picker at 120 minutes max for
v1.

**Handoff fidelity degrades with distance.** 8 waypoints over 60km is one every
7km, and Google rarely finds a highway shortcut inside 7km of back roads. Over
135km it's one every 17km, and in New Jersey there is almost always a faster
highway connecting two points that far apart. So the approach that works today
gets worse exactly where longer drives would need it most.

**The handoff does not grab highways at v1 distances, but it does cut corners.**
Tested 2026-08-07 by routing point-to-point through the 8 downsampled waypoints
and comparing against the original round trip:

| picked | loop shown | via 8 waypoints | highway |
|--------|-----------|-----------------|---------|
| 60 min | 61 min, 17.2 mi | 50 min, 15.6 mi | 0% -> 0% |
| 90 min | 88 min, 37.3 mi | 64 min, 32.3 mi | 0% -> 0% |
| 120 min| 127 min, 53.0 mi | 96 min, 47.3 mi | 0% -> 0% |

Good news: highway share stays at 0% even at 120 minutes, so the shape holds and
the 120 minute option is safe. That was the open worry and it's resolved.

**The driven route runs roughly 72-82% of the round trip's duration.** Routing
between waypoints takes straighter, faster paths than the wandering original.
This is not fixable by adding waypoints — measured at 8/10/12/16/24 waypoints on
the same loop, recovery is slow and plateaus (69% -> 82%), and Google's URL API
caps around 9 waypoints anyway.

**Resolved by making the rerouted path the canonical route.** Rather than
correcting the number, the app stopped producing the wrong one. A round trip is
now only a candidate; we downsample it, ask ORS to route through those waypoints,
and the result of *that* is what we draw, time and hand off. See the two-phase
LoopScorer flow.

Measured after the change: all three picker options land within 4% of target.

Remaining caveat: the reroute is ORS, not Google, so it's a very good proxy
rather than ground truth. Open a handoff URL and read Google's own ETA, or note
it on the first real drive.

Both ceilings point the same direction for v2: self-hosted GraphHopper to remove
the distance cap, and something other than Google handoff for navigation. The
likely answer is a follow-the-line view, drawing the polyline on MapKit, showing
the user's position along it, and reading out the turn instructions ORS already
returns. Rerouting is unnecessary on a fixed loop, the only recovery needed is
"get back on the line", which is what makes this weeks rather than months.

Do not build any of that in v1.

## Other risks

- ~~ORS free tier is not licensed for production use.~~ **Wrong. Retracted
  2026-08-08 after reading HeiGIT's actual Terms of Service.** Nothing in them
  restricts commercial or production use. Prohibited Conduct covers unlawful
  purposes, abusive content, IP infringement, overburdening the service and
  transmitting personal data — not who you are or whether you ship. This was
  assumed during prototyping and never checked, and it shaped planning for a
  while. Self-hosting is now an optimisation, not a compliance requirement.
- ~~API key ships in the app binary.~~ Fixed. Routing goes through a Cloudflare
  Worker; the key is a Worker secret and is absent from the shipping binary.
- **Attribution is required and the exact string is specified.** HeiGIT asks
  for `© openrouteservice by HeiGIT | Data from OpenStreetMap`, displayed in
  the map image or elsewhere. The app currently says something close but not
  identical — see HANDOFF.md, fix in 1.1.
- **Results are licensed CC-BY-SA 4.0.** "Results obtained from
  openrouteservice in any context are licensed under CC-BY-SA 4.0." Displaying
  them with attribution is fine; the share-alike clause would bite if loop data
  were ever redistributed as a dataset. Worth remembering before adding any
  export or share feature.
- **Bursty concurrency is explicitly called out as abuse.** The usage limits
  section lists "sending requests too fast, i.e. too many requests per second"
  alongside daily overuse, with temporary blocking and account removal as
  consequences. The generator fires 12 concurrent round-trip requests and then
  up to 6 verifications — a burst, by design, roughly every generate. It has
  not caused trouble at one user. It is the design decision most likely to look
  like abuse at any scale, and it is worth throttling before it matters.
- Generated loops cluster toward developed suburban corridors rather than
  farmland. See Direction bias.

# Handoff — v1 built, not yet driven

Read `SPEC.md` first. That's the source of truth, and it's current — every
measurement and correction below is already folded into it. This file records
state, decisions, and what's open.

Last updated 2026-08-07.

## Where things stand

v1 is **built, running, and committed**. It has never been driven.

- Builds clean, runs in the simulator, generates 3 loops at all three durations.
- Verified against the live API using the real app sources, not a reimplementation.
- All three picker options land within 4% of the requested duration.
- Three commits on `main`. **No git remote** — nothing has been pushed anywhere.

The definition of done in `SPEC.md` is met in the simulator. What remains is
physical: put it on a phone and drive one.

## Environment

- Xcode 26.6 at `/Applications/Xcode.app`, iOS 26.5 SDK.
- `xcode-select` already points at Xcode.
- Bryce has a **paid Apple Developer account**.
- Disk filled up completely during the first build session. Xcode DerivedData is
  the usual culprit (`rm -rf ~/Library/Developer/Xcode/DerivedData`, safe — it's
  build cache). Worth watching; builds and device installs need headroom.
- Simulator note: `simctl privacy grant location` does *not* suppress the
  CoreLocation prompt on this runtime. To auto-authorize for scripted
  screenshots, write the bundle ID into
  `<device>/data/Library/Caches/locationd/clients.plist` with `Authorized=true`
  while the device is shut down. Only matters for automation.

## Project

```
Developer/Aimless/
  Aimless.xcodeproj
  Aimless/
    AimlessApp.swift
    Config.swift             <- gitignored, holds the ORS key
    Models/      Loop, RoundTrip, RoadStats, DurationOption
    Services/    RouteService, LoopScorer, Handoff, LocationProvider
    ViewModels/  LoopViewModel
    Views/       GenerateView, LoopMapView
  Config.example.swift       <- keyless template, at root so it isn't compiled
  SPEC.md, HANDOFF.md
```

Hand-written `.xcodeproj` using Xcode 16+ synchronized folders, so new Swift
files are picked up without editing the project file. iOS 17+, bundle ID
`com.brycepercoco.aimless`.

## Decisions

- **Deployment target: iOS 17+.** SwiftUI-native `Map` with `MapPolyline` and
  `MapCameraPosition`. No `UIViewRepresentable` / `MKMapView` bridging.
- **No direction picker in v1.** The spec listed it as optional and flagged that
  ORS `bearings` may be ignored inside `round_trip`. Cut it. Revisit after the
  first real drive, when there's evidence about whether loops actually are too
  suburban.
- **Distance shown in miles.** The spec used km throughout; Bryce is in New Jersey.
- **Name: Aimless**, bundle ID `com.brycepercoco.aimless`. Settled after two
  rejected candidates. "Loop" collides with `Loop.swift`, the model type.
  "LongWay" was built under briefly and dropped — a generic idiom that collides
  in App Store search with an existing driving app, "The Long Way". "Loopback"
  was proposed and withdrawn on finding three existing apps by that name,
  including Rogue Amoeba's. Aimless is the word the spec itself uses.

  The bundle ID was changed while that was still free to do. It is permanent
  once an app ships to the App Store.

## Withdrawn: the proposed LoopScorer change

The concern was that a serial retry round doubles wall-clock wait, 20+ seconds
staring at a spinner. Measured: ORS responds in 0.5-1.0s, so 12 concurrent seeds
is 1-2 seconds and a retry round is about a second. There is no spinner problem.
The spec's original "widen and retry" stands.

## What the live API checks changed

Three rounds of live measurement, roughly 400 requests. All of it is in `SPEC.md`
in full; this is the index.

1. **The duration math was broken.** 45 km/h and a flat 30% overshoot correction
   are both wrong, and they compound — "30 minutes" produced a 62 minute drive.
   Replaced with a measured request-size table plus filtering on the duration
   ORS actually returns.
2. **The 30 minute option is gone.** Reaching it needs a ~4km request, and those
   loops spend 87% of their length within 2km of the start. A lap around the
   block.
3. **Failure rate is ~6-10%, not 33%**, and some failures are HTTP 500, not 404.
4. **Seeds are deterministic.** Same seed + origin + size returns the identical
   result forever, failures included. Retries must use fresh seed numbers.
5. **The displayed route wasn't the driven route.** Google reroutes between the
   8 handoff waypoints, and that path runs 72-82% of the round trip. Fixed by
   making the rerouted path canonical — see below.
6. **Rate limit: 40 requests/minute.** One generate costs ~18. This masqueraded
   as "the 2 hour option is broken" for one very confusing test run.

## How generation works now

A round trip is a *candidate*, not a result.

1. Ask ORS for 12 round-trip candidates (`RoundTrip`).
2. Pre-filter cheaply on data already in hand; keep at most 6.
3. Reroute each through its 8 handoff waypoints — the same thing Google will do.
4. That rerouted path is the `Loop`: its polyline is drawn, its duration printed,
   its waypoints handed to Google.
5. Filter and rank on the verified duration and highway share.

Roughly 18 requests and about a second per generate.

Keeping `RoundTrip` and `Loop` as separate types is deliberate. Conflating them
is what let the app display a duration nobody would drive.

## Pre-drive hardening

Four failure modes that a simulator on wifi never reproduces, all fixed before
the first drive. None were caught by the live API testing, because all of them
live above the API client.

1. **The app could hang on "Finding you…" permanently.** `requestLocation()` is
   one-shot and `didFailWithError` did nothing, so a failed fix — parking
   garage, cold start indoors — left Generate disabled forever under a message
   claiming we were still looking. Only escape was force-quitting. Now surfaced
   as a retryable state with a **Try Again** button.
2. **Precise Location off produced a silently wrong loop.** Nothing checked
   `accuracyAuthorization`. Under reduced accuracy CoreLocation still returns a
   coordinate, fuzzed by kilometers, so the app would build and hand Google a
   loop starting somewhere the driver isn't. That's a wrong answer, not an
   error, so it now blocks generation and links to Settings.
3. **No signal blamed the wrong thing.** Offline, all 12 seeds throw `URLError`
   and the user got "couldn't build any loops from here" — which sends them
   driving somewhere else when the fix is a bar of signal. Now a distinct
   `.offline` case, for the same reason `.rateLimited` is one.
4. **The fix never refreshed.** Taken once on appear. Open the app in the
   driveway, drive ten miles, hit Generate, get a loop around the driveway. Now
   re-requested on return to the foreground.

`LocationProvider` gained a `Status` enum in the process — `denied`,
`reducedAccuracy`, `failed` and `locating` need different words on screen and
only one of them is fixed by waiting, which the old `isDenied` bool couldn't say.

## Open

- **Never been driven.** Everything past this point is guesswork without it.
- **Request timeout is 30s, unmeasured.** Generous against measured 0.5-1.0s
  responses, so on flaky cell it means a 30-second spinner with no cancel. Left
  alone deliberately — lowering it without measuring risks failing slow-but-fine
  requests, and this app's whole environment is marginal signal. Revisit with
  data from the drive.
- **The 60 and 90 minute request sizes are derived, not directly measured.**
  Only 120 was measured against true driven duration. The duration filter
  absorbs table error, so this costs candidates rather than accuracy.
- **Route 9.** Loops run alongside it and the app reports 0% highway, because
  ORS classifies it as a state road rather than a motorway. Bryce has seen this
  and is fine with it — it isn't the Parkway or Turnpike. Not acting on it.
- **The reroute proxy is ORS, not Google.** A good proxy, not ground truth.
  Cheapest check: open a handoff URL and compare Google's own ETA.
- **`loopgen_ors.py` is stale** — sends `avoid_features` and defaults to
  `points: 5`, both superseded. Kept for reference only.

## Getting it on a phone

The `.xcodeproj` lives on the Mac; the phone connects by cable and Xcode pushes
the build across.

1. Open `Aimless.xcodeproj` in Xcode.
2. Plug in the iPhone, tap **Trust** if prompted.
3. Change the device dropdown in the toolbar from a simulator to the iPhone.
4. Select the **Aimless** target → **Signing & Capabilities** → tick
   *Automatically manage signing* → choose the Team.
5. Cmd+R.

If the phone reports *Untrusted Developer*: Settings → General → VPN & Device
Management. Usually unnecessary with a paid account.

## Shipping

**TestFlight, not the App Store.** Two blockers make public release a v2 topic:

- **ORS quota is per-key, not per-user.** 2,000 requests/day and 40/minute are
  shared across every install. At ~18 requests per generate that's ~111 generates
  per day *combined*, and two simultaneous users throttle each other. Roughly
  5 active users breaks it.
- **The API key ships in the binary** and cannot be hidden. Obfuscation doesn't
  work — the app must send the real key over the network, so anyone can proxy
  their own traffic and read it.

Both have the same fix: **self-host the routing.** Self-hosted ORS or GraphHopper
supports `round_trip` for free (the paid-only restriction is on GraphHopper's
*hosted* service). The client change is one URL constant; the work is ops — a VPS
with ~8GB RAM, an OSM extract, a Docker container.

Until then TestFlight covers it: up to 100 internal testers, no App Review for
internal builds, 90-day builds.

## Prototype files kept for reference

- `loopgen_ors.py` — ORS prototype, reads `ORS_KEY` env var. Stale, see above.
- `loopgen.py` — earlier GraphHopper attempt, superseded.
- `geojson2gpx.py` — converts loop output to GPX for simulated movement (v2).
- `*.geojson`, `gpx/` — prototype output. `p8.geojson` is only the start marker;
  the route that went with it is `p8_route.geojson`, renamed out of
  `p8.geojsonclear` — a `> p8.geojson` and a `clear` on one line.

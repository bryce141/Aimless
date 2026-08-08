# Handoff — v1 submitted to the App Store, still never driven

Read `SPEC.md` first for the routing design. `store/listing.md` holds everything
App Store Connect asks for. This file records state, decisions, and what's open.

Last updated 2026-08-08.

## Where things stand

v1 is **submitted to the App Store and waiting for review** as of 2026-08-08.
Apple quotes up to 48 hours. It has still never been driven on a real road.

- Public repo: **https://github.com/bryce141/Aimless**
- Store listing: **Aimless Drives** (`Aimless` was taken). Apple ID 6799342576.
  The app itself reads **Aimless** on the home screen — `CFBundleDisplayName` is
  pinned so the two can't drift.
- Submitted build: **1.0 (3)**. Builds 1 and 2 are superseded and still show
  "Missing Compliance" in TestFlight; 3 does not, because it declares
  `ITSAppUsesNonExemptEncryption` in the bundle instead of answering the web
  form per upload.
- Routing goes through a **Cloudflare Worker**, not ORS directly. The ORS key is
  a Worker secret and is verifiably absent from the shipping binary.
- Not available in the EU, deliberately — see Decisions.

The definition of done in `SPEC.md` is met in the simulator. What remains is
still physical: put it on a phone and drive one.

## If review comes back

**Approved:** nothing to do; it releases automatically unless a manual release
was selected.

**Rejected:** the likely grounds, in order of probability —

1. *Guideline 2.1, app doesn't function.* The most probable failure is a
   reviewer tapping Generate three times inside a minute and hitting the ORS
   40/minute limit. The review notes in `store/listing.md` warn about this
   explicitly; if it happens anyway, reply in Resolution Center pointing at
   them rather than shipping a new build.
2. *Location permission.* The app refuses to generate under reduced accuracy by
   design. A reviewer with Precise Location off sees a blocked button. Also
   covered in the notes.
3. *A location surrounded by water returns no loops.* Genuinely no loops exist;
   not a bug.

Any code fix needs a build number bump — App Store Connect rejects a re-upload
reusing one it has seen. `CURRENT_PROJECT_VERSION` is at 3.

## Store assets

**Screenshots must match the slot App Store Connect shows**, which was 6.5"
(1284x2778) on this record despite Apple's docs leading with 6.9". Both sets
are in `store/screenshots/`. No 6.5"-class simulator exists by default; the
create command is in `store/listing.md`, along with two traps in regenerating
them.

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
    Config.swift             <- gitignored; holds the Worker client token,
                                NOT the ORS key any more
    Models/      Loop, RoundTrip, RoadStats, DurationOption
    Services/    RouteService, LoopScorer, Handoff, LocationProvider
    ViewModels/  LoopViewModel
    Views/       GenerateView, LoopMapView, Theme
  worker/                    <- Cloudflare Worker: ORS proxy
  store/                     <- listing.md, screenshots/{6.5-inch,6.9-inch}
  tools/makeicon.swift       <- regenerates the app icon
  Config.example.swift       <- tokenless template, at root so it isn't compiled
  README.md, SPEC.md, HANDOFF.md, PRIVACY.md
```

Hand-written `.xcodeproj` using Xcode 16+ synchronized folders, so new Swift
files are picked up without editing the project file. iOS 17+, bundle ID
`com.brycepercoco.aimless`.

## Decisions

- **Not available in the EU.** The Digital Services Act requires a trader
  declaration to distribute there, and declaring as an individual publishes a
  legal name, home address, phone and email on the public product page.
  Removing the EU costs distribution in markets with no users; declaring would
  cost a permanently indexed home address. Reversible if it ever matters.

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

## Routing proxy

The app talks to `aimless-routing.bdrp777.workers.dev`, not to ORS. See
`worker/README.md`.

Two reasons, and the second is the one that mattered. The ORS key stops shipping
in a binary anyone can unpack — verified by grepping the exported binary, which
contains the Worker URL and no key. And **the routing backend now has an address
the app owns**: a shipped App Store build has its endpoint frozen into a
reviewed artifact, so pointing at ORS directly would have made any future move
to self-hosted routing a new binary, another review, and old installs stranded.

The client token in `Config.swift` is **not** a security boundary and the code
says so. It ships in the binary like any string. It exists because the endpoint
is public in a public repo, and it narrows a scraped value to one disposable
endpoint rather than an ORS account key.

**Status codes pass through the proxy untouched, and this is load-bearing.** The
client reads 429 as rate limiting worth surfacing and 404/5xx as one dead seed
to swallow. Flattening them would recreate exactly the ambiguity `RouteService`
was built to remove.

## Still open on shipping

- **ORS quota is shared across every install.** 2,000/day and 40/minute. One
  generate is ~18 requests, or ~36 when the retry round fires, so roughly 55-110
  generates per day *combined*. Fine at current usage — which is one person —
  and broken at maybe 5 active users.
- **`SPEC.md` says the ORS free tier is not licensed for production use.** Never
  chased down against ORS's current terms. If accurate, a public App Store
  listing on the free tier is not legitimate regardless of user count. **This is
  the largest unresolved risk in the project.**

Both have the same fix: **self-host the routing.** Self-hosted ORS or GraphHopper
supports `round_trip` for free (the paid-only restriction is on GraphHopper's
*hosted* service). Half a day to a full day of ops — a VPS with ~8GB RAM, an OSM
extract, a Docker container, TLS via Caddy — and thanks to the Worker the client
change is a server-side URL swap, not an app update.

## Prototype files kept for reference

- `loopgen_ors.py` — ORS prototype, reads `ORS_KEY` env var. Stale, see above.
- `loopgen.py` — earlier GraphHopper attempt, superseded.
- `geojson2gpx.py` — converts loop output to GPX for simulated movement (v2).
- `*.geojson`, `gpx/` — prototype output. `p8.geojson` is only the start marker;
  the route that went with it is `p8_route.geojson`, renamed out of
  `p8.geojsonclear` — a `> p8.geojson` and a `clear` on one line.

# Handoff — v1 with App Review, runs on a phone, still never driven

Read `SPEC.md` first for the routing design. `store/listing.md` holds everything
App Store Connect asks for. This file records state, decisions, and what's open.

Last updated 2026-08-18.

## Where this stands

**1.0 (3) is back with App Review as of 2026-08-14.** No code change was
involved and none is pending.

Apple rejected under **Guideline 2.1, Information Needed** — not a bug, not a
crash, nothing wrong with the app. The reviewer wanted documentation the
submission never carried, in seven numbered items, plus a screen recording made
on a physical device. Answers to items 2-7 live in `store/review-notes.md`, and
are now in both the App Review Information Notes field and the reply itself.

That rejection forced the device test that was deliberately skipped before
submitting, and the app passed it: location permission, generation, and the
Google Maps handoff all work on an iPhone Air running iOS 26.5.2. "Drive This"
opens Google Maps in live turn-by-turn navigation on the generated route.

One thing worth carrying forward: **iOS does not capture system permission
dialogs in screen recordings**, so the location alert cannot be filmed that way.
It is visible indirectly — the app sits on "Finding you..." while the alert is
up, and the status-bar location arrow appears the moment access is granted. The
reply points the reviewer at both. Two recordings were thrown away before
working that out.

## Rejected again 2026-08-19, and what fixed it

Second rejection of 1.0 (3), on two counts. Reviewed on an **iPad Air 11-inch
(M3), iPadOS 26.6** — the app is `TARGETED_DEVICE_FAMILY = 1`, so it ran in
iPhone compatibility mode. **The iPad was incidental to both problems.**

**Guideline 2.1(a): "an error message after tap on generate button."** This was
the HeiGIT rate limit, reproduced exactly: 40 requests/minute shared across
every user, ~18 per generate, so the fourth generate inside a minute comes back
throttled and the app surfaces an error. Measured from Apple Park coordinates —
generates 1-3 all 200, generate 4 gave 4 ok and 8 throttled, generate 5 gave
twelve throttled.

Ruled out on the way: routing from Cupertino works (12/12 candidates, 6/6
verified), the ±25% duration filter accepts those, and Generate is correctly
gated on `location.isUsable`, so the reviewer had a fix.

**Fixed server-side, no new build, by caching in the Worker.** The app requests
seeds 1-12 on every first round and ORS is deterministic, so repeated generates
in one spot are byte-identical requests. Four generates went from 48 upstream
requests with 8 throttled to 23 with none. See `worker/README.md`.

**Note the Worker had never actually been deployed** — the live version predated
the self-hosted routing, the `X-Aimless-Served-By` header and the rate-limit
header forwarding, all of which were sitting in source. Deployed now.

**Guideline 1.5: Support URL.** The URL loads and always did — the repo has been
public since 8 August and returns 200. The real fault is that it is a developer
README with **no contact address anywhere on it**, so a user needing help has
nowhere to go. Now a proper support page at
**https://bryce141.github.io/Aimless/**, served from `docs/` via GitHub Pages,
with Brycepercoco@gmail.com on it. Update the Support URL in App Store Connect
to point there.

### A fix that was proposed and dropped

Cutting `seedsPerRound` from 12 looked obvious and the measurements killed it.
In-band survival is **62% at 60 minutes, 38% at 90, 29% at 2 hours** — so six
seeds leaves only two survivors on both longer options, below `desiredCount`,
which fires the retry round and costs *another* twelve requests. Even eight
seeds lands exactly on three with no margin and saves just four requests,
because the six verification reroutes are fixed. **12 is right; leave it.**

## What happens when Apple replies

1. **Approved** — next build is 1.0.1 with a fresh build number, carrying the
   attribution fix.
2. **Rejected again** — fix what they cite, and the attribution fix rides along
   in 1.0 with build 4.

Version numbers cannot be chosen in advance: Apple requires the build's version
string to match the App Store Connect record, so the outcome decides it.

Pushing a new build later is safe. A live app stays live while a new version is
in review; users keep downloading the current one, and the new version only
replaces it on approval. There is no window where the app disappears.

## Who this is for

**Bryce is an IT engineer, not a software engineer.** Infrastructure vocabulary
lands — reverse proxy, VM, vendor quota, firewall, connector. Software and cloud
platform vocabulary does not, and assuming it has cost two rounds of
back-and-forth already.

Three rules that came out of it:

- **Name the product and say what it is**, the first time it appears in a reply.
  "The Cloudflare Worker" means nothing on its own; "the Cloudflare Worker, a
  reverse proxy Cloudflare hosts for us" does.
- **Never let a plan step secretly mean "do nothing".** "Stay on the free plan"
  was read as a product to go acquire, because it was written in a list of
  actions. If the answer is no action, write *no action needed*.
- **Keep the units straight.** A per-minute limit and a per-day limit in the same
  table, without labels, is unreadable. That one confused an entire exchange.

## The two ceilings, in plain terms

Worth keeping because it gets re-derived every time. **There are two separate
limits, in different units, and they have nothing to do with each other.**

| | What it is | Limit | Fixed by |
|---|---|---|---|
| Cloudflare Worker | Our reverse proxy, hosted by Cloudflare | 100k requests/day = **~5,500 generates/day** | $5/month |
| Routing backend | Whoever computes the routes | HeiGIT: 40 req/min = **~2 generates/min** | Oracle box |

One generate costs ~18 requests, which is where both conversions come from.

Whichever number is tighter is the one that actually stops you. Today that is
HeiGIT's 2/minute — the daily cap is unreachable behind it. Stand up the Oracle
box and the per-minute ceiling goes to roughly 30-60/min, at which point the
5,500/day becomes the binding one.

In users: **roughly 100 today, roughly 2,500 with Oracle.** A hundred people
generating twice on a Saturday morning is 3.3/minute against a ceiling of 2 —
errors during the exact hour the app exists for. 2,500 people generating twice
is 5,000/day, just under the Worker cap.

**Paying Cloudflare $5 without the Oracle box buys nothing** — it lifts a limit
we are nowhere near. The Worker already exists and is already free; it needs no
action beyond one setting change when the box is ready.

The 30-60/min for Oracle is the only number here nobody has measured. HeiGIT's
40/min, Cloudflare's 100k/day and the ~18 per generate are all documented or
counted.

## Oracle routing: deployed, not yet switched on

Built 2026-08-19. **The box exists, serves correct routes, and is not yet
carrying any traffic** — the Worker still sends everything to HeiGIT because
`SELF_HOSTED_ORIGIN` is unset. That is the safe order: prove the backend, then
flip one secret.

| | |
|---|---|
| Instance | `aimless-ors`, Oracle always-free |
| Shape | VM.Standard.A1.Flex, 2 OCPU / 12 GB, Ampere |
| OS | Ubuntu 24.04 aarch64 |
| Region | US East (Ashburn), AD-2 |
| Public IP | 129.213.20.151 |
| SSH | `ssh -i ~/.ssh/aimless_oracle ubuntu@129.213.20.151` |

Graph built in 1742 s, 1.3 GB on disk. Verified against HeiGIT on eight seeds:
within ~1% on duration and 0.6 points on highway share. Full numbers and the
build runbook are in `selfhost/README.md` and `selfhost/DEPLOY.md`.

**What it bought is throughput, not latency.** Twelve concurrent requests finish
in 0.73 s, so a generate lands near 1.1 s and sustained throughput is roughly
**50 generates per minute against HeiGIT's 2**. A single request also got faster
(38-80 ms against 430-970 ms), but under a real burst two Ampere cores queue.

### Live as of 2026-08-20

**New Jersey traffic now routes to our own box.** Verified by the
`X-Aimless-Served-By` header: Marlboro and Jersey City come back `self`, Apple
Park and Chicago come back `heigit`.

- Hostname `https://ors.workdocks.com` via Cloudflare Tunnel — no inbound ports
  open on the instance.
- An nginx gate on `127.0.0.1:8081` checks `X-Aimless-Origin` and 403s anything
  without it, because a tunnel hostname is public to anyone who knows the name
  and ORS has no auth of its own. The Worker sends it from `SELF_HOSTED_TOKEN`.
- Worker secrets: `SELF_HOSTED_ORIGIN` (note the mandatory `/ors` suffix),
  `SELF_HOSTED_TOKEN`, plus the existing `ORS_API_KEY` and `CLIENT_TOKEN`.
- **Fallback tested, not assumed**: with the gate stopped, a New Jersey request
  still returned 200 from HeiGIT and recovered on its own.

Rollback is still `wrangler secret delete SELF_HOSTED_ORIGIN` and a deploy.

### What is left

1. **Cloudflare Tunnel — blocked on owning a domain.** Named tunnels require a
   zone in the Cloudflare account; quick tunnels are ephemeral and not for
   production. Roughly $10/year at Cloudflare Registrar if there isn't one.
2. **Cloudflare Access with a service token** in front of the tunnel hostname,
   with the Worker sending `CF-Access-Client-Id` / `CF-Access-Client-Secret`.
   Without it the hostname is open routing for anyone who finds it — the same
   problem we are leaving HeiGIT to avoid, except on a box we pay for.
3. **Set `SELF_HOSTED_ORIGIN`** to `https://ors.<domain>/ors` and deploy. **The
   `/ors` suffix is mandatory and omitting it fails silently** — see
   `worker/README.md`. Verify with the `X-Aimless-Served-By` response header,
   which must read `self` for a New Jersey origin.

Rollback is `wrangler secret delete SELF_HOSTED_ORIGIN` and a deploy. No app
change, no review.

### Watch for

**Oracle reclaims idle always-free compute** — under ~20% utilisation across 7
days. A routing box for an app with no users is exactly that profile. The Worker
degrades to HeiGIT on a dead socket, so the failure mode is "slower", not
"broken", but nothing currently notices or alerts.

`tools/oracle-retry.sh` rebuilds the instance if it is ever reclaimed; it
rotates availability domains until free ARM capacity appears. Capacity in
Ashburn was refused on AD-1 and granted on AD-2 on the first attempt.

**Coverage is still the limit.** The graph holds NJ, PA, NY and DE, and the
Worker only routes *New Jersey* origins locally — deliberately, since a route
generated near a graph edge gets silently clipped. Everyone else still goes to
HeiGIT and still shares its ceiling. This scales one region, not the app.

**Open question, not yet answered:** whether "v2" also means a paid Pro tier.
Unrelated work — StoreKit, subscriptions, a real App Review surface — and should
be planned separately.

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

- **ORS licensing: resolved 2026-08-08, and the old claim was wrong.** HeiGIT's
  Terms of Service place no restriction on commercial or production use.
  Prohibited Conduct covers unlawful purposes, abusive content, IP
  infringement, overburdening the service and transmitting personal data —
  nothing about who you are or whether you ship. `SPEC.md` has been corrected.

  This was assumed during prototyping, never checked, and shaped planning for
  a while. Self-hosting is now an optimisation, not a compliance requirement.

- **Attribution string: fixed in source, not yet shipped.** Now reads
  `© openrouteservice by HeiGIT | Data from OpenStreetMap`, which is what
  HeiGIT's terms specify. The shipped 1.0 (3) build still carries the old
  wording — it credits both parties, so it was not worth pulling a live
  submission for, but it is not the string they ask for. Goes out with the next
  build. Note the required string also differs from what secondary sources
  claim; the ToS is the only source worth trusting.

- **Bursty concurrency is the real licence risk, not who uses the app.** The
  usage limits section lists "sending requests too fast, i.e. too many requests
  per second" alongside daily overuse, with temporary blocking and account
  removal as stated consequences. Every generate fires 12 concurrent requests
  and then up to 6 more.

  Deliberately not fixed. Practical exposure at one user is nil, and the fix
  costs the thing the app is judged on: 12-at-once is ~1s wall clock, capping
  to 4 makes it three sequential waves at ~3s. If it ever needs doing, do it
  **in the Worker, not the client** — client-side pacing throttles one phone,
  so ten phones generating at once still burst, and a server-side fix ships
  without an App Store review.

- **Route results are CC-BY-SA 4.0.** Fine for display with attribution. The
  share-alike clause would matter if loops were ever exported or shared as
  data, so check before building any share feature.

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

- **ORS quota is shared across every install.** 40 requests/minute, and one
  generate is ~18 (up to ~36 with a retry round). That works out to roughly
  **two generates per minute across all users combined**, which is the real
  ceiling — not the daily quota. Fine at one user; it starts hurting somewhere
  around a hundred active ones, and it hurts on weekend mornings specifically,
  which is the whole use case.

- ~~The ORS free tier is not licensed for production use.~~ **Retracted
  2026-08-08.** HeiGIT's terms place no restriction on commercial or production
  use. This was assumed during prototyping, never checked, and wrongly shaped
  planning for weeks — it is why self-hosting kept getting framed as a
  compliance requirement. It is an optimisation, nothing more.

The quota ceiling is real but not urgent, and **self-hosting is now measured
rather than theorised** — see `selfhost/README.md`. Summary of what it costs:

| | |
|---|---|
| Extract (NJ + PA + NY + DE) | 0.98 GB |
| Graph build | 955 s, **1.96 GB peak heap** |
| Serving with MMAP | **1.12 GB** |
| Latency | 55-140 ms, against 430-970 ms hosted |
| 12-request burst | 0.28 s, no rate limit |

Two findings worth keeping:

- **Build memory barely grows with the extract.** Six times the map cost 15%
  more heap, not six times. `graphs_data_access: MMAP` keeps the graph off-heap
  during the build as well as during serving, so disk and build time scale and
  RAM does not. Linear extrapolation predicted ~10 GB and was wrong by 5x. This
  is what puts it inside a free tier.
- **The neighbouring states are not optional.** A New Jersey-only graph ends at
  the state line: Jersey City and Lambertville failed outright, and the
  north-west corner silently returned a loop **19% short with no error**, which
  nothing at runtime could have detected.

`worker/src/index.js` already routes New Jersey traffic to a self-hosted
instance and falls back to HeiGIT on any non-200, timeout or dead socket. It is
inert until `SELF_HOSTED_ORIGIN` is set, so it deploys safely before a server
exists.

## Prototype files kept for reference

- `loopgen_ors.py` — ORS prototype, reads `ORS_KEY` env var. Stale, see above.
- `loopgen.py` — earlier GraphHopper attempt, superseded.
- `geojson2gpx.py` — converts loop output to GPX for simulated movement (v2).
- `*.geojson`, `gpx/` — prototype output. `p8.geojson` is only the start marker;
  the route that went with it is `p8_route.geojson`, renamed out of
  `p8.geojsonclear` — a `> p8.geojson` and a `clear` on one line.

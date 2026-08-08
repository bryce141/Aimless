# Handoff — start of build

Read `longwayspecmvp.md` first. That's the source of truth. This file only
records decisions made after the spec was written, and open questions.

## Environment (already verified)

- Xcode 26.6 at `/Applications/Xcode.app`, iOS 26.5 SDK, simulator runtimes present.
- `xcode-select` was pointed at CommandLineTools. Fix with:
  `sudo xcode-select -s /Applications/Xcode.app`
- No git repo in this directory yet.

## Decisions made after the spec

- **Deployment target: iOS 17+.** Uses SwiftUI-native `Map` with `MapPolyline`
  and `MapCameraPosition`. No `UIViewRepresentable` / `MKMapView` bridging.
- **No direction picker in v1.** The spec listed it as optional and flagged that
  ORS `bearings` may be ignored inside `round_trip`. Cut it. GenerateView is
  duration picker + Generate button only. Revisit after the first real drive,
  when there's evidence about whether loops actually are too suburban.
- **Project name: TBD.** Spec says "Loop", folder says "LongWay". Recommend
  LongWay — an app target named `Loop` collides awkwardly with `Loop.swift`,
  the model type. Bundle ID e.g. `com.brycepercoco.longway`.

## Proposed change to the spec's LoopScorer — withdrawn

The concern was that a second serial retry round doubles wall-clock wait, 20+
seconds staring at a spinner. Measured: ORS responds in 0.5-1.0s, so 12
concurrent seeds is 1-2 seconds and a retry round is about a second. There's no
spinner problem. The spec's original "widen and retry" stands.

## The two live API checks — done 2026-08-07

Both ran. 80 requests at the Marlboro origin. Results are folded into the spec;
summary here.

1. **Short loops: the picker floor is 60 minutes.** Short requests don't fail
   (8/8 at every size down to 4km, 0% highway, no hairpin problem). But a real
   30 minute drive needs a ~4km request, and those loops spend 87% of their
   length within 2km of the start. Neighborhood lap. See Known floors in the
   spec.

2. **Failure rate: 94%, not 67%.** 45/48 seeds succeeded. Zero failures at 16km,
   31km and 47km requests; 3/12 at 63km. Two of the three were HTTP 500
   "Could not find a valid point after 3 tries", not 404 — the client has to
   swallow 5xx too.

**The bigger finding neither check was looking for:** the spec's duration math
was broken. 45 km/h and a flat 30% overshoot correction are both wrong and they
compound, so tapping "30 minutes" produced a 62 minute drive. Fixed in the spec:
a calibrated duration-to-request-size table, and LoopScorer now filters on the
`duration` ORS returns instead of on distance.

Probe scripts that produced this are throwaway, but the parameters are recorded
in the spec. `loopgen_ors.py` is still stale — it sends `avoid_features` and
defaults to `points: 5`, both superseded.

## Existing files here

- `longwayspecmvp.md` — the spec
- `loopgen_ors.py` — ORS prototype, reads `ORS_KEY` env var
- `loopgen.py` — earlier GraphHopper attempt, superseded
- `geojson2gpx.py` — converts loop output to GPX for simulated movement (v2 only)
- `*.geojson`, `gpx/` — prototype output, keep for reference

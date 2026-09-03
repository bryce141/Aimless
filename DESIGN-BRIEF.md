# Aimless — design brief

Written 2026-09-02, for a **restyle of `Theme.swift` only**. Read "Out of
scope" before proposing anything structural; the layout has a rejection history
and is deliberately frozen this pass.

## What the app is

You tap one button and it hands you a road loop that starts and ends where you
are standing. No destination, no search field, no saved places. You pick how
long you want to be out — 1 hour, 1½ hours, 2 hours — and it gives you three
loops of roughly that length on back roads, then hands the chosen one to Google
Maps to navigate.

It is named after the thing it is for. The subtitle on the first screen is
"No particular place to be."

It deliberately avoids highways. It shows you a shape, a duration, a distance,
and how much of it is highway. That is the whole product.

## Who uses it, and where

One person, in a parked car, about to drive for pleasure. Realistically:

- **A weekend morning or a weekday evening.** Not a commute. Not a task.
- **Phone mounted or in a cupholder**, glanced at rather than read.
- **Sunlight is a real condition.** So is dusk. So is a dark garage.
- **One thumb.** The other hand is on a steering wheel or a coffee.
- The user has already decided to go driving. The app is not competing for
  attention or trying to earn a session. It should feel like a coin toss, not a
  dashboard.

It has never actually been driven. Glanceability is therefore **untested** — a
design that reads well on a desk may not survive a windshield. Prefer high
contrast and large type where there is a choice.

## The two screens

**Generate**

- Title "Aimless", subtitle "No particular place to be"
- A small map card showing current location
- "How long do you want to be out?"
- A duration slider with tick labels ("1 hr", "1½", "2 hr") and a large spoken
  readout above it ("1 hour", "1½ hours", "2 hours")
- A primary **Generate** button, which becomes a "Finding you…" spinner while
  a location fix is pending
- An inline callout above the button for blocked taps and errors
- A quiet ambient line of text

**Results**

- The loops as a swipeable stack, each drawing its polyline on a MapKit view
- Per loop: distance, estimated time, highway percentage
- A **Drive This** button
- A required attribution line (see constraints)

## The current look, and why

Not a default — a stated position, so change it on purpose rather than by
accident.

- **Dark only.** Views force `.preferredColorScheme(.dark)`. The reasoning in
  the code: *"this is an app you open in a car, usually not at noon, and a warm
  dusk palette is the point rather than a theme choice."*
- **A vertical gradient** from night indigo at the top through a muddy plum to
  ember at the bottom — dusk, roughly when you would actually go for a drive.
- **Warm off-white ink** rather than pure white, which was judged "clinical and
  fights the warmth." Three weights: ink, inkSoft, inkFaint.
- **Exactly one saturated colour** — an ember orange. Everything else is
  neutral. The accent carries the primary button and the active states.
- **One exception to that rule:** a green start marker, which exists to match
  the app icon and the flag on the map. Keep them matched to each other.
- **Surfaces are white at 7% opacity** with a **white 13% hairline border**,
  24pt continuous corner radius.
- **Rounded system font throughout**, because the default face "reads like a
  settings screen; rounded reads like something you'd use on a weekend."

## Hard constraints

**These are not stylistic. Breaking them breaks the app or fails review.**

1. **The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) but runs on iPad in
   a compatibility window that is shorter than any iPhone screen.** Every App
   Review pass that named a device used an iPad. Two of four rejections were
   the Generate button being clipped out of that window. Nothing may grow tall
   enough to push it off screen.
2. **The Generate button must be visible and reachable in every location
   state** — permission undecided, denied, reduced accuracy, locating, failed.
   Several of those add two lines of status text plus a recovery link.
3. **Blocked-tap feedback is an inline callout, never an alert.** iOS silently
   discards an alert while the system location prompt is presenting, which is
   exactly when a new user taps. The callout must stay legible while a system
   dialog is on screen — so it needs to hold its own against a dimmed
   background.
4. **A fourth duration tick is being added** (30 minutes, for test drives). The
   picker must hold four labels without crowding.
5. **The attribution string is fixed by HeiGIT's terms** and must read exactly
   `© openrouteservice by HeiGIT | Data from OpenStreetMap`. Wording cannot
   change. It must remain legible — small and quiet is fine, invisible is not.
6. **iOS 17+, SwiftUI, native MapKit.** The map is a system component; it will
   not fully absorb a custom palette.

## In scope

Everything in `Theme.swift`, which is 70 lines and is the only place colour and
type live. `GenerateView.swift` contains zero hardcoded colours or fonts, so
changes here propagate everywhere automatically:

- The palette — gradient stops, ink weights, the accent, the start marker
- Whether the app stays dark-only or adapts
- Type face, weights, and scale
- Corner radius and the surface/hairline card treatment

## Out of scope

- Where controls sit, and the structure of the bottom action bar
- The map's minimum height
- Adding, removing, or reordering screens or controls
- Replacing the slider with a different control

The layout is being held until the app has actually been driven, on the grounds
that the real design brief for a car app — what is readable at 45 mph, in
sunlight, with one thumb — cannot be obtained from a simulator on a desk.

## The tone to aim for

Unhurried. A little romantic. The opposite of a productivity app. It should
suggest an evening rather than a task, and it should get out of the way in
about four seconds — which is the entire time the user will look at it before
putting the car in gear.

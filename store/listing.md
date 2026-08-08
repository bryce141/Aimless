# App Store listing copy

Everything App Store Connect asks for, written out. Character limits noted so
edits stay inside them.

---

## Name (30 char limit)

```
Aimless
```

**Check availability first.** This project has already lost two names to
collisions ("LongWay" clashed with an existing driving app, "Loopback" with
three apps including Rogue Amoeba's). If `Aimless` is taken, the store name and
the on-device name can differ — the fallbacks below keep the icon label short
while satisfying the store:

- `Aimless — Drives` (16)
- `Aimless Loops` (13)
- `Aimless: Loop Drives` (20)

## Subtitle (30 char limit)

```
Circular drives from anywhere
```
(29)

## Promotional text (170 char limit, editable without a new build)

```
No destination, no backtracking. Pick how long you want to be out and get a loop that brings you home the long way.
```
(114)

## Description (4000 char limit)

```
Aimless makes driving loops that start and end exactly where you are.

Pick how long you want to be out — 60, 90, or 120 minutes — and Aimless hands
you three routes that wander out and come back without retracing themselves.
Tap one and it opens in Google Maps, ready to drive.

It exists because aimless drives have a flaw. You head out with no
destination, you get too far from home, and the drive back becomes dead time
retracing roads you just covered. A loop fixes that. The whole drive is the
good part.

WHAT IT DOES

• Generates three loops starting from your current location
• Shows each on a map with real distance, drive time, and highway percentage
• Hands off to Google Maps for turn-by-turn navigation
• Favors back roads — loops with significant highway are filtered out

BUILT FOR BACK ROADS

Aimless deliberately avoids highways. Every candidate route is checked for
motorway content and anything with a meaningful share is discarded, because a
highway loop is not a drive worth taking.

The times are honest, too. Aimless routes each loop through the exact waypoints
it hands to Google, so the duration you see is the duration you drive — not an
optimistic estimate of a route you were never going to take.

WHAT IT DOESN'T DO

No account. No sign-up. No history, no sync, no ads, no tracking. It doesn't
store anything, including where you have been. Open it, tap once, drive.

Aimless needs a location fix to know where your loop should start, and it needs
Google Maps for navigation. That's the whole dependency list.

Good for a Sunday morning, a passenger worth talking to, and no particular
place to be.
```

## Keywords (100 char limit, comma-separated, no spaces after commas)

```
drive,driving,road trip,loop,route,scenic,backroad,cruise,joyride,country,roads,detour,wander
```
(93)

Deliberately excludes "Aimless" — the app name is already indexed, so spending
keyword characters on it is waste.

## Category

- Primary: **Navigation**
- Secondary: **Travel**

## Age rating

4+. No objectionable content. The questionnaire answers are all "None."

## Price

Free.

## Support URL

```
https://github.com/bryce141/Aimless
```

## Privacy Policy URL

```
https://github.com/bryce141/Aimless/blob/main/PRIVACY.md
```

Required, and doubly so because the app uses location. If a bare GitHub page
feels too rough, enabling GitHub Pages on the repo gives a cleaner URL for the
same file with no extra hosting.

---

## App Privacy questionnaire

App Store Connect asks this separately from the policy, and the answers must
match the policy or review flags it.

**Data collected: Precise Location**

- Used for: **App Functionality**
- Linked to the user's identity: **No**
- Used for tracking: **No**

Nothing else is collected. No identifiers, no usage data, no diagnostics — the
app has no analytics SDK of any kind.

Note the distinction Apple cares about: location is *transmitted* to a routing
service to compute a route, but it is not *stored* and not associated with any
identifier. That is still a disclosure, so declare it.

---

## Export compliance

Aimless uses HTTPS and nothing else. It qualifies for the standard exemption:

- Uses encryption: **Yes**
- Qualifies for exemption: **Yes** (only standard encryption via the OS)

---

## Notes for App Review

Paste into the "Notes" field. Reviewers reject location apps they can't make
work, and this app does nothing visible without a fix.

```
Aimless generates circular driving routes starting from the user's current
location.

TO TEST:
1. Allow location access when prompted. The app requires precise location — it
   deliberately refuses to generate under reduced accuracy rather than build a
   route starting kilometers from the user.
2. Choose a duration (60, 90, or 120 minutes) and tap Generate.
3. Three loops appear as swipeable maps with distance, drive time, and highway
   percentage.
4. "Drive This" opens the route in Google Maps or in Safari if Google Maps is
   not installed.

NOTES:
- Generation takes 1-2 seconds and issues roughly 18 routing requests.
- The upstream routing provider rate-limits at 40 requests/minute, so three
  generates inside one minute will show a "rate limit" message. This is
  expected and handled; waiting a minute resolves it.
- Loops are generated from real road data, so results depend on the simulated
  or actual location used. A suburban or rural location gives better results
  than a dense city center or a location surrounded by water.
```

---

## Screenshots

In `store/screenshots/`. All 1320 × 2868 — the 6.9" iPhone size App Store
Connect requires. The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so no
iPad set is needed.

| File | Shows |
|---|---|
| `01-pick-how-long.png` | The Generate screen — map, duration slider, button |
| `02-one-hour-loop.png` | A 58 min / 28 mi / 0% highway loop |
| `03-two-hour-loop.png` | A 124 min / 63 mi / 0% highway loop |

Captured with a pinned status bar (9:41, full bars, charged) via
`simctl status_bar override`, and with `-autoGenerate -duration N` to drive the
app past the first screen — `simctl` has no tap command.

**Two things that will bite whoever regenerates these:**

1. **Settle after `terminate` before `launch`.** Without a pause, `simctl`
   returns the still-running process and silently keeps the *previous* run's
   launch arguments, so the screenshot shows the wrong duration with no error.
2. **Leave 2+ minutes between generates.** One generate is ~18 requests, but a
   retry round doubles it to ~36, and the upstream limit is 40/minute. Back to
   back captures trip it and the screenshot catches the rate-limit message
   instead of a loop.

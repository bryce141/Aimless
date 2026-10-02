# Handoff — shipping on the App Store, served by our own routing box, never driven

Read `SPEC.md` first for the routing design. `store/listing.md` holds everything
App Store Connect asks for. This file records state, decisions, and what's open.

Last updated 2026-10-01.

## Where this stands

**1.0.2 build 7 is live on the App Store as of 2026-09-09.** It carries the
retrace stat and the dashed map overlay — task 13.

**Three clean review passes in a row**, after four rejections:

| Version | Cleared | Carried |
|---|---|---|
| 1.0 (5) | 2026-09-02 | Silent-button fix, California on our own box |
| 1.0.1 (6) | 2026-09-04 | The 30-minute option |
| **1.0.2 (7)** | **2026-09-09** | **Retrace stat + dashed map overlay** |

**The variable that changed is iPad testing.** All four rejections predate it;
all three passes had it. Every review that ever named a device used an iPad, and
the app is `TARGETED_DEVICE_FAMILY = 1`, so it runs there in a compatibility
window shorter than any iPhone screen. **Keep doing it before every submission.**

### Outage 2026-09-13 to 2026-09-14 — 47 hours, found 2026-10-01

**The box was down for about 47 hours, and nothing in this file recorded it.**
A clean `reboot` at 2026-09-13 00:40Z (kernel 1018 → 1020, started from Bryce's
home IP) stopped `aimless-ors`, and Docker's default restart policy `no` left it
stopped while nginx kept forwarding to nothing. For those two days every request
fell back to HeiGIT's 200/day.

Fixed 2026-09-14 23:29Z by `restart: unless-stopped` in
`~/selfhost/docker-compose.yml` (backup alongside as `.bak-20260914`). Verified
2026-10-01: the running container reports `restart=unless-stopped`, started
2026-09-14 23:30Z, health `ok`. **Not yet re-proven by an actual reboot.**

**The monitor caught it; nobody heard it.** UptimeRobot logged the incident at
2026-09-12 20:45:56 EDT (the reboot minute) through 2026-09-14 19:38:13 EDT
(the fix), 1d 22h 52m. No UptimeRobot email has ever landed in
bdrp777@gmail.com, so the alerts went to an inbox nobody was watching.
**Fixed 2026-10-01:** UptimeRobot iOS app installed with push on, attached to
the monitor, test notification confirmed by Bryce.

**Lesson:** a reboot of the box is an outage unless the restart policy is set.
It now is. Whoever fixed it did not write it down; that is how it hid for two weeks.

### If you are picking this up cold

- **The app works and is shipping.** Nothing is on fire.
- **Routing is ours.** The whole US runs on the Oracle box; capacity is ~2,750
  users/day against ~5 before 2026-09-03. See "The ceilings".
- **1.0.3 build 8 is built and simulator-tested (2026-10-01)**, not yet
  submitted. See "1.0.3 as built". **Submit by mid-November**: Apple's
  holiday slowdown and shutdown land in late December, and 30-minute loops are
  what people will use for Christmas-lights drives.
- **Task 8 is now actionable** — the US graph has had six days of real use.
- The open checklist below is the authoritative list. Numbers are stable.

Build 1.0 (5) was the fifth submission and carried both the silent-button fix
and California on our own routing box. See "Rejected a fourth time" below for
what is in it and "Widening coverage" in `selfhost/DEPLOY.md` for how the graph
was built.

**What cleared review is not the same as what is good, and that gap is the
current work.** The 30-minute option shipped in build 6, and measurement the
same day (see "Retrace and reversal, measured 2026-09-04") showed it is the
**worst size for retracing** and worst of all in Marlboro — median 18.9% of the
drive on road already covered, up to 43.3%. Apple had no reason to object, but
the option most likely to draw a first-time user is the one that most often draws
itself over its own line on the map.

**1.0.2 made that visible. It did not fix it.** A 43%-repeated loop still ranks
in the top three; it is now labelled rather than silent. **Removing those loops
is task 14**, deliberately held back to a separate release because a filter is a
new way to show the user nothing — the shape of rejections three and four. Tune
its threshold on real retrace data now that the stat is shipping, not on the
113-loop sample.

**The coverage problem is solved as of 2026-09-03.** It was the top open item in
this file for a day: outside New Jersey and California the app supported
single-digit generates per day across every install on earth. The whole United
States now runs on our own box, and the app supports **roughly 2,750 users a
day** against roughly 5 before. See "Widening to the whole country" below for
what it cost and where it is still weak, and "The ceilings" for the arithmetic.

**The box is now watched.** The entire product depends on it, where a day ago
two states did, and its failure mode is silent: every request in the country
falls back to HeiGIT's 200/day, which reads as the app being bad rather than the
box being down. An external monitor polls `/health/selfhosted` every five
minutes as of 2026-09-03. What is still unproven is the alarm firing on a real
outage — see task 6.

Four rejections. The first two were not code defects; the third and fourth
were:

1. **2026-08-14, Guideline 2.1 Information Needed.** Wanted documentation the
   submission never carried, plus a screen recording on a physical device.
   Answers live in `store/review-notes.md`. That rejection forced the device
   test that had been skipped, and the app passed it — location, generation and
   the Google Maps handoff all work on an iPhone Air running iOS 26.5.2.
2. **2026-08-19, Guidelines 2.1(a) and 1.5.** The rate limit and the Support
   URL. Both fixed server-side and verified — see the next section.
3. **2026-08-23, Guideline 2.1(a).** "Nothing happened when we tapped on
   generate", on an iPad Air (5th generation). A real layout defect plus two
   compounding location bugs. Fixed in 1.0 (4) — see below.
4. **2026-08-27, Guideline 2.1(a).** The same sentence again, on 1.0 (4), on an
   iPad Air 11-inch (M3). The layout fix held; the alert that was supposed to
   explain the blocked tap never appeared, and could never appear again. See
   below.

Worth carrying forward from the first round: **iOS does not capture system
permission dialogs in screen recordings**, so the location alert cannot be
filmed. It shows indirectly — the app sits on "Finding you..." while the alert
is up, and the status-bar arrow appears the moment access is granted. Two
recordings were thrown away before working that out.

**Still never driven, and that is now a decision rather than a gap.** Asked
directly on 2026-09-02, Bryce declined: not needed. So the duration table, the
highway ranking, the direction-bias question and handoff fidelity all stand on
ORS's own numbers and stay that way. Stop filing it as an open item and stop
proposing it — it has been raised and answered.

## Open checklist

Kept current. Everything here is unfinished; anything finished moves into the
section that explains it. **Numbers are stable identifiers — refer to "task 3"
and it will mean the same thing next week.** When one is done, mark it `[x]` and
leave the number in place rather than renumbering the rest.

Ordered by what bites first, not by size. **B** = only Bryce can do it.

| # | | What |
|---|---|---|
| ~~1~~ | **B** | ~~Uptime monitor~~ — **done 2026-09-03**, verified receiving checks |
| ~~2~~ | **B** | ~~Upload and submit build 6~~ — **live on the App Store 2026-09-04** |
| ~~3~~ | | ~~Persist the swapfile~~ — **done 2026-09-03** |
| ~~4~~ | **B** | ~~"What's New" text~~ — **done**, build 6 submitted |
| ~~5~~ | **B** | ~~Cloudflare Access~~ — **done 2026-09-03**, enforcing |
| ~~6~~ | | ~~Test the health alarm~~ — **done 2026-09-03**, full cycle verified |
| ~~7~~ | | ~~Delete stray `imless` Worker~~ — **done 2026-09-03** |
| ~~8~~ | **B** | ~~Reclaim 2.4 GB (`graphs.nj-ca`)~~ — **done 2026-10-01**, needed `sudo` (files are root-owned); disk 98 GB free, health `ok` after |
| ~~9~~ | | ~~Explain `round_trip` failure near water~~ — **done 2026-09-03**, it is loop size |
| ~~10~~ | | ~~Alaska region box~~ — **done 2026-09-03**, plus Hawaii |
| ~~11~~ | | ~~Correct `selfhost/README.md`~~ — **done 2026-09-03** |
| ~~12~~ | | ~~Clean stale "What is left"~~ — **done 2026-09-03** |
| ~~13~~ | | ~~Retrace: colour on map + show the stat~~ — **live 2026-09-09** as 1.0.2 build 7 |
| 14 | | Retrace half **built 2026-10-01 as 1.0.3 build 8**, awaiting device test + submit. Reversal button and curviness moved to **1.0.4** |
| 15 | | Seed scaling off `X-Aimless-Served-By` — **proposed, unmeasured** |

**13, 14 and 15 are app changes**, so unlike everything above them they need a
new binary and another App Review pass.

**They are deliberately split across two releases, and the split is the whole
point.** An earlier plan put all three in one build; that was wrong. The two
changes that can produce an **empty result set** (the retrace filter) or a
**control that looks dead** (the reverse button) are the exact shapes of
rejections three and four. Shipping them alongside everything else means three
new failure surfaces at once and no way to tell which one drew a rejection.

- **1.0.2 = task 13 only. Shipped 2026-09-09, cleared review first time.**
  Compute retrace, colour the doubled segments, show the number. No filter, no
  new control. It **cannot** return empty and has nothing new to tap, so it
  cannot produce a 2.1(a).
- **1.0.3 = tasks 14 and 15**, with the filter threshold tuned on real retrace
  data gathered from 1.0.2 in production rather than from a 113-loop sample.

**The split worked and is worth repeating.** The low-risk half is live and the
risky half now ships against a known-good baseline, with real data to set its
threshold. Do this again whenever a release mixes safe changes with ones that can
show the user nothing.

`Aimless/Services/Geometry.swift` already implements the maths for both releases
and is cross-checked — see the pre-submission checklist.

### 1.0.3 as built, 2026-10-01

**Scope cut on purpose.** The plan put the retrace filter, the reverse button,
curviness and seed scaling in one release. With Apple's December shutdown as a
hard deadline, 1.0.3 carries only changes that **cannot show the user nothing
and add nothing new to tap**: the same rule that let 1.0.2 pass first time.
The reverse button (a new control) and curviness go to **1.0.4 in January**;
task 15 stays unmeasured.

**1. Retrace re-ranks rather than filters.** `LoopScorer.rank` sorts loops with
`hasNotableRetrace` (≥10%, the same line that shows the note) behind clean ones,
least-repeated first. Nothing is removed, so the result set is exactly as large
as before. **2. A retry round also fires when a shown loop is notable**, in
`LoopViewModel.generate`, not only when there are fewer than three.

**Tuned by simulation, not the 113-loop sample.** `tools/simulate-ranking.py`
replays the app's whole generate (24 seeds, best 6 of each 12 verified, retry)
from 12 suburbs, the kind of places people drive for lights, through an SSH tunnel to
the box; `tools/analyze-ranking.py` replays ranking policies over the saved
loops. 1,031 candidates, 474 verified.

| 30-minute size | today (1.0.2) | 1.0.3 |
|---|---|---|
| Mean retrace of the three shown | 13.1% | **5.2%** |
| Worst shown | 44.4% | **16.7%** |
| Shown slots over 10% | 47% | **3%** |
| Empty results | 0 of 12 | 0 of 12 |
| Generates needing a retry round | 58% | 75% |
| Median distance from 30 min | 20.9% | 24.5% |

Marlboro specifically: mean 33.3% → 8.7%, worst 43.3% → 16.7%. 60m improves
(worst 16.6% → 7.6%); 90m and 120m barely change because they rarely retrace.
The cost is about one minute of duration accuracy at 30m and more retries.

**The first policy tried had a bug the simulation caught:** when fewer than three
clean loops exist, the leftovers were ordered by duration, so Marlboro still
showed its 43% loop. Leftovers are now ordered by least retrace.

**Noticed, not acted on:** the simulation returned no loops at 120m for 3 of 11
origins under *today's* code too. That's a pre-existing gap, unchanged by 1.0.3, and
probably the known water/loop-size failure. Worth a look before 1.0.4.

**3. Backstop wording.** `.fixFailed` now reads "No location yet. Answer the
permission prompt if one is showing, or try a clearer view of the sky." It's
98 characters, deliberately shorter than `.denied` (109), the longest note
verified to fit the iPad window with Generate visible. **That
state could not be triggered in the simulator** (it holds its last fix even after
`simctl location clear`), so the fit is argued from length, not seen.

**Verified on the iPad Air 11-inch (M4) simulator:**

| Check | Result |
|---|---|
| Marlboro, 30 min, permission granted | 3 loops; first is **2% repeated** (1.0.2 led with 43% here) |
| **Threshold forced to 0%**, every loop "notable" | **Still 3 loops**, note renders, Drive This visible. Source reverted after |
| Permission denied | Callout + Open Settings, Generate visible |
| Debug and Release builds | Both succeed |

**Still to do before submitting (Bryce):** the permission-prompt tap on a
real device or a fresh simulator (the one check that needs a hand on the
screen), archive, What's New text, submit.

Simulator note: `clients.plist` keys contain a colon, so PlistBuddy cannot edit
them; use Python `plistlib`. This device had been left at denied (`Authorization
= 1`) by an earlier session.

### Task 13 as built, 2026-09-04

- `Geometry.retraceFraction` and `Geometry.retracedSegments` share one private
  index pass, **so the number in the stat row and the dashes on the map can
  never disagree.**
- `Loop.retraceFraction` is computed at construction in
  `RouteService.drivenRoute`, on the driven path like every other number on a
  `Loop`. No extra request.
- `LoopMapView` stores the retraced runs in `init` rather than a computed
  property — the page stack re-renders on every swipe and the polyline is
  thousands of points.
- Dashes are `Theme.repeated` cyan, **same 5pt width as the route**. At 7pt with
  a round cap they render as beads fatter than the line and bury the orange
  instead of marking it. Cyan against ember also survives red-green colour
  blindness, where cyan against the green start flag would not.
- The explanatory note appears only above 10% (`Loop.hasNotableRetrace`).

**Verified on an iPad Air 11-inch (M4) simulator and an iPhone 17e**, generated
from Marlboro at the 30-minute size. Four stats fit the row on both, the note
does not clip, Drive This stays visible. Release configuration also builds.

Version bumped to **1.0.2, build 7**. Release builds after the bump.

### Pre-submission checklist run against 1.0.2, 2026-09-04

On the iPad Air 11-inch (M4) simulator, which is the device class from two
rejections:

| State | Result |
|---|---|
| **Tap Generate while the permission prompt is up** — rejection 4's exact moment | Tap absorbed, button becomes a "Finding you..." spinner. **Not silent, does not latch.** |
| 15-second backstop with no fix | Falls back to "Couldn't get a location fix" with **Try Again**, and Generate re-enables |
| **Permission denied** | Explicit callout — "needs location access... Turn it on in Settings" — plus **Open Settings**, Generate stays enabled |
| Happy path, permission granted | 3 loops, retrace stat and dashes render |
| Release configuration | Builds |

**Reduced accuracy is the one state the tooling cannot set** — `simctl` has no
switch for it, and the `clients.plist` trick only grants authorisation, not the
accuracy level. It is untested here and **unchanged by 1.0.2**, which touches
neither `LocationProvider` nor the `accuracyAuthorization` gate.

**One wording weakness noticed, deliberately not fixed in 1.0.2.** When the
15-second backstop fires because the user has not answered the permission prompt
yet, the message blames the sky — "Somewhere with a clearer view of the sky
usually does it" — when the real cause is an unanswered dialog. It is honest
about the symptom and misleading about the cause. **This is shipped behaviour
from build 5, which has cleared review twice**, so changing it now would add risk
to a release whose whole point is having none. Candidate for 1.0.3.

**The first loop it returned was 43% repeated** — from Bryce's own coordinates,
ranked in the top three. That is the measurement showing up in the product, and
it is the argument for the task 14 filter: 1.0.2 makes the problem *visible*, it
does not fix it.

**1. ~~Uptime monitor~~ — done 2026-09-03.** UptimeRobot free tier, HTTP/S,
5-minute interval, on `/health/selfhosted`. Test Notification confirmed the
alert reaches Bryce.

**It was created paused, and that is the trap worth remembering.** The URL and
interval were correct from the start, but the monitor had never run a check, so
the dashboard showed 100% and zero incidents — 0 of 0, which renders identically
to a healthy history. Confirmed live only when a real `GET /health/selfhosted`
appeared in `wrangler tail` at 22:24:10Z. **Verify a new monitor by watching a
check arrive, not by reading its uptime percentage.**

Expect it to fire during any future graph rebuild, correctly: during a rebuild
the country really is on HeiGIT's 200/day. Pause it first if the rebuild is
planned.

**2. ~~Upload and submit build 6~~ — cleared review and live 2026-09-04.**
*(Bryce)* 1.0.1 build 6, carrying the 30-minute slider. Archived 2026-09-02,
submitted 2026-09-03, live 2026-09-04.

**The iPad precaution worked.** The 30-minute row was verified on an iPad Air
11-inch simulator before submission — four ticks spacing evenly, "30 minutes"
fitting at 46pt as the longest spoken label, Generate staying visible — and this
is the first update to pass without a device-specific complaint. Two clean passes
in a row. **Keep doing it**; every review that ever named a device used an iPad.

**Test iPad before assuming this one passes.** Every review that named a device
used an iPad, and two of four rejections were the Generate button clipped out of
the iPhone compatibility window. The 30-minute row was verified on an iPad Air
11-inch simulator — four ticks space evenly, "30 minutes" is the longest spoken
label and fits at 46pt, Generate stays visible — so the known risk is covered.
The unknown is whatever a fifth reviewer does next.

**3. ~~Persist the swapfile~~ — done 2026-09-03.** It was added mid-build and
would have vanished on the next reboot, taking with it the thing that kept the
OOM killer away: peak container memory during the US build was 11,295 MiB
against 11,927 MiB of RAM.

- `/etc/fstab`: `/swapfile none swap sw,nofail 0 0`. **`nofail` is deliberate**
  — a routing box that will not boot is a far worse failure than one without
  swap, and a damaged swapfile should never be able to cause that.
- `/etc/sysctl.d/99-aimless-swap.conf`: `vm.swappiness = 10`. Low on purpose.
  Swap here is a floor under an OOM kill, not working memory, and the default of
  60 would trade away page cache that ORS actively needs — the 15 GB graph is
  served via MMAP, so the page cache *is* the performance.
- `/etc/fstab.bak-2026-09-03` is the backup.

**Proven without rebooting**, which is the part worth copying next time: `sudo
swapoff /swapfile` then `sudo swapon --all` re-enabled it *from fstab*, which is
the same path boot takes. `findmnt --verify` passed first. Do not settle for
having written the line — a wrong fstab entry is discovered at the worst
possible moment otherwise.

**4. ~~"What's New" text~~ — done 2026-09-03**, implicitly: Apple does not
accept an update without it, and build 6 is live. **1.0.2 needed fresh text and
got it** on 2026-09-04 — it is per-version, not written once. Every future build
needs its own.

**5. ~~Cloudflare Access~~ — done 2026-09-03.** Enforcing on
`ors.workdocks.com` via service token `aimless-worker`, policy `worker-only`,
action **Service Auth**.

Verified after saving: an anonymous request to the hostname now returns **403
from Cloudflare Access** rather than from nginx, so it never crosses the tunnel;
the Worker's health probe still reads `state: ok`; and Denver, Marlboro and
Dallas still route `self`.

**Use "Service Token", not "Any Access Service Token", in the include rule.**
The latter matches every non-expired token in the account, so any future token
created for something unrelated would also get free routing on the box. Same
behaviour today with one token, wrong the moment there are two.

The gain is narrower than it sounds and still worth it: rejection moved to
Cloudflare's edge, where before an attacker's request crossed the tunnel and was
refused by nginx *on our own two cores*. The credential is also now rotatable
and auditable, where `SELF_HOSTED_TOKEN` is static and nothing logs attempts.

**6. ~~Test the health alarm~~ — done 2026-09-03.** Verified against a real
outage rather than by reasoning. Container stopped 03:13:31Z, auto-restored
03:20:33Z by a detached timer armed in the same command, so the box could not be
left down if the session died.

| | |
|---|---|
| Health endpoint while down | `{"ok":false,"state":"down","upstreamStatus":502}`, HTTP 503 |
| App during the outage | HTTP 200, `served-by: heigit` — users unaffected |
| Recovery | `state: ok` at 43 ms, container healthy |
| Alert | down **and** recovery emails both received by Bryce |

So the whole chain is proven end to end: the box failing, the endpoint noticing,
the monitor detecting, and a message arriving. No link in it is assumed.

**The outage exposed how thin the fallback is.** HeiGIT read
`x-ratelimit-remaining: 33` of 200 during it, down from 156 that afternoon. The
fallback is not a safety net that lasts — at ~18 requests per generate it is
roughly two generates of grace. If the box dies on a Saturday morning, HeiGIT
buys minutes, not hours. That is the argument for the monitor mattering.

**7. ~~Delete the stray `imless` Worker~~ — done 2026-09-03.** Gone; the
hostname 404s and `aimless-routing` is unaffected. The local
`wrangler.jsonc.stray-*` is deleted too, and both it and any future one are
gitignored.

**How it happened, because the trap is easy to re-enter:** `npx wrangler deploy`
run from the repo root instead of `worker/` finds no config, so wrangler writes
one and deploys whatever it infers — here `docs/` as a Worker named after the
directory. Always deploy from `worker/`.

**8. Reclaim the last 2.4 GB — the wait is over; now purely optional.**
`graphs.with-elevation` was deleted on 2026-09-03 (2.5 GB, the Aug 30 NJ+CA
graph with elevation on, superseded by `graphs.nj-ca`). What remains is
`graphs.nj-ca` itself, which is **the rollback**: a two-minute restore to the
two-state configuration that has been serving since 2026-08-30, if anything
about the US graph turns out to be wrong.

~~Delete it once the US graph has a few days of real use behind it.~~ **That
condition is met as of 2026-09-09** — six days of the whole US on the new graph
with no routing complaint, no rollback, and the app shipping two releases on top
of it. Verified the same day: `graphs` 15 GB serving, `graphs.nj-ca` 2.4 GB idle,
ORS `{"status":"ready"}`, box up 21 days, load 0.00.

**Still not urgent, and that is the honest read.** Disk is 95 GB free at 35%
used, so the 2.4 GB buys nothing back that anyone needs. Delete it when you want
the tidiness, keep it if you want the two-minute rollback. `rm -rf
~/selfhost/graphs.nj-ca` is the whole operation, and **the rollback it protects
is only reachable while the NJ+CA graph exists** — rebuilding one costs 40
minutes, against 6h40m for the US graph.

**9. ~~Explain the `round_trip` failure near large water~~ — done 2026-09-03.**
**It is requested loop size, not location**, and it is geometry rather than a
bug. Success by requested length, five seeds each:

| Origin | 6.5 km | 15 km | 33 km | 50 km |
|---|---|---|---|---|
| Denver (inland) | 5/5 | 5/5 | 5/5 | 5/5 |
| Chicago | 5/5 | 3/5 | 2/5 | 1/5 |
| Honolulu | 3/5 | 4/5 | 0/5 | 2/5 |

Denver is flat at every size. The coastal origins fall away as the loop grows,
because the generator places waypoints on a ring whose radius scales with the
requested distance, and a coastal origin has roughly half a circle of usable
land. Bigger loop, more of the ring in water.

**Three explanations tested and eliminated, so nobody repeats them:**

- *Not snapping.* Every coordinate reported as "could not find a valid point"
  routes fine as a point-to-point start — Chicago 41.912,-87.625, Detroit
  42.369,-82.942, Honolulu 21.354,-157.813, all OK.
- *Not missing roads.* Point-to-point works throughout all three cities.
- *Not `maximum_snapping_radius`.* Raised from the 400 m default to 3,000 m and
  restarted: Chicago 5/10, Honolulu 0/10, NJ 10/10 — identical. Reverted.

**The error message misleads and it is worth knowing why.** ORS reports the last
of three retries, and each retry pulls the point back toward the origin, so the
coordinate printed is usually dry land in a dense city even though the original
attempt was over water.

**Product consequence:** the 30-minute option added on 2026-09-02 (6,500 m)
works everywhere — Chicago 5/5, Honolulu 3/5. Failures concentrate in the 60,
90 and 120 minute sizes. A Honolulu user asking for a two-hour back-road loop is
asking for something a 44 km wide island cannot geometrically provide, and no
routing backend fixes that.

**10. ~~Alaska region box~~ — done 2026-09-03, and Hawaii with it.**
`SELF_HOSTED_REGIONS` now ends `,ak,hi`; deployed as version `d9861788`.
Verified: Anchorage, Fairbanks and Honolulu all return `self` at the 30-minute
size.

**The earlier reasoning for excluding them was wrong.** Both were left on HeiGIT
because our graph does badly there — Honolulu 0/10 at 33 km, Anchorage 2/5 —
with the note that "no retry rescues a zero." That treated it as a choice
between our box and HeiGIT, and it is not one: `trySelfHosted` returns null on
any non-200 and falls through to HeiGIT. **Adding a region can only add
successes.** Whatever our graph fails, the user gets exactly today's behaviour.

Measured at the app's four real request sizes, six seeds each:

| Origin | 6,500 m (30 min) | 33,000 (60) | 70,000 (90) | 85,000 (120) |
|---|---|---|---|---|
| Anchorage | **6/6** | 2/6 | 0/6 | 0/6 |
| Fairbanks | **6/6** | 1/6 | 0/6 | 0/6 |
| Juneau | **6/6** | 0/6 | 0/6 | 0/6 |
| Honolulu | **3/6** | 0/6 | 0/6 | 0/6 |

So both regions gain a working 30-minute option and lose nothing. The only cost
is a doubled upstream call on the sizes that fail, which is latency and no
quota, because our box has no limit.

`ak` stops at -142.3, about 65 km inside the -141 meridian border with Canada,
so the south-east panhandle is outside on purpose — Juneau is ~40 km from
British Columbia and its road network is isolated regardless. `hi` needs no
inset; it is ocean on every side.

**11. ~~Correct `selfhost/README.md` on build memory~~ — done 2026-09-03.** The
file claimed "heap does not scale" in bold. True from 0.16 GB to 0.98 GB, false
at country scale: 1.96 GB became 8,021 MiB against an 8,192 MiB ceiling. The
15% rule predicted 5.0-5.7 GB for the US and was wrong by ~2.5 GB in the
direction that kills a build. Now carries both tables and says to budget for
heap, disk and time.

**12. ~~Clean up the stale "What is left" list~~ — done 2026-09-03.** All three
items had shipped while the list still read as open — the exact failure this
file exists to prevent. Rewritten as history rather than deleted, since each
carries a fact worth keeping, including that the `/ors` suffix on
`SELF_HOSTED_ORIGIN` fails silently when omitted.

## Widening to the whole country — in flight 2026-09-03

**Started, not finished.** Written down before the long step rather than after,
because the session that did the prep work died mid-run and everything it had
learned went with it.

### What the overnight session of 2026-09-03 actually did

At 01:04 elevation was turned off, `REBUILD_GRAPHS` was flipped to `"True"`, a
memory sampler was started, and the graph rebuilt 01:11 → 01:51. **Coverage did
not change.** `fetch.log` reads "reusing" for both inputs, so it rebuilt the
same NJ+CA `coverage.osm.pbf` from 2026-08-30.

It was a measurement, and a useful one:

| | Peak heap | Peak container | Build time |
|---|---|---|---|
| Elevation on (2026-08-30) | — | — | 48m14s |
| Elevation off (2026-09-03) | **4,354 MiB** | 5,605 MiB | ~40 min |

Against `XMX: 8g` and 11 GB of RAM. That headroom is what makes a country-sized
extract affordable, which is what the prep was for.

**A whole-US graph was believed to exist after that session and did not.** The
misread is worth recording because it is an easy one to repeat. The build log's
flush line reads:

```
bounds: -124.4005403, -71.8582973, 32.4951871, 45.0621982
```

Pacific coast to eastern Long Island — which reads as coast-to-coast, and is
not. It is the bounding box of **two disjoint extracts**, California and the
northeast bundle. The box of a union is not the union; everything between
Nevada and Pennsylvania was empty. Node and edge counts are the honest check:
9,097,006 and 11,487,713, which is a two-state graph.

### Two things that session left behind

- **`REBUILD_GRAPHS` was left `"True"`.** Any container restart would have
  triggered a full rebuild with the box out of service. Set back to `"False"`
  on 2026-09-03. DEPLOY.md already says to do this; it just did not happen.
- **`elevation: false` existed only on the box.** DEPLOY.md's widening
  procedure *starts* with an `rsync` of `selfhost/`, which would have pushed the
  repo's config back over it and silently re-enabled elevation on the next
  build. Now committed to `selfhost/ors-config.yml`, so the two agree.

### Elevation stays off

Decided 2026-09-03. Nothing in the app reads it — loops are ranked on duration
and highway share, and grade is not an input to either. It costs 8 minutes of
build time on two states, and it drags an SRTM tile download into the build:
the cache is already **6.2 GB for NJ+CA**, and US-wide that is hours of fetching
from S3 in the middle of an already long build. Turn it back on only if
something starts needing gradient.

### The build

`fetch-extract.sh` now takes a `COVERAGE` mode. `us` is the default and is
**simpler than the two-state path, not just bigger** — one Geofabrik file means
no `osmium merge` and no duplicate-relation dedupe, which is both of the failure
modes that cost the 2026-08-30 session. The complete-ways check still runs,
because that one is about whether the file itself is sound. `COVERAGE=nj-ca`
keeps the old behaviour as a rollback.

| | Now | Whole US |
|---|---|---|
| Extract | 2.3 GB | **11.28 GB** |
| Graph | 2.4 GB | ~12 GB estimated |
| Build | ~40 min | **3.5-6 hours estimated** |
| Peak heap | 4,354 MiB | 5.0-5.7 GB estimated, against 8 GB |

**Heap is the number that can kill it, and it is the one that is extrapolated
rather than measured.** `selfhost/README.md` records that six times the map cost
15% more heap, which is where the estimate comes from, but that was measured
across much smaller files. The graph currently serving is preserved before the
rebuild starts, so a failure costs hours and not coverage.

### Extract fetched and verified 2026-09-03 15:35Z

`us-latest.osm.pbf`, **12,116,008,404 bytes**, Geofabrik replication timestamp
2026-08-31T20:21:20Z. `osmium check-refs -r` reports complete ways, so the file
is sound in the one way that killed two builds on 2026-08-30.

`data/coverage.osm.pbf` is a **hard link** to `data/us.osm.pbf` — same inode
`524394`, link count 2 — rather than a copy, which is what keeps a second 11 GB
off the disk. That inode equality is also the check worth repeating before any
build: `fetch-extract.sh` runs under `set -e`, so a failed verification leaves
the *old* 2.3 GB two-state file sitting at that path, and building from it would
silently produce the graph you already have after hours of work.

**The header carries no bounding box**, so at this point whether Alaska and
Hawaii were in the file was unconfirmed — `osmium fileinfo -e` would answer it
but reads all 12 GB. **Asking the finished graph was the cheaper test, and it
came back yes**: graph bounds `-178.09, 174.15, 18.91, 71.36`. See "The build
finished" below. Use that trick rather than scanning the extract.

### Build started 2026-09-03 15:41Z

Box taken out of service at 15:41:04Z; NJ and CA fall back to HeiGIT until it
returns, so they are slower and spending quota rather than broken. The serving
graph was preserved as `graphs.nj-ca` (2.4 GB) first. Disk at start: 116 GB free
of 145 GB. `REBUILD_GRAPHS` armed to `"True"`, container up 15:41:35Z, and the
log confirms `Elevation deactivated`.

`sample-build-mem.sh` is running against this build, so the peak-heap figure
that the whole estimate rests on will be measured rather than extrapolated when
it lands. **Put `REBUILD_GRAPHS` back to `"False"` when it finishes** — left
armed, every future restart rebuilds from scratch, which is exactly what the
overnight session left behind.

Disk on the box is no longer a constraint: the volume is **145 GB**, and it had
121 GB free at this point in the build. An older 48 GB figure was carried
somewhere in this file and is simply wrong — it has since been removed, so
**this line is the reference.** Measured again 2026-09-03 after the build:
**96 GB free, 35% used**, holding the 15 GB US graph and the 2.4 GB rollback.

Note this is the *Oracle box*. The disk constraint under "Environment" is a
different machine — the Mac — and that one is still real.

### The build finished 2026-09-03 22:21Z — 6h40m

**It worked, and it nearly did not fit.**

| | NJ+CA | Whole US |
|---|---|---|
| Extract | 2.3 GB | 11.28 GB |
| Graph | 2.4 GB | **15 GB** |
| Nodes | 9,097,006 | **55,953,477** |
| Edges | 11,487,713 | **70,387,384** |
| Build | 40 min | **400 min** |
| Peak heap | 4,354 MiB | **8,021 MiB of 8,192** |

**171 MiB of heap headroom.** The estimate of 5.0-5.7 GB was wrong and so is the
rule it came from — `selfhost/README.md` says six times the map cost 15% more
heap, and that does not hold at this size. Peak *container* memory hit 11,295
MiB against 11,927 MiB of physical RAM, so **the 8 GB swapfile added mid-build
is what kept the OOM killer away**. Do not attempt this size again without it.

Scaling is superlinear where it hurts. Nodes and edges grew 6.1x; `PrepareCore`
grew 8.1x, from 284s to 2,289s. The four landmark sets took 46, 46, 60 and ~60
minutes against roughly 6 minutes each before. Both phases are single-threaded
by config (`core.threads: 1`, `lm.threads: 1`) on two Ampere cores.

**Alaska and Hawaii are in it.** Graph bounds are
`-178.09, 174.15, 18.91, 71.36` — the longitude range crosses the antimeridian
because of the Aleutians, and 18.91°N is the south point of the island of
Hawaii. That settles the question the PBF header could not.

**Restarting is now cheap: 20 seconds** to load the 15 GB graph over MMAP, once
`REBUILD_GRAPHS` is `"False"`. It is back to `"False"` as of 22:2xZ.

### Where the new graph is worse than HeiGIT, measured

**Do not widen the Worker on the assumption that a bigger graph is uniformly
better. It is not.** Same seeds, same request, `round_trip` at 33 km:

| Origin | Our US graph | HeiGIT |
|---|---|---|
| Marlboro NJ | 10/10 | — |
| Denver CO | 10/10 | — |
| Austin TX | 10/10 | — |
| Cupertino CA | 9/10 | — |
| **Chicago IL** | **5/10** | **5/5** |
| **Honolulu HI** | **0/10** | **4/5** |

**The graph is not missing those roads.** Point-to-point routing succeeds in
both places — Honolulu→Kaneohe 10.8 mi, Honolulu→Kailua 11.9 mi,
Chicago→Evanston 13.4 mi, Chicago→Naperville 30.4 mi. Only `round_trip` fails,
with `code 2099, "Could not find a valid point after 3 tries"`. That error is
the round-trip generator throwing a waypoint somewhere it cannot snap.

**`maximum_snapping_radius` was the obvious hypothesis and it is wrong.** Ours
was unset, so the ORS default of 400 m applied. Raising it to 3,000 m and
restarting changed nothing at all: Chicago 5/10, Honolulu 0/10, NJ 10/10 —
identical. Reverted. Do not spend time on it again.

The pattern is large adjacent water: Lake Michigan for Chicago, the Pacific for
an island 44 km wide. It is not simple coastline, because Seattle and Cupertino
are fine. The mechanism is still unexplained.

**What it means for the app is not symmetrical with what it means per request.**
A generate fires 12 seeds and needs 3 survivors, then filters on duration. At
5/10 Chicago is degraded but a retry round is *free* on our box and rationed on
HeiGIT, so we may still be ahead there. At 0/10 no amount of retrying helps, so
**Hawaii must stay on HeiGIT.**

### The Worker is widened and live — 2026-09-03

Deployed version `a7ca9cee-5434-4292-852f-ea9e500b7d1d`.
`SELF_HOSTED_REGIONS = "nj,ca,us_north,us_southeast,us_texas,us_southwest"`.

**A single bounding box cannot express the country**, because the inset that
keeps a loop away from a graph edge has to apply in the north and the south-west
and nowhere else. One `minLat` inset from Mexico would cut Miami, 1,900 km away.
Six boxes, four of them new:

| Box | Covers | Inset from |
|---|---|---|
| `us_north` | above 33.5°N, coast to coast, capped 48.4°N | Canada by ~65 km; Mexico by ~87 km |
| `us_southeast` | below 33.5°N, east of -96.0 — Florida, Gulf, east Texas | Rio Grande by ~114 km |
| `us_texas` | -98.8 to -96.0, 28.5-33.5°N — Dallas, Austin, San Antonio | Laredo by ~130 km |
| `us_southwest` | -114.5 to -109.1, 32.1-33.5°N — Phoenix, Tucson | Sonora by ~85 km |
| `nj`, `ca` | now subsets of `us_north` | kept so rollback to the proven pair is one setting |

`nj` and `ca` being redundant is deliberate. Reverting to `"nj,ca"` restores
exactly the configuration that has been serving since 2026-08-30.

**Verified through the live Worker**: Marlboro NJ, Cupertino, Denver, Austin,
Dallas, Phoenix, Miami, Seattle and Boston all return
`x-aimless-served-by: self`. Honolulu and San Diego return `heigit`, which is
correct — both are deliberately outside every box.

**`heigit` in a single response does not mean the region is off.** Chicago
returned `self` twice and `heigit` three times across five seeds. That is the
fallback working exactly as designed: our box fails a seed, the Worker retries
HeiGIT, and the user still gets a route. Seattle looked like a region miss on
one sample and came back 5/5 `self` on five. **Always test a region with several
seeds before concluding it is not covered.**

### Two corrections to earlier reasoning in this file

- **Water borders are not graph edges.** Detroit sits 37 km from Canada and
  Buffalo 16 km, both inside the 65 km rule, and both are fine — the border
  there is the Detroit and Niagara rivers, where the US road network genuinely
  ends. Measured: Detroit 4/8 and Buffalo 3/8 on `round_trip`, but the loops
  that succeed average 45.3 km and 42.6 km against 33 km requested, next to
  Denver's 40.3 km. **Not clipped short**, which is the hazard the inset exists
  to prevent. The inset is only needed where roads cross continuously — the 49th
  parallel, and the Maine and Vermont land borders.
- **The Great Lakes degrade `round_trip`, and it is survivable.** Chicago 5/10,
  Detroit 4/8, Buffalo 3/8 against 10/10 inland. Routing them to us anyway is a
  decision, taken 2026-09-03: worse per request, but a retry round is free here
  and rationed at 200/day on HeiGIT, so a user near a lake gets more successful
  generates from the degraded graph than from the good one they are allowed ten
  of. Hawaii is the exception, because no retry rescues 0/10.

### What was still to do here — all three closed 2026-09-03

Kept as history rather than deleted. Each is written up in full under its
checklist number; this list only says where it went.

- **Alaska** — done, task 10. It was 2/5 with no box and reasoned to be not
  worth adding. That reasoning was wrong: the Worker falls through to HeiGIT on
  any non-200, so adding a region can only add successes. `ak` and `hi` are both
  live. The road-sparsity finding stands and HeiGIT shares it — a 33 km request
  near Anchorage still returns a six-hour loop.
- **The `round_trip` failure near large water** — explained, task 9. It is
  requested loop size, not location, and it is geometry rather than a bug: the
  generator places waypoints on a ring that scales with the request, and a
  coastal origin has roughly half a circle of usable land. Snapping radius was
  tested and disproved; do not spend time on it again.
- **Cloudflare Access** — done, task 5. Enforcing via service token
  `aimless-worker`. The exposure it closed was also overstated in this file: the
  nginx gate always held. See "What was left" below, whose items 1 and 3 were
  done on 2026-08-20 and should be read as history.

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
with Brycepercoco@gmail.com on it. **The Support URL in App Store Connect was
updated to point there on 2026-08-19.**

### A fix that was proposed and dropped

Cutting `seedsPerRound` from 12 looked obvious and the measurements killed it.
In-band survival is **62% at 60 minutes, 38% at 90, 29% at 2 hours** — so six
seeds leaves only two survivors on both longer options, below `desiredCount`,
which fires the retry round and costs *another* twelve requests. Even eight
seeds lands exactly on three with no margin and saves just four requests,
because the six verification reroutes are fixed. **12 is right; leave it.**

## Rejected a third time 2026-08-23, and what fixed it

Guideline 2.1(a): **"nothing happened when we tapped on generate."** Reviewed on
an **iPad Air (5th generation), iPadOS 26.6.1**. Submission ID
`0cd7fabf-eade-4dfa-a6a9-ce413df95702`.

**This one was a real code defect** — the first of the three. It needed a new
binary, which the previous two did not.

Reproduced on 2026-08-23. Three causes, stacked:

1. **The Generate button was clipped off the bottom of the window.**
   `TARGETED_DEVICE_FAMILY = 1`, so on iPad the app runs in an iPhone
   compatibility window *shorter than any iPhone screen*. `GenerateView` used a
   fixed `VStack` with a 240pt floor under the map and no scroll view. Add a
   two-line location status message plus its recovery link and the content
   overflowed — title clipped off the top, Generate clipped off the bottom. The
   reviewer tapped what was left of a disabled button.

2. **A disabled button with no tap feedback.** `.disabled(!location.isUsable
   || model.isGenerating)` meant a tap without a fix did nothing whatsoever —
   no alert, no message, no state change. Indistinguishable from a broken app,
   and filed as one.

3. **A permanent `.locating` deadlock in `LocationProvider`.** `requestFix()`
   set `.locating` unconditionally; `didFailWithError` only escaped to
   `.failed` when `current == nil`. So any failed refresh *after* a good fix
   pinned the status at `.locating` forever — button disabled, "Finding you..."
   on screen, and `.locating` renders no recovery control. Force-quit was the
   only way out. `scenePhase` calls `start()` on every foreground, so this
   fires constantly.

Why iPad and not iPhone: **Wi-Fi-only iPads have no GPS receiver.** Location is
inferred from a Wi-Fi network database or the public IP, so failed refreshes
are routine there. Checked against Apple's documentation, not assumed.

Ruled out first: the Worker was healthy throughout — 200 in 1.28s,
`x-aimless-served-by: heigit`, 1959/2000 rate budget remaining. Not a repeat of
the round-two rate limit. The full happy path also works on iPad: driven with
`-autoGenerate` it produced 2 loops at 71 min / 23 mi / 8% highway.

### The fixes, all in 1.0 (4)

- **Action bar moved to `.safeAreaInset(edge: .bottom)`.** It reserves its
  space before the map and picker get any, so no combination of status text and
  window height can clip it. Map floor dropped 240pt to 150pt.
- **Generate is disabled only while a generate is already running.** Tapping it
  without a fix now retries the location request *and* raises an alert saying
  why, with an "Open Settings" button when permission is the cause.
- **`didFailWithError` always leaves `.locating`** — `.failed` with no fix,
  back to `.ready` if one is already in hand. `requestFix()` no longer drops a
  good fix to `.locating` on foreground, so the button stays live during a
  refresh.

Verified on iPad: the denied-permission state now renders complete with margin
to spare, and the happy path still produces the same 2 loops. Release
configuration compiles — worth checking specifically, because the
`-autoGenerate` hook is `#if DEBUG` and Release takes a different path through
`generate()`.

**The attribution string ships in this build**, as planned.

### Test iPad before every submission

**Every review that named a device used an iPad** — an iPad Air 11-inch (M3) on
2026-08-19, an iPad Air (5th generation) on 2026-08-23. Never an iPhone. Device
testing here has been iPhone Air on hardware, which is exactly why this
shipped. The defect does not reproduce on iPhone at any size.

### The verification claim, if Apple asks

The reply as sent says the fix was confirmed "on an iPad running iPadOS 26".
What was actually tested is an **iPad Air 11-inch (M4) simulator on the iPadOS
26.4 runtime** — not physical hardware, and not the 26.6.1 the reviewer used.
The wording is true but non-specific, and Apple's rejection did say "test the
app on supported devices".

**If they push back on it, answer precisely rather than restating it.** The
honest position is a strong one: the fault is a layout overflow that depends on
window height, not on hardware, and it reproduces and resolves identically in
the simulator. Say so plainly and name the configuration.

No physical iPad was available. The newest runtime installed is 26.5, so
testing closer to the review configuration means downloading the iPadOS 26.6
runtime first (~8-10 GB, and see the disk note in Environment).

## Rejected a fourth time 2026-08-27, and what fixed it

Guideline 2.1(a): **"nothing happened when we tapped on generate"**, word for
word the third rejection. **iPad Air 11-inch (M3), iPadOS 26.6.1**, build
1.0 (4), submission `0cd7fabf-eade-4dfa-a6a9-ce413df95702`.

**The 1.0 (4) layout fix held.** Verified the same day on an iPad Air simulator:
the button is fully visible in every location state, and the whole happy path
works from Apple's own coordinates — 12/12 candidates, three loops, 77 min /
24 mi / 7% highway from Cupertino. The clipping is genuinely gone.

Two other things were wrong, and either one produces the reported symptom.

### 1. The alert never appeared, and the button latched silent

`GenerateView.generate()` raised its "Can't generate yet" alert by setting a
`@State` **Bool** and letting `.alert(isPresented:)` present it. Two failures
compounded:

- SwiftUI **silently discards** an alert presentation while something else is
  presenting. The system location permission prompt is presenting for exactly
  the first seconds of the first launch, which is when a reviewer taps.
- The flag then stayed `true`. Every later tap assigned `true` to a `true`
  variable, which is not a state *change*, so SwiftUI was never asked to
  present anything again. **The button was silent for the life of the screen.**

Reproduced, not inferred. Four synthetic taps over 20 s on the iPad Air
simulator, in two configurations (permission undecided, permission revoked):
`blocked=true` from the first tap onward, and no alert on screen at any point.

**Fixed by not using a presentation at all.** The state is now an optional
`BlockNote?` — a fresh value per tap, so it cannot latch — and it renders as an
inline callout above the button, which draws underneath a system alert instead
of losing to it.

**And by making the tap mean something.** A tap without a fix now *queues* the
generate: the button changes to a "Finding you..." spinner and the generate
fires by itself the moment the fix lands, with a 15-second backstop that falls
back to an explicit error and a Try Again. On a Wi-Fi-only iPad, where a fix
takes seconds and the reviewer taps immediately, this turns the exact reported
scenario into a result. Verified on the simulator: tapped with the permission
prompt still up, and it produced three loops.

### 2. HeiGIT cut the daily quota from 2000 to 200

Measured 2026-08-27 against the live Worker: `x-ratelimit-limit: 200`. On
2026-08-23 the same header read 2000. Nothing on our side changed it.

At 18-36 requests per generate that is **five to ten generates per day for every
install combined**. Two generates during testing took the remaining budget from
153 to 77 in twelve minutes. When it runs out every seed fails, and the app said
"Couldn't build any loops from here" in one grey line the same weight as the
picker caption — which is also fairly described as nothing happening.

Three changes, in increasing order of how much they actually help:

- `ORSHTTPError.isRateLimit` now covers **403 as well as 429**, so a quota
  refusal reads as "come back later" instead of blaming the user's geography.
- Errors from a failed generate now render in the same loud callout as
  everything else, instead of a grey line.
- **California is being added to the self-hosted graph.** Every review so far
  has been near Cupertino and every one of those generates went to HeiGIT. See
  `selfhost/DEPLOY.md`, "Widening coverage" — build the graph first, widen
  `SELF_HOSTED_REGIONS` second.

### 3. The Worker had no logs, which is why round four was inference

`worker/wrangler.toml` had no `[observability]` block, so there was no record of
whether the review device ever reached the Worker or what it was told. Now
enabled at `head_sampling_rate = 1`, with one structured line per request:
status, cache hit/miss, which backend answered, and the remaining upstream
quota. **No coordinates** — `PRIVACY.md` promises the Worker does not store
them, and it now describes this logging explicitly.

### All of this was done on 2026-08-30, in this order

1. **California graph built and serving.** Took three attempts and about four
   hours; the two failures are worth reading before touching the extract again,
   and they are written up in `selfhost/DEPLOY.md` under "Widening coverage".
   Short version: Geofabrik was down, the mirror substituted for it clips
   without complete ways, and GraphHopper rejects such a file after four
   minutes without naming a cause. `fetch-extract.sh` now checks for that, and
   for the duplicate-relation problem that a version skew between two extracts
   creates. Final build: 48m14s, 4.85 GB peak against an 8 GB heap, 2.5 GB
   graph.
2. **Worker widened.** `SELF_HOSTED_REGIONS = "nj,ca"`, deployed and verified
   from outside with fresh seeds: Cupertino, Los Angeles, Sacramento and
   Marlboro NJ all return `X-Aimless-Served-By: self`; Chicago and San Diego
   return `heigit`. San Diego is outside the served box on purpose — it sits
   22 km from the Mexican border, inside the clipping distance.
3. **Build 1.0 (5) archived and uploaded**, and attached to the 1.0 version
   record.
4. **Reply sent**, after the above rather than before, because it tells Apple
   routing for their region now runs on our own infrastructure. That became
   true at step 2 and not a moment earlier.

~~The New Jersey rollback graph is still on the box at
`~/selfhost/graphs.nj-only` (1.3 GB). Delete it once California has been serving
for a few days without complaint.~~ **Done, and verified gone 2026-09-03** —
`~/selfhost` now holds only `graphs` (15 GB, the US graph in service) and
`graphs.nj-ca` (2.4 GB, the current rollback, task 8). California served without
complaint, so the plan above was followed through.

### App Store Connect field limits, both learned the hard way

Two different fields, two different caps, and neither is documented where you
are typing:

- **Reply to App Review: 4,000 characters.** `store/review-reply-4.txt` was
  written at 4,370 and had to be cut on the spot. It is now 3,920.
- **Review notes** are much tighter — that is what the 2026-08-14 round hit.

Write to fit rather than trimming under time pressure. `wc -m` before pasting.

## Pre-submission checklist

Written 2026-09-04, before tasks 13-15 are built, and derived from **what
actually caused the four rejections** rather than from general good practice.

### The pattern in the four rejections

**Not one of them was routing or geometry.** Every single one was UI state, or
the server, or store metadata:

| # | Cause | Layer |
|---|---|---|
| 1 | Missing docs and screen recording | Process |
| 2 | HeiGIT rate limit surfaced as an error; Support URL had no contact address | Server + store metadata |
| 3 | Generate clipped off an iPad window; disabled button gave no feedback; `.locating` deadlock | **UI state** |
| 4 | Alert silently discarded and then latched; HeiGIT cut the quota to 200/day | **UI state** + server |

That is good news for 13-15, whose *maths* lives in the layer that has never
once been rejected. It is bad news for their *controls*, which live in the layer
that has been rejected three times.

### The two ways tasks 13-15 could earn a fifth rejection

1. **A filter that returns nothing.** Retrace filtering is a new way for the app
   to show zero loops, and "nothing happened when we tapped on generate" is the
   verbatim sentence from rejections three *and* four. **Rule: neither filter
   may ever produce an empty result.** On empty, fall back to the best available
   loops with the stat displayed. A slightly retraced loop shown honestly beats
   an empty screen every time.
2. **A button that appears dead.** The reverse control fires a network request on
   tap. If it is slow, silent or latches, that is rejection 3 cause 2 and
   rejection 4 cause 1 happening again. **It must show a spinner within one
   frame of the tap, and it must never disable itself without saying why** —
   the same lesson the `BlockNote?` optional taught, which is that a fresh value
   per tap cannot latch where a `Bool` can.

### What can actually be tested, given there is no test target

`Aimless.xcodeproj` is hand-written with one target and **no test target**, so
XCTest would mean editing the fragile project file. Not required — the new work
is pure functions.

- **Geometry, outside Xcode — built and passing as of 2026-09-04.**
  `tools/geometry-check/run.sh` compiles `Aimless/Services/Geometry.swift` with
  `swiftc` against `main.swift` and asserts. Runs in seconds, **touches no Xcode
  project file.**
- **Cross-checked against the Python, and they agree.** 56 real ORS routes,
  49,582 points, fixtures in `tools/geometry-check/fixtures.json`:

  | | |
  |---|---|
  | Max Δ retrace | **0.00005 pp** (tolerance 0.01) |
  | Max Δ curviness | **0.00005 deg/mi** (tolerance 0.05) |
  | Synthetic out-and-back | 99.2% retrace (expect ~100) |
  | Synthetic straight line | 0.000 deg/mi, 0.0% retrace |

  Two independent implementations in different languages agreeing to five
  decimal places on real routes is a far stronger check than hand-written
  fixtures. **Regenerate fixtures with `tools/measure-geometry.py` on the box**
  if the pipeline ever changes.
- **Degenerate inputs are asserted, not assumed** — empty, single-point and
  all-identical polylines must return 0 rather than trap. The retrace filter is
  a new path to an empty result, so the thing feeding it must not crash first.
- **The empty-result path specifically.** Force it: set the retrace threshold to
  0% and confirm the app still shows loops rather than an empty state. This is
  the single most important test in the list, because it is the rejection path.
- **`-autoGenerate -duration N`** already exists for screenshots and drives the
  app past the first screen without a tap.

### Before every submission, without exception

- **Test on an iPad.** Every review that named a device used one — iPad Air
  11-inch (M3) twice, iPad Air (5th gen) once, never an iPhone. The app is
  `TARGETED_DEVICE_FAMILY = 1`, so it runs in a compatibility window shorter
  than any iPhone screen, and that is what clipped Generate twice.
- **Check the four location states** on that iPad: permission undecided, denied,
  reduced accuracy, and a failed refresh after a good fix. Rejection 3 was
  hiding in the fourth.
- **Tap Generate immediately on first launch**, while the system permission
  prompt is still up. That is the exact moment rejection 4 lived in, and it is
  what a reviewer does.
- **Build the Release configuration**, not just Debug. `-autoGenerate` is
  `#if DEBUG`, so Release takes a different path through `generate()`.
- **Leave 2+ minutes between generates** when capturing anything, or the upstream
  limit trips and the screenshot catches a rate-limit message.

## Shipping updates — done once, and the pattern held

~~The next binary is 1.0.1 with a fresh build number.~~ **Shipped 2026-09-04, and
1.0.2 build 7 shipped 2026-09-09.** Apple requires the build's version string to
match the App Store Connect record, which is why the version could not be chosen
before the first approval landed. **The next one is 1.0.3**, carrying task 14.

**Bump both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`** in
`Aimless.xcodeproj/project.pbxproj` — two occurrences each, Debug and Release.
Apple rejects an upload that reuses a build number. Each release also needs its
own "What's New" text; it is per-version, not written once.

**Pushing a new build is safe, and this has now been done rather than reasoned
about.** A live app stays live while a new version is in review; users keep
downloading the current one, and the new version only replaces it on approval.
There is no window where the app disappears.

**Nothing on the ceiling problem needs a new binary.** Coverage is
`SELF_HOSTED_REGIONS` in the Worker and the graph on the Oracle box — both
server-side, both deployable without Apple. That division still holds and is
worth protecting: **spend a binary only on what genuinely lives in the app.**
Tasks 13-15 qualify, because filtering, map rendering and a new control cannot
be done from the server.

~~The first candidate is whatever the drive turns up.~~ There is no drive; that
was declined 2026-09-02. The candidates now come from measurement instead — see
"Retrace and reversal, measured 2026-09-04".

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

## The ceilings, in plain terms

Worth keeping because it gets re-derived every time. **There are two separate
limits, in different units, and they have nothing to do with each other.**

| | What it is | Limit | Fixed by |
|---|---|---|---|
| Cloudflare Worker | Our reverse proxy, hosted by Cloudflare | 100k requests/day = **~5,500 generates/day** | $5/month |
| Routing backend, per minute | Whoever computes the routes | HeiGIT: 40 req/min = **~2 generates/min** | Oracle box |
| Routing backend, per day | The same provider, separate counter | HeiGIT: 200 req/day = **~5-10 generates/day** | Oracle box |

One generate costs ~18 requests, or up to 36 with a retry round, which is where
all three conversions come from.

### Updated 2026-09-03, when the whole US moved to our own box

**The binding limit changed, and so did the advice about paying for it.**

**The Oracle row is no longer the constraint, and it is now measured** — the
number this file used to flag as the only guess. On the 15 GB US graph: twelve
concurrent round trips in **0.47-0.52 s**, single request **49-64 ms**. That is
~24 requests/second, or **roughly 80 generates per minute**. Note it got *faster*
than the two-state graph (0.73 s, 55-140 ms) despite being six times the map,
because MMAP keeps the graph off-heap and the page cache does the work.

**So the Cloudflare Worker is now what stops you**, at 100k requests/day:

> **100,000 ÷ 18 ≈ 5,500 generates/day ÷ 2 per user ≈ 2,750 users**

against roughly 5 users before, when everyone outside NJ and CA shared 200/day.
A hundred people generating twice on a Saturday morning is 3.3/minute against a
box that does 50-80. The old ceiling was 2/minute, which is exactly why that
hour was the failure case.

**Retracted: "paying Cloudflare $5 buys nothing."** That was true while HeiGIT's
200/day was the binding limit — the Worker's ceiling was unreachable behind it.
The box has now removed that constraint, so the Worker genuinely is the next
wall. The paid plan is 10M requests/month, about 333k/day, so **~18,500
generates/day or roughly 9,000 users**. Not needed yet. No longer pointless.

**HeiGIT is still being spent, and not only by the excluded regions.** Every
fallback costs quota. Chicago fails roughly half its seeds on our graph, so a
Chicago generate spends ~6 HeiGIT requests, which is **200 ÷ 6 ≈ 33 lakeside
generates/day** shared globally with Hawaii, Alaska and the border strips. "Free
retries" is true of retries against our own box and **not** of fallbacks. Inland
users spend no HeiGIT quota at all.

So the honest statement of the ceiling is still geographic, but the geography
inverted: **inside the served boxes the app supports thousands of users; outside
them, and in the Great Lakes fallback path, it is still tens of generates a
day.**

### The state before 2026-09-03, kept because it explains the numbers above

Both HeiGIT rows applied everywhere outside New Jersey and California. Those two
states were served by our own box from 2026-08-30; everyone else spent HeiGIT's
allowance, which read 2000/day on 2026-08-23 and 200/day on 2026-08-27, cut by
HeiGIT rather than by us.

Measured 2026-09-02, on approval day: still `x-ratelimit-limit: 200`, Marlboro
and Cupertino `self`, Chicago `heigit`. Outside the two states the app supported
single-digit generates per day across every install on earth — less than one App
Review pass consumes. That is the number the widening was done against.

## Oracle routing: live since 2026-08-20, carrying the whole US

Built 2026-08-19. **The box now serves every covered US region** — see "Widening
to the whole country" above for the current graph and "The Worker is widened and
live" for the six region boxes.

~~The box exists, serves correct routes, and is not yet carrying any traffic.~~
True only between 2026-08-19 and 2026-08-20, while `SELF_HOSTED_ORIGIN` was
unset. Kept because **the order it describes is the one to repeat**: prove the
backend first, then flip one secret. Rollback has been a single secret delete
ever since.

| | |
|---|---|
| Instance | `aimless-ors`, Oracle always-free |
| Shape | VM.Standard.A1.Flex, 2 OCPU / 12 GB, Ampere |
| OS | Ubuntu 24.04 aarch64 |
| Region | US East (Ashburn), AD-2 |
| Public IP | 129.213.20.151 |
| SSH | `ssh -i ~/.ssh/aimless_oracle ubuntu@129.213.20.151` |

**12 GB is the whole always-free allowance, confirmed 2026-09-03.** This box
consumes all of it, and three things follow that are easy to plan around
wrongly:

- **There is no resize.** The 8 GB heap ceiling is permanent, so the 171 MiB of
  headroom the US build finished with is a permanent fact and **the swapfile
  stays load-bearing forever.**
- **There is no second free instance**, so a hot spare has to be paid for or not
  exist. Today it does not exist.
- **`core.threads` and `lm.threads` stay at 1.** Two cores would genuinely help
  `PrepareCore` (2,289 s) and the ~3.5 hours of landmark sets, but parallel
  phases hold more in memory at once and there is no headroom to spend.

**Building a graph and serving one need different resources, and that is the way
out.** Building needs heap and cores; serving needs page cache, which is why a
15 GB graph serves comfortably on a 12 GB box and got *faster* than the
two-state one. So any future graph larger than the US should be **built on a
rented box for an afternoon and `rsync`ed here** — a few euros once, and it
sidesteps the ceiling entirely. Whether the result still *serves* well on 12 GB
is a separate question and a measurable one; the US graph suggests the hot
working set is far smaller than the file.

The **original** NJ-only graph built in 1742 s at 1.3 GB on disk, and was
verified against HeiGIT on eight seeds: within ~1% on duration and 0.6 points on
highway share. Those figures describe 2026-08-19, not what is serving now — the
current graph is the 15 GB US one. Full numbers and the build runbook are in
`selfhost/README.md` and `selfhost/DEPLOY.md`.

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

### What was left — all three done, kept as history

This list read as open until 2026-09-03 while every item had in fact shipped,
which is exactly the failure mode `HANDOFF.md` exists to prevent. Recorded as
history rather than deleted, because each one carries a fact worth keeping.

1. **Cloudflare Tunnel — done 2026-08-20.** It was blocked on owning a domain:
   named tunnels need a zone in the account, and quick tunnels are ephemeral and
   not for production. `workdocks.com` was bought at Cloudflare Registrar,
   roughly $10/year, and `ors.workdocks.com` has served through the tunnel since.
2. **Cloudflare Access with a service token — done 2026-09-03.** Enforcing via
   service token `aimless-worker`, policy `worker-only`, action Service Auth.
   ~~Without it the hostname is open routing for anyone who finds it.~~ **That
   was wrong and was measured wrong** — the nginx gate always held, refusing
   every unauthenticated request before it reached ORS. Access moved rejection
   to Cloudflare's edge and made the credential rotatable. Defence in depth, not
   a hole closed.
3. **Set `SELF_HOSTED_ORIGIN` — done 2026-08-20.** **The `/ors` suffix is
   mandatory and omitting it fails silently**, which is the part still worth
   knowing: every self-hosted attempt 404s, the Worker falls back to HeiGIT, and
   the app keeps working at HeiGIT's latency under HeiGIT's limit — the precise
   thing the box exists to escape. Verify with `X-Aimless-Served-By`.

Rollback is `wrangler secret delete SELF_HOSTED_ORIGIN` and a deploy. No app
change, no review.

### Access: both halves are live — the measurement is why it was worth doing

**Enforcing as of 2026-09-03** (task 5). This section is kept for the
measurement, not as an open item.

**The exposure was overstated in this file, and that is the part worth keeping.**
Tested 2026-09-03 against `ors.workdocks.com` with no credentials at all, *before*
Access was switched on:

| Request | Result |
|---|---|
| `GET /ors/v2/health` | **403** |
| `GET /ors/v2/directions/driving-car/geojson` | **403** |
| `GET /` | **403** |
| `POST` a real round-trip route | **403**, nginx, before ORS |

So it is a shared secret, not an open door. What Access actually buys is
narrower than "closing a hole" and still real:

- **Rejection moved to Cloudflare's edge.** Before Access, an attacker's request
  travelled the tunnel and was refused by nginx *on the box*, so it cost our CPU
  — a denial-of-service surface on two Ampere cores. It is now refused before it
  crosses the tunnel at all.
- **The credential became rotatable and auditable.** `SELF_HOSTED_TOKEN` is
  static, has never been rotated, and nothing logs attempts against it.

**The Worker half was deployed first, on purpose** (version `7c8656f6`).
`trySelfHosted` and the health probe both send `CF-Access-Client-Id` /
`CF-Access-Client-Secret` when both secrets exist, and send nothing when they do
not — so the deployed code was a no-op until the secrets were set, and there was
**no code change at the risky moment.** Copy that ordering for anything else that
gates live traffic. Verified after deploy: Denver and Marlboro still `self`,
health still `ok`.

The health probe sends the same credentials as real traffic **on purpose**. A
probe that authenticates differently would report the box healthy while every
real request was being refused, which is the one failure a monitor must not
have.

### Watch for

**Oracle reclaims idle always-free compute** — under ~20% utilisation across 7
days. A routing box for an app with no users is exactly that profile. The Worker
degrades to HeiGIT on a dead socket, so the failure mode is "slower", not
"broken". ~~Nothing currently notices or alerts.~~ **Something does now** —
UptimeRobot on `/health/selfhosted`, proven against a real outage, see tasks 1
and 6.

**A reclaim costs much more than it used to.** `tools/oracle-retry.sh` rebuilds
the instance and rotates availability domains until free ARM capacity appears
(Ashburn refused AD-1 and granted AD-2 on the first attempt), but the instance
was the cheap part. Rebuilding the graph on it is **6h40m**, and with 12 GB
being the entire allowance there is no larger box to do it on. Whatever replaces
this box should get the graph by `rsync` from a backup, not by rebuilding.

~~**Coverage is still the limit.** The graph holds NJ, PA, NY and DE, and the
Worker only routes New Jersey origins locally.~~ **Superseded 2026-09-03.** The
graph is the whole US and the Worker routes six region boxes plus `ak` and `hi`.
The reasoning underneath it still holds and is why the insets exist: a route
generated near a graph edge gets silently clipped. See "The Worker is widened and
live" for the boxes and their inset distances.

**The limit is now the Cloudflare Worker**, at 100k requests/day, and the
geography inverted — inside the boxes the app supports thousands of users;
outside them, and in the Great Lakes fallback path, it is still tens of generates
a day. See "The ceilings".

**Open question, not yet answered:** whether "v2" also means a paid Pro tier.
Unrelated work — StoreKit, subscriptions, a real App Review surface — and should
be planned separately.

## The app degrades where roads are sparse, and nothing says so

Measured 2026-08-20, one seed each at the 60-minute size. Coverage is worldwide
— OpenStreetMap via HeiGIT routes the whole planet, and the Oracle box is a
speed optimisation for New Jersey rather than a coverage boundary:

| Origin | Result |
|---|---|
| Austin TX | 95 min, 31 mi |
| Burlington VT | 109 min, 31 mi |
| Maui HI | 89 min, 28 mi |
| Scottish Highlands | 159 min, 44 mi |
| **Anchorage AK** | **397 min, 199 mi** |
| rural Montana | 404 on that seed |

**Anchorage is the finding.** A 33 km request came back as a six-hour loop,
because the road network is thin enough that there is nothing shorter to build.
The ±25% duration filter rejects that, so a user there most likely sees "Found
loops, but none close to 1 hour" rather than a route. The app is honest at
runtime — it declines rather than handing over a bad loop — but **the listing
does not mention road density anywhere**, and that is a real product limit.

Not a false-advertising problem: the listing makes no geographic claim, and
"back-road loops from anywhere" is accurate about where it will *try*. If a
caveat is ever added, it should be about road density, not geography. Bryce
wants to revisit this.

## Retrace and reversal, measured 2026-09-04

113 loops, three origins, all four picker sizes, run through the **app's exact
pipeline** — `round_trip`, downsample to the 8 handoff waypoints, reroute, and
measure *that*. Direct against local ORS on the box, so no quota was spent.
Script and raw JSON: `tools/measure-geometry.py`, `/tmp/loopdata.json` on the box.

### Retrace: the app promises something it never checks

The App Store description promises loops that "come back **without retracing
themselves**", and SPEC.md's founding problem is the retraced return leg.
**Nothing in the app computes it.** Highway share gets a filter; retrace does not.

Percentage of driven length spent on road covered on a separate pass:

| size | median | mean | >10% | >20% |
|---|---|---|---|---|
| **30m** | **7.8%** | 11.2% | **47%** | **17%** |
| 60m | 4.1% | 7.1% | 33% | 7% |
| 90m | 5.1% | 4.9% | 7% | 0% |
| 120m | 3.5% | 4.5% | 4% | 0% |

**The 30-minute option is far worse in Marlboro than anywhere else**, which is
why it was noticed there and matters more than the global median suggests:

| origin, 30m | median | max |
|---|---|---|
| **Marlboro NJ** | **18.9%** | **43.3%** |
| Denver CO | 5.0% | 17.2% |
| Austin TX | 6.0% | 12.1% |

This confirms SPEC.md's "Known floors" prediction (11% retrace at the small
sizes against 2% at 16 km) and **localises it**: it is not a general defect, it
is Bryce's own road network at the smallest size, which is exactly the
combination he generates from.

Retrace is a **25 m grid approximation** — points snapped to cells, a cell
entered in two non-contiguous runs counts as retraced, both passes counted.
Treat ±2 points as noise.

### Reversal: reversing the waypoints is not the same drive

**The obvious implementation is wrong and this was measured, not reasoned.**
Reversing the handoff waypoint list produces a **systematically longer and
different** route:

| | |
|---|---|
| Median duration change | **+8.1%** |
| Median distance change | +10.2% |
| Reversed came back longer | **101 of 113** |
| Duration within 5% of forward | **36%** |
| Worst case | Marlboro 60m seed 7: 71.8 min → **124.5 min** |

Clean rate by size: 30m **20%**, 60m 43%, 90m 41%, 120m 42%.

**The mechanism shows in the retrace numbers** — reversed routes carry roughly
double the retrace of forward ones at every size (30m 7.8% → 15.8%, 120m 3.5% →
8.9%). Routing the same points in the opposite order does not mirror the path;
it finds a worse one. Only 1 of 113 crossed the 15% highway threshold, so
highway share is *not* the thing reversal breaks — duration is.

**Consequence:** shipping a bare `waypoints.reversed()` would hand the user a
drive ~8% longer than the number on screen, against a description that
explicitly promises "the duration you see is the duration you drive." A
verification request per reversal is not optional.

### What follows, and the review risk in it

Both filters below are **new ways for the app to show the user nothing**, and
"nothing happened when we tapped generate" is the exact sentence that caused
rejections three and four. **Neither filter may ever return an empty result** —
on empty, fall back to the best available loops with the stat shown, rather than
an empty state. See the pre-submission checklist.

**Status lives in the open checklist at the top of this file, not here** — a
second copy of a task list is how this file drifted twice already. What follows
is the reasoning behind tasks 13-15, which does not change as they ship.

**13 — shipped in 1.0.2, 2026-09-09.** The map colouring is the part that
answers the original complaint: on a
retraced stretch the route draws over itself and reads as one straight line with
no way to tell it is two passes. **That is all 1.0.2 does** — it labels the
problem, it does not remove it.

**14, the filter half.** Thresholds should land where they are affordable: 10%
rejects only 4-33% of loops at the three long sizes, but 47% globally at 30m and
more than half in Marlboro, which is why 30m wants 20% and should lean on the
colouring instead. **Re-derive these from live data before building it** — the
numbers above come from a 113-loop sample on three origins, and the retrace stat
has been shipping since 2026-09-09.

**The hard rule, worth repeating because it is the rejection path:** the filter
may never return an empty result. On empty, fall back to the best available
loops with the stat shown.

**14, the reversal half.** Verify lazily on tap, not upfront: one request, ~50 ms on the box, and
users who never press it pay nothing. When it diverges, **show the cost rather
than hiding the button** — "Reverse (+12 min)" is honest and leaves the choice
with the driver. Hiding it would mean the control vanishes on ~64% of loops,
which is worse UI than a truthful label.

**15.** Curviness is the one that would change what the product is — total
heading change per mile, computed on `Loop.coordinates`, no network. Note it
**cannot distinguish the two directions**: total turning is identical whichever
way round you go, so it is not a substitute for offering reversal.

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
- **Disk is the standing constraint.** It filled completely during the first
  build session. Measured 2026-08-24: the data volume was at **91%, 183 GiB
  used with 19 GiB free**. Note `df -h /` reads ~12 GiB used — that is the
  read-only system snapshot and is misleading; check `/System/Volumes/Data`.

  Where it goes, and what is safe to reclaim:

  | Size | Path | Safe? |
  |---|---|---|
  | 56 G | `/Library/Developer/CoreSimulator/Volumes` — runtimes (26.4, 26.4.1, 26.5, one unused watchOS) | Per-runtime, via Xcode Settings ▸ Components. 26.4 and 26.4.1 are a pointless duplicate. |
  | 24 G | `~/Library/Developer/CoreSimulator/Devices` | `xcrun simctl delete unavailable`, then `shutdown all && erase all` |
  | 11 G | `~/Library/Developer/Xcode/iOS DeviceSupport` — symbol caches per physical device | Delete entirely; rebuilds on next connect |
  | 834 M | `~/Library/Developer/Xcode/DerivedData` | Delete entirely; pure build cache |
  | 12 M | `~/Library/Developer/Xcode/Archives` | **Keep.** Only local copy of what was uploaded. |

  Clearing the first three lands around 55-60 GiB free.
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

- **Attribution string: fixed in source, ships in 1.0 (4).** Now reads
  `© openrouteservice by HeiGIT | Data from OpenStreetMap`, which is what
  HeiGIT's terms specify. 1.0 (3) carried the old wording — it credited both
  parties, so it was not worth pulling a live submission for, but it was not
  the string they ask for. Confirmed rendering in the 1.0 (4) results screen.
  Note the required string also differs from what secondary sources claim; the
  ToS is the only source worth trusting.

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

- **Never been driven, by decision** (2026-09-02). Not an open item. See "Where
  this stands".
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

## What was open on shipping — kept as history

**Every item here is closed. Read it for the reasoning, not for the state.**
Current capacity is in "The ceilings, in plain terms".

- ~~**ORS quota is shared across every install.** 40 requests/minute, roughly
  two generates per minute across all users combined, which is the real ceiling
  — not the daily quota.~~ **Superseded 2026-09-03.** That was the binding limit
  only while everyone was on HeiGIT. Inside the US, requests go to our own box,
  which measures **~24 requests/second, roughly 80 generates per minute** and has
  no quota at all. The binding limit is now the Cloudflare Worker's 100k
  requests/day.

  **The prediction in it was right, and worth keeping for that.** It said the
  ceiling "starts hurting somewhere around a hundred active ones, and it hurts on
  weekend mornings specifically, which is the whole use case." That is exactly
  the failure that made the widening urgent.

- ~~The ORS free tier is not licensed for production use.~~ **Retracted
  2026-08-08.** HeiGIT's terms place no restriction on commercial or production
  use. This was assumed during prototyping, never checked, and wrongly shaped
  planning for weeks — it is why self-hosting kept getting framed as a
  compliance requirement. It is an optimisation, nothing more.

**Self-hosting stopped being theoretical here** — see `selfhost/README.md`. What
it cost at the time, on the original four-state graph:

| | NJ + PA + NY + DE | Whole US, for comparison |
|---|---|---|
| Extract | 0.98 GB | 11.28 GB |
| Graph build | 955 s, **1.96 GB peak heap** | 400 min, **8,021 MiB peak heap** |
| Serving with MMAP | **1.12 GB** | 15 GB graph, restart in 20 s |
| Latency | 55-140 ms, against 430-970 ms hosted | 49-64 ms |
| 12-request burst | 0.28 s, no rate limit | 0.47-0.52 s, no rate limit |

Two findings, and **the first one is wrong at scale:**

- ~~**Build memory barely grows with the extract.** Six times the map cost 15%
  more heap, not six times. Linear extrapolation predicted ~10 GB and was wrong
  by 5x. This is what puts it inside a free tier.~~ **Corrected 2026-09-03, task
  11.** True from 0.16 GB to 0.98 GB and false at country scale: the 15% rule
  predicted 5.0-5.7 GB for the US and the real figure was **8,021 MiB of an
  8,192 MiB ceiling**. It was wrong by ~2.5 GB in the direction that kills a
  build. `graphs_data_access: MMAP` does keep the graph off-heap, and that part
  still holds — it is why serving is cheap. **Budget for heap, disk and time
  separately, and do not extrapolate any of them from a small extract.**
- **The neighbouring states are not optional.** A New Jersey-only graph ends at
  the state line: Jersey City and Lambertville failed outright, and the
  north-west corner silently returned a loop **19% short with no error**, which
  nothing at runtime could have detected. This is the finding the region insets
  exist to honour, and it generalises — it is why `us_north` is capped 65 km
  inside the Canadian border rather than at it.

~~`worker/src/index.js` routes New Jersey traffic to a self-hosted instance. It
is inert until `SELF_HOSTED_ORIGIN` is set, so it deploys safely before a server
exists.~~ **Superseded** — six region boxes plus `ak` and `hi`, live since
2026-09-03. The fallback behaviour described is unchanged and load-bearing: any
non-200, timeout or dead socket falls through to HeiGIT, which is why adding a
region can only add successes.

## Prototype files kept for reference

- `loopgen_ors.py` — ORS prototype, reads `ORS_KEY` env var. Stale, see above.
- `loopgen.py` — earlier GraphHopper attempt, superseded.
- `geojson2gpx.py` — converts loop output to GPX for simulated movement (v2).
- `*.geojson`, `gpx/` — prototype output. `p8.geojson` is only the start marker;
  the route that went with it is `p8_route.geojson`, renamed out of
  `p8.geojsonclear` — a `> p8.geojson` and a `clear` on one line.

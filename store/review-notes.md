# App Review Information — response to Guideline 2.1

Rejected 2026-08-14 under Guideline 2.1, *Information Needed*. Not a bug report
and not a code problem: the reviewer asked for documentation and a screen
recording, in seven numbered items.

Item 1 is a screen recording captured on a physical device and is attached
separately in Resolution Center. Items 2-7 are the text below, which goes in the
**Notes** field of App Review Information so future submissions carry it
automatically.

Keep this file in sync with that field. Apple asks the same questions every
time, and answering them up front is what prevents this rejection recurring.

---

## Paste into the Notes field

```
Aimless generates circular driving routes that start and end at the user's
current location. No account, no login, no purchases, no user-generated
content.

TO TEST
1. Allow location access when prompted. The app requires precise location and
   deliberately refuses to generate under reduced accuracy rather than build a
   route starting kilometers away.
2. Choose a duration - 60, 90, or 120 minutes - with the slider.
3. Tap Generate. Takes 1-2 seconds.
4. Three loops appear as swipeable maps showing distance, drive time, and
   highway percentage.
5. Tap "Drive This" to open the route in Google Maps, or in Safari if Google
   Maps is not installed.

No credentials or sample files are required. Results depend on the road network
around the tester's location: a suburban or rural location produces better
results than a dense city center or a location surrounded by water.

2. DEVICES AND OS TESTED
- iPhone Air (iPhone18,4), iOS 26.5.2 - physical device
- iPhone 17 Pro Max, iOS 26 - Simulator
- iPhone 14 Plus, iOS 26 - Simulator

3. FUNCTION AND TARGET AUDIENCE
Aimless is for drivers who enjoy driving itself rather than arriving somewhere.
The problem it solves: a drive with no destination has a flaw - you get too far
from home and the return leg becomes dead time retracing roads you just
covered. A loop removes that. The user picks how long they want to be out and
receives three circular routes that wander out and come back without retracing
themselves, favoring back roads. Routes with significant highway content are
filtered out. Audience is general - drivers, motorcyclists, and passengers
looking for a scenic drive. Rated 4+, no objectionable content.

4. SETUP AND ACCESS
No setup. No account registration, login, or deletion flows exist. No paid
content, purchases, or subscriptions. No user-generated content, so no
reporting or blocking mechanisms apply. The only permission requested is
location, prompted at first launch.

5. EXTERNAL SERVICES USED
- openrouteservice, operated by HeiGIT gGmbH (Germany): generates and verifies
  candidate routes. Road data derives from OpenStreetMap.
- Cloudflare Workers: a proxy we operate, sitting between the app and
  openrouteservice so the API credential is not shipped inside the binary.
- Apple MapKit: renders the base map and its own map credit.
- Google Maps: receives the chosen route via a universal link for turn-by-turn
  navigation. Opens in Safari if the app is not installed. No SDK is embedded.

No analytics, advertising, tracking, authentication, payment, or AI services of
any kind are used. The app has no third-party SDKs.

6. REGIONAL DIFFERENCES
None. The app behaves identically in every region, with no geo-gating, no
region-specific content, and no regional feature differences. Routing coverage
is worldwide because OpenStreetMap is worldwide. Route quality varies with
local road density, which is a property of the map data rather than of the app.

7. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
Not a regulated industry. The app provides no medical, financial, legal, or
gambling functionality.

The third-party material used is map and routing data, and both licenses permit
this use with attribution:
- Road network data from OpenStreetMap, licensed under the Open Database
  License (ODbL), which permits use including commercial use and requires
  attribution.
- Routing results from openrouteservice, licensed CC-BY-SA 4.0. Their terms
  place no restriction on production or commercial use.

The app displays the required attribution on the results screen, where the data
is shown. Base map credit is rendered by MapKit itself.

OPERATIONAL NOTE
One generation issues roughly 18 routing requests, or up to 36 when a retry
round is needed, against a provider limit of 40 per minute. Several generations
in quick succession may show a rate-limit message. This is expected, handled,
and resolves after a minute.
```

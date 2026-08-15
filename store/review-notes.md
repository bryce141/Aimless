# App Review Information — response to Guideline 2.1

Rejected 2026-08-14 under Guideline 2.1, *Information Needed*. Not a bug report
and not a code problem: the reviewer asked for documentation and a screen
recording, in seven numbered items.

Item 1 is a screen recording captured on a physical device, attached to the
reply on the submission page. Items 2-7 are the text below, which goes in the
**Notes** field of App Review Information so future submissions carry it
automatically.

Two things worth knowing before editing this:

- **Paste from `review-notes.txt`, not from this file.** That file holds the
  notes and nothing else, so select-all-copy does the right thing. Copying this
  file instead picks up the prose above and the code fences, which is what
  twice produced an over-limit error and twice looked like the field being
  smaller than documented. The field really is 4,000 characters; the block
  below is 3,162.
- **The reply dialog does not show an attachment until you click Save Draft.**
  There is no progress bar, no filename, and no error while it uploads, so a
  successful attach and a failed one look identical. Save the draft, confirm
  "Message Attachments" lists the file, then Continue Draft and send. Chasing
  this cost half an hour and three re-encodes of a video that had uploaded fine
  the first time.
- **Keep the video small anyway.** ffmpeg at `-vf scale=540:-2 -crf 30` turned a
  105 MB screen recording into 1.4 MB that is still legible down to the
  attribution line. `avconvert`, which needs no install, only got to 17 MB
  because its presets do not expose the encoder.
- **Resolution Center no longer exists** as a separate area. The reply thread
  now lives behind "View Submission" in the rejection banner on the version
  page, and the Notes field is under **App Review** in the left sidebar.

Keep this file in sync with that field. Apple asks the same seven questions of
every new app, so answering them up front is what stops this recurring.

---

## Paste into the Notes field

```
Aimless generates circular driving routes that start and end at the user's
current location. No account, login, purchases, or user-generated content.

TO TEST
1. Allow location when prompted. Precise location is required; the app
   deliberately refuses to generate under reduced accuracy.
2. Choose 60, 90, or 120 minutes with the slider.
3. Tap Generate (1-2 seconds).
4. Three loops appear as swipeable maps with distance, drive time, and highway
   percentage.
5. Tap "Drive This" to open the route in Google Maps, or Safari if Google Maps
   is not installed.

No credentials or sample files are needed. Results depend on the roads around
the tester: suburban or rural works better than a dense city center or a
location surrounded by water.

2. DEVICES AND OS TESTED
- iPhone Air (iPhone18,4), iOS 26.5.2 - physical device
- iPhone 17 Pro Max and iPhone 14 Plus, iOS 26 - Simulator

3. FUNCTION AND TARGET AUDIENCE
For drivers who enjoy driving rather than arriving. A drive with no destination
has a flaw: you get too far out and the return leg becomes dead time retracing
roads you just covered. A loop removes that. The user picks how long to be out
and gets three circular routes that come back without retracing, favoring back
roads; routes with significant highway content are filtered out. Audience is
general - drivers, motorcyclists, passengers. Rated 4+.

4. SETUP AND ACCESS
No setup. No account registration, login, or deletion flows. No paid content or
subscriptions. No user-generated content, so no reporting or blocking applies.
Location is the only permission requested, prompted at first launch.

5. EXTERNAL SERVICES
- openrouteservice, operated by HeiGIT gGmbH (Germany): generates and verifies
  routes from OpenStreetMap road data.
- Cloudflare Workers: our own proxy, so the API credential is not shipped in
  the binary.
- Apple MapKit: renders the base map and its own credit.
- Google Maps: receives the route via a universal link for navigation. Opens in
  Safari if not installed. No SDK is embedded.
No analytics, advertising, tracking, authentication, payment, or AI services,
and no third-party SDKs.

6. REGIONAL DIFFERENCES
None. Identical in every region: no geo-gating, no region-specific content or
features. Coverage is worldwide because OpenStreetMap is worldwide. Route
quality varies with local road density, which is a property of the map data
rather than of the app.

7. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
Not a regulated industry; no medical, financial, legal, or gambling
functionality. The only third-party material is map and routing data, and both
licenses permit this use with attribution: OpenStreetMap road data under the
Open Database License (ODbL), and openrouteservice results under CC-BY-SA 4.0.
Neither restricts commercial or production use. The app displays the required
attribution on the results screen; MapKit renders its own base map credit.

OPERATIONAL NOTE
One generation issues ~18 routing requests, up to 36 with a retry, against a
provider limit of 40/minute. Generating several times in quick succession may
show a rate-limit message; this is expected and clears after a minute.
```

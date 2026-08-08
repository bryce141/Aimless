# Privacy Policy for Aimless

Last updated: 8 August 2026

Aimless has no accounts, no analytics, no advertising, and no third-party
tracking SDKs. It stores nothing about you, on your device or anywhere else.

## What the app accesses

**Your location, while you are using the app.** Aimless builds a driving loop
that starts and ends where you are, so it needs a location fix to have anywhere
to start from. It is requested only while the app is open — Aimless does not
track your movement, run in the background, or record where you have been.

The app requires precise location. With Precise Location turned off, iOS
returns a position that can be off by kilometers, which would produce a loop
starting somewhere you are not. Aimless declines to generate rather than hand
you a route to the wrong place.

## What leaves your device

When you tap Generate, your current coordinates are sent to a routing service
to calculate loops:

1. Coordinates go to a Cloudflare Worker operated by the developer, which adds
   an API credential and forwards the request.
2. The Worker forwards it to [OpenRouteService](https://openrouteservice.org),
   operated by HeiGIT gGmbH in Germany, which returns candidate routes.

Nothing else is transmitted. No device identifier, no name, no email, no
advertising ID — nothing that identifies you or your device is attached to the
request. The coordinates are used to compute a route and are not stored by the
app or by the developer's Worker.

Cloudflare and HeiGIT operate their own infrastructure and may keep standard
service logs under their own policies:

- Cloudflare: https://www.cloudflare.com/privacypolicy/
- OpenRouteService / HeiGIT: https://openrouteservice.org/privacy-policy/

## Google Maps handoff

Aimless does not provide navigation. Tapping **Drive This** opens Google Maps
with the loop's waypoints in the URL. From that point you are using Google
Maps, and Google's privacy policy applies: https://policies.google.com/privacy

Aimless has no relationship with Google and receives nothing back.

## What is stored

Nothing. Aimless has no database, no accounts, no saved history, and no
sync. Generated loops exist only in memory and are gone when you close the app.

## Children

Aimless is not directed at children and collects no personal information from
anyone.

## Changes

Any change to this policy will be published at this address with an updated
date.

## Contact

Questions: open an issue at https://github.com/bryce141/Aimless/issues

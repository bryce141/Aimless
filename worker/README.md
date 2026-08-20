# Routing proxy

A Cloudflare Worker between the app and OpenRouteService.

Two reasons it exists, and the second is the important one:

1. The ORS key stops shipping inside the app binary.
2. **The routing backend gets an address the app owns.** Once a build is on the
   App Store, its endpoint is frozen into a reviewed artifact — changing it
   means a new binary, another review, and users on old versions stranded on the
   old URL. Pointing at a Worker instead makes swapping in a self-hosted routing
   engine a server-side change deployed in seconds.

## Deploy

```
npm install -g wrangler
wrangler login
wrangler secret put ORS_API_KEY     # paste the key from Aimless/Config.swift
wrangler deploy
```

Optionally require a client token:

```
wrangler secret put CLIENT_TOKEN
```

If `CLIENT_TOKEN` is set, the app must send a matching `X-Aimless-Client`
header. This does not make the app secure — whatever the client sends is also
in the binary — it just narrows a scraped value from "an ORS account key usable
against every ORS API" to "a disposable string for this one endpoint."

## Contract

Only `POST /v2/directions/driving-car/geojson` is served. Everything else 404s.

**Status codes pass through untouched**, and this is load-bearing. The client
treats 429 as rate limiting worth telling the user about, and 404/5xx as one
dead seed to swallow silently. Collapsing them into a generic error would make a
throttled round look identical to a round where no loop matched — the exact
confusion `RouteService` is built to avoid. Response bodies pass through too,
since ORS puts a readable message in `error.message`.

## Self-hosted routing

`SELF_HOSTED_ORIGIN` points at our own ORS instance. When it is set, requests
whose origin falls inside the New Jersey bounding box are tried there first and
fall back to HeiGIT on any non-200, timeout or dead socket. Unset, everything
goes to HeiGIT — which is why this deploys safely before a server exists.

```
wrangler secret put SELF_HOSTED_ORIGIN
```

**The value must end in `/ors`, and getting this wrong is silent.** The Worker
appends `/v2/directions/driving-car/geojson`, while ORS serves that path under
`/ors`. So:

```
https://ors.example.com/ors        <- correct
https://ors.example.com            <- 404s on every request, forever
```

A wrong origin does not look broken. Every self-hosted attempt 404s, `trySelfHosted`
returns null exactly as designed, and HeiGIT answers instead — so the app keeps
working, at HeiGIT's latency and under HeiGIT's rate limit, which is the precise
thing the instance was stood up to escape.

**Check the response header rather than assuming.** `X-Aimless-Served-By` is
`self` or `heigit` on every response:

```
curl -sD- -o/dev/null -X POST \
  https://aimless-routing.bdrp777.workers.dev/v2/directions/driving-car/geojson \
  -H 'Content-Type: application/json' \
  -H 'X-Aimless-Client: <token>' \
  -d '{"coordinates":[[-74.246,40.315]],"options":{"round_trip":{"length":33000,"points":8,"seed":1}}}' \
  | grep -i served-by
```

An origin in Marlboro NJ should come back `self`. If it says `heigit`, the
instance is not being used — check the `/ors` suffix first.

The timeout is 1000 ms (`SELF_HOSTED_TIMEOUT_MS`), against 55-140 ms measured
locally. It is sized to catch a box that is wedged or reclaimed, not one that is
briefly busy. Note the first request after a restart is slower — `MMAP` serves
the graph from disk, so the page cache starts cold and one request paid 200 ms.

## Caching

Successful routes are cached at the edge for 24 hours, keyed on a SHA-256 of the
request body. Only 200s are stored — a cached 429 would outlive the minute it
belongs to, and a cached 404 would turn one dead seed into a permanent fact
about that route.

**This matters more than it looks, because the app asks for seeds 1-12 on every
first round.** ORS is deterministic — same seed, origin and size returns the
identical route forever — so tapping Generate twice in the same spot re-sends
twelve byte-identical requests. Uncached, four generates at a desk cost 48
requests against HeiGIT's 40/minute ceiling and the fourth one fails.

Measured before and after, four generates from one origin:

| | Upstream requests | Throttled |
|---|---|---|
| Before | 48 | **8 of 12 on generate #4** |
| After | 23 | **none** |

`X-Aimless-Cache` reads `hit` or `miss` on every response. Expect the first
repeat to still miss: `cache.put` runs in `waitUntil` after the response is
already on its way, and the cache is per-datacentre rather than global.

**This was the fix for the Guideline 2.1(a) rejection** — a reviewer tapping
Generate repeatedly hit the rate limit and saw an error. It is server-side, so
it shipped without a new build.

## Self-hosted origin auth

`SELF_HOSTED_TOKEN` is sent to our own instance as `X-Aimless-Origin`. An nginx
gate in front of ORS checks it and 403s everything else.

It exists because a Cloudflare Tunnel hostname is public — Cloudflare serves it
to anyone who knows the name — and ORS has no authentication of its own. Unset
the secret and the header is simply omitted, which the gate will reject; that
degrades to HeiGIT rather than failing, like any other non-200 from the box.

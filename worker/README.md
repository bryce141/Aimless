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

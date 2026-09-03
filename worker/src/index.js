/**
 * Aimless routing proxy.
 *
 * Sits between the app and OpenRouteService so the API key stops shipping
 * inside a binary anyone can download and inspect. Also gives the routing
 * backend a stable address the app owns: swapping ORS for a self-hosted
 * instance later becomes a change here, deployed in seconds, instead of a new
 * App Store build and another review cycle.
 *
 * Deliberately dumb. It attaches a key, refuses anything that isn't the one
 * call the app makes, and gets out of the way.
 */

const UPSTREAM = "https://api.openrouteservice.org";

/** The only endpoint Aimless calls. Anything else is someone else's traffic. */
const ALLOWED_PATH = "/v2/directions/driving-car/geojson";

/** A generate is ~18 requests of a few hundred bytes. Anything large is not us. */
const MAX_BODY_BYTES = 8 * 1024;

/**
 * Where our own routing instance is allowed to answer.
 *
 * Each box is deliberately *smaller* than the graph behind it. A route
 * generated near the edge of a graph gets silently clipped against roads that
 * stop existing and returns a plausible-looking loop that is simply too short —
 * measured from a NJ-only graph, an origin in the north-west corner came back
 * 19% short with no error at all. So each entry is inset far enough from the
 * graph's real edge that a 100 km round trip cannot reach it, and HeiGIT, who
 * host the whole planet, keeps everywhere else.
 *
 * Since 2026-09-03 the graph holds the whole United States, so the only real
 * edges left are the Canadian and Mexican land borders. **Coastlines are not
 * edges in this sense** — the road network genuinely stops at the water, so a
 * route clipped by the Atlantic is a correct route, not an artefact.
 *
 * **One box cannot express the country.** The Canadian border needs a ~65 km
 * inset in the north, and the Mexican border needs one in the south-west — but
 * a single `minLat` inset from Mexico would cut Miami, which sits 1,900 km from
 * that border. Hence a north box and a south-east box, split at the latitude
 * above which Mexico stops mattering.
 *
 * - `nj`  NJ only. Shipped and measured 2026-08-20, now a subset of `us_north`
 *         and kept so a rollback to the proven pair stays one setting away.
 * - `ca`  California, inset from Oregon, Nevada, Arizona and Mexico. Also now a
 *         subset of `us_north`. Kept for the same reason.
 * - `us_north`  Everything above 33.5°N, which clears the Mexican border's
 *         northernmost point (32.72°N at the Colorado River) by ~87 km. Capped
 *         at 48.4°N, ~65 km south of the 49th parallel. Costs a thin northern
 *         strip — Bellingham WA, the Montana and North Dakota border towns.
 * - `us_southeast`  Below 33.5°N and east of -96.0, which is ~114 km east of
 *         the Rio Grande's easternmost point at Brownsville. Florida, the Gulf
 *         coast and eastern Texas. Miami and the Keys included; the coast needs
 *         no inset.
 *
 * Deliberately still on HeiGIT, and each for its own reason:
 *   - **Hawaii.** Measured 0/10 on `round_trip` against this graph where HeiGIT
 *     returns 4/5. The roads are present — point-to-point works — but the
 *     round-trip generator cannot place waypoints on a 44 km wide island. No
 *     retry rescues a zero, so routing it here would be strictly worse.
 *   - **Alaska.** 2/5, and its real problem is road sparsity that HeiGIT shares:
 *     a 33 km request already comes back as a six-hour loop. Worth revisiting,
 *     not worth a bespoke box tonight.
 *   - **The south-west border strip** — San Diego, Tucson, El Paso, Laredo.
 *     Inside the clipping distance of the Mexican border.
 *
 * Which of these are live is `SELF_HOSTED_REGIONS`, not this table — see
 * `coveredRegions`. Adding a box here does not route anything to it.
 */
const REGIONS = {
  nj: { minLon: -75.56, maxLon: -73.89, minLat: 38.93, maxLat: 41.36 },
  ca: { minLon: -124.4, maxLon: -117.5, minLat: 33.5, maxLat: 41.4 },
  us_north: { minLon: -124.8, maxLon: -66.9, minLat: 33.5, maxLat: 48.4 },
  us_southeast: { minLon: -96.0, maxLon: -79.0, minLat: 24.4, maxLat: 33.5 },
  us_texas: { minLon: -98.8, maxLon: -96.0, minLat: 28.5, maxLat: 33.5 },
  us_southwest: { minLon: -114.5, maxLon: -109.1, minLat: 32.1, maxLat: 33.5 },
};

/**
 * The regions our instance currently has a graph for, as a comma-separated list
 * in `SELF_HOSTED_REGIONS` — for example `nj,ca`. Unset means `nj`, which is
 * what was live before this setting existed.
 *
 * Coverage is configuration rather than code because the graph and the routing
 * rule have to change together, and only one of them is a deploy. Building a
 * new extract on the box takes hours and can fail; flipping a region on before
 * its graph exists would route those users into 404s. So the box gets built
 * first, and this is turned on afterwards, with no code change between them.
 */
function coveredRegions(env) {
  const raw = (env.SELF_HOSTED_REGIONS ?? "nj").split(",");
  return raw
    .map((name) => REGIONS[name.trim()])
    .filter(Boolean);
}

/**
 * How long to wait on our own instance before giving up and using HeiGIT.
 *
 * Measured locally at 55-140ms per request, so a second is generous. It is
 * meant to catch a box that is wedged or reclaimed, not one that is briefly
 * busy — Oracle's free tier can shut down instances it considers idle, and that
 * must degrade to "slower" rather than "broken".
 */
const SELF_HOSTED_TIMEOUT_MS = 1000;

/**
 * How long a routed answer stays good.
 *
 * ORS is deterministic: the same seed, origin and request size returns the
 * identical route forever — verified, same geometry and duration to the metre
 * across repeated calls. Only the response's own timestamp differs.
 *
 * That makes this cache unusually effective here, because **the app asks for
 * seeds 1-12 on every first round**. Tapping Generate a second time in the same
 * spot re-sends twelve byte-identical requests. Uncached, four generates at a
 * desk cost 48 requests against a 40/minute ceiling and the fourth one fails —
 * which is exactly the bug App Review reported.
 *
 * A day is well inside how fast road data moves; the graph behind it is rebuilt
 * far less often than that.
 */
const CACHE_TTL_SECONDS = 86400;

/**
 * Where the uptime monitor points. GET, unauthenticated, no coordinates
 * involved, so it is safe to hand to a third-party checker.
 */
const HEALTH_PATH = "/health/selfhosted";

/**
 * Longer than `SELF_HOSTED_TIMEOUT_MS`, and on purpose.
 *
 * The routing timeout is 1000 ms because a user is waiting and HeiGIT is a
 * perfectly good answer. A monitor is not waiting, and a page-out at 3am
 * because the box took 1.2 s once is worse than useless — it teaches you to
 * ignore the alert. This wants to fire when the box is *gone*, not when it is
 * briefly busy. Note the first request after a restart is slower: MMAP serves
 * the graph from disk and the page cache starts cold.
 */
const HEALTH_TIMEOUT_MS = 8000;

/**
 * Ask our own instance whether it is serving, and say so in a shape an uptime
 * monitor understands: **HTTP 200 means healthy, anything else means alert.**
 *
 * The three states worth telling apart, because they need different responses:
 *
 * - `unconfigured` — `SELF_HOSTED_ORIGIN` is unset, so the Worker is sending
 *   everything to HeiGIT by design. This is the documented rollback position,
 *   not a fault, so it answers 200. If it answered 503 the monitor would scream
 *   through a deliberate rollback.
 * - `ok` — the box answered and reported ready.
 * - `down` — no answer, a timeout, or a body that does not say ready. A graph
 *   rebuild also lands here, because ORS reports "not ready" while building,
 *   which is correct: during a rebuild the country really is on HeiGIT's 200/day.
 */
async function selfHostedHealth(env) {
  const started = Date.now();

  if (!env.SELF_HOSTED_ORIGIN) {
    return healthJson(200, {
      ok: true,
      state: "unconfigured",
      note: "SELF_HOSTED_ORIGIN unset; all traffic goes to HeiGIT by design",
    });
  }

  try {
    // Same credentials the routing path sends. The probe has to authenticate
    // exactly as real traffic does, or it reports the box healthy while every
    // actual request is being refused — a monitor that cannot see the failure
    // it exists to catch.
    const headers = {};
    if (env.SELF_HOSTED_TOKEN) headers["X-Aimless-Origin"] = env.SELF_HOSTED_TOKEN;
    if (env.CF_ACCESS_CLIENT_ID && env.CF_ACCESS_CLIENT_SECRET) {
      headers["CF-Access-Client-Id"] = env.CF_ACCESS_CLIENT_ID;
      headers["CF-Access-Client-Secret"] = env.CF_ACCESS_CLIENT_SECRET;
    }

    const res = await fetch(`${env.SELF_HOSTED_ORIGIN}/v2/health`, {
      method: "GET",
      headers,
      signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS),
    });
    const latencyMs = Date.now() - started;
    const text = (await res.text()).slice(0, 200);

    // ORS answers {"status":"ready"} when serving and {"status":"not ready"}
    // while a graph builds. Substring-matching "ready" would match both, which
    // is a mistake already made once against this exact endpoint.
    const ready = res.ok && text.includes('"status":"ready"');

    return healthJson(ready ? 200 : 503, {
      ok: ready,
      state: ready ? "ok" : "down",
      upstreamStatus: res.status,
      upstreamBody: text,
      latencyMs,
    });
  } catch (err) {
    return healthJson(503, {
      ok: false,
      state: "down",
      error: String(err?.name ?? err),
      latencyMs: Date.now() - started,
    });
  }
}

function healthJson(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      // Never cache a health result. A cached 200 outliving the box being up
      // is the one way this check can lie.
      "Cache-Control": "no-store",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Public health probe for an external uptime monitor. Deliberately GET,
    // deliberately unauthenticated, and deliberately *not* on the routing path.
    //
    // **It has to be answered here rather than on the box.** A check that runs
    // on the instance cannot report that the instance is gone. The Worker runs
    // on Cloudflare's edge and is up when the box is not, which is the only
    // arrangement that can distinguish the two.
    if (url.pathname === HEALTH_PATH) {
      return selfHostedHealth(env);
    }

    if (request.method !== "POST") {
      return json(405, "Method not allowed");
    }

    if (url.pathname !== ALLOWED_PATH) {
      return json(404, "Not found");
    }

    // Optional shared token. This does not make the app secure — whatever the
    // client sends ships in the binary too — it just means a scraped value is
    // a disposable string scoped to this one endpoint rather than an ORS
    // account key usable against every ORS API.
    if (env.CLIENT_TOKEN) {
      if (request.headers.get("X-Aimless-Client") !== env.CLIENT_TOKEN) {
        return json(401, "Unauthorized");
      }
    }

    const body = await request.text();
    if (body.length > MAX_BODY_BYTES) {
      return json(413, "Payload too large");
    }

    // A previously answered identical request. Costs no upstream quota at all,
    // which is the whole point — see CACHE_TTL_SECONDS.
    const cache = caches.default;
    const cacheKey = await cacheKeyFor(body);
    const store = { ctx, cache, cacheKey };
    const cached = await cache.match(cacheKey);
    if (cached) {
      const headers = new Headers(cached.headers);
      headers.set("X-Aimless-Cache", "hit");
      logOutcome({
        servedBy: headers.get("X-Aimless-Served-By") ?? "cache",
        status: 200,
        cache: "hit",
      });
      return new Response(cached.body, { status: 200, headers });
    }

    // Try our own instance first when one is configured and the route starts
    // somewhere it covers well. Unset SELF_HOSTED_ORIGIN and everything goes to
    // HeiGIT exactly as it always has — which is what makes deploying this safe
    // before any server exists.
    if (env.SELF_HOSTED_ORIGIN && originIsCovered(body, coveredRegions(env))) {
      const local = await trySelfHosted(
        env.SELF_HOSTED_ORIGIN, body, env.SELF_HOSTED_TOKEN, store, env);
      if (local) return local;
      // Fall through to HeiGIT. A dead box is a slower app, not a broken one.
    }

    let upstream;
    try {
      upstream = await fetch(UPSTREAM + ALLOWED_PATH, {
        method: "POST",
        headers: {
          Authorization: env.ORS_API_KEY,
          "Content-Type": "application/json",
          Accept: "application/geo+json",
        },
        body,
      });
    } catch (e) {
      // The app reads a failed request as one dead seed, which is the right
      // reading: 502 is not 200, and it will be swallowed like any other.
      return json(502, "Upstream unreachable");
    }

    return passThrough(upstream, "heigit", store);
  },

  /**
   * Cron trigger. Runs the same probe on a schedule and writes the result to
   * Workers Logs.
   *
   * **This is a record, not an alarm** — nothing here can wake anyone up, and
   * pretending otherwise would be worse than having no check. Its job is that
   * when someone eventually asks "how long has it been down", the answer exists
   * rather than having to be guessed. The alerting is an external monitor
   * pointed at HEALTH_PATH, which is the piece that can actually reach a person.
   */
  async scheduled(event, env, ctx) {
    const res = await selfHostedHealth(env);
    const body = await res.clone().json().catch(() => ({}));
    logOutcome({
      probe: "selfhosted-health",
      status: res.status,
      state: body.state,
      latencyMs: body.latencyMs,
    });
  },
};

/**
 * Asks our own instance, returning null if it can't answer for any reason.
 *
 * Null covers a genuine 404/500 too, not just a dead socket. Those are ordinary
 * on round-trip requests — roughly one seed in ten fails everywhere — but our
 * box is the newer, less proven of the two, so anything short of a 200 is worth
 * a second opinion from HeiGIT. A 429 can't happen here; there is no limit to
 * hit, which is the entire reason this path exists.
 */
async function trySelfHosted(origin, body, token, store, env) {
  try {
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/geo+json",
    };
    // The tunnel hostname is public — Cloudflare serves it to anyone who knows
    // the name — and ORS has no notion of auth. A gate at the origin checks
    // this header and 403s everything else.
    //
    // **Verified 2026-09-03: the gate holds.** Every unauthenticated request to
    // ors.workdocks.com is refused by nginx before it reaches ORS — GET and
    // POST, health and routing, all 403. So this is a shared secret rather than
    // an open door, and earlier wording in HANDOFF calling it "open routing for
    // anyone who finds it" was wrong.
    if (token) headers["X-Aimless-Origin"] = token;

    // Cloudflare Access service token, when one exists. Both secrets unset is
    // the current state and a deliberate no-op — sending nothing leaves the
    // nginx gate as the only check, which is exactly what is live today.
    //
    // This is here **before** the Access application exists so that turning
    // Access on is two `wrangler secret put` calls and no code change. The
    // dangerous ordering is the reverse: create the Access policy first and
    // every self-hosted request 403s until a deploy lands, which would drop the
    // whole country onto HeiGIT's 200/day in the meantime.
    if (env?.CF_ACCESS_CLIENT_ID && env?.CF_ACCESS_CLIENT_SECRET) {
      headers["CF-Access-Client-Id"] = env.CF_ACCESS_CLIENT_ID;
      headers["CF-Access-Client-Secret"] = env.CF_ACCESS_CLIENT_SECRET;
    }

    const response = await fetch(origin + ALLOWED_PATH, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(SELF_HOSTED_TIMEOUT_MS),
    });
    return response.status === 200 ? passThrough(response, "self", store) : null;
  } catch (e) {
    return null;
  }
}

/**
 * Reads the request's starting coordinate and says whether any covered region
 * contains it.
 *
 * Both request shapes the app sends put the origin first: `round_trip` sends a
 * single [lon, lat], and the verification reroute sends origin, waypoints, then
 * origin again. Note the order — GeoJSON is [longitude, latitude], which is the
 * reverse of how everyone says it out loud.
 *
 * Anything unparseable answers false and goes to HeiGIT. Guessing wrong in that
 * direction costs latency; guessing wrong the other way costs a wrong route.
 */
function originIsCovered(body, regions) {
  try {
    const first = JSON.parse(body)?.coordinates?.[0];
    if (!Array.isArray(first) || first.length < 2) return false;
    const [lon, lat] = first;
    return regions.some(
      (b) =>
        lon >= b.minLon && lon <= b.maxLon &&
        lat >= b.minLat && lat <= b.maxLat
    );
  } catch (e) {
    return false;
  }
}

/**
 * Status codes must pass through untouched. The client distinguishes 429 (rate
 * limited, tell the user to wait) from 404 and 5xx (one dead seed, swallow it
 * silently). Flattening those into a generic error would make a throttled round
 * indistinguishable from a round where nothing matched — exactly the bug the
 * client works hard to avoid.
 *
 * The body matters for the same reason: ORS puts a human-readable message in
 * `error.message` and the client surfaces it.
 *
 * Rate-limit headers are forwarded so quota is observable from a response
 * instead of guessed at. An earlier version rebuilt the response with only a
 * Content-Type and threw them away, which left us unable to answer "how close
 * to the limit are we" without arithmetic and assumptions.
 */
function passThrough(upstream, servedBy, store) {
  const headers = new Headers({
    "Content-Type":
      upstream.headers.get("Content-Type") ?? "application/geo+json",
    "Cache-Control": "no-store",
    "X-Aimless-Served-By": servedBy,
  });
  for (const [name, value] of upstream.headers) {
    if (name.toLowerCase().startsWith("x-ratelimit")) {
      headers.set(name, value);
    }
  }
  headers.set("X-Aimless-Cache", "miss");

  logOutcome({
    servedBy,
    status: upstream.status,
    cache: "miss",
    quotaRemaining: upstream.headers.get("x-ratelimit-remaining"),
    quotaLimit: upstream.headers.get("x-ratelimit-limit"),
  });

  // Only 200s are worth keeping. A 429 cached for a day would outlive the
  // minute it belongs to, and a 404 is one dead seed rather than a fact about
  // the route — caching either would turn a transient state into a permanent
  // one.
  // clone() before the body is read. Splitting the stream by hand instead
  // (tee, then reading upstream.body) locks the original and throws on every
  // single request.
  if (upstream.status === 200 && store) {
    const forCache = new Response(upstream.clone().body, {
      status: 200,
      headers: new Headers({
        "Content-Type": headers.get("Content-Type"),
        // The client copy says no-store; this stored copy is the one the edge
        // is allowed to keep, so it needs its own lifetime.
        "Cache-Control": `max-age=${CACHE_TTL_SECONDS}`,
        "X-Aimless-Served-By": servedBy,
      }),
    });
    store.ctx.waitUntil(store.cache.put(store.cacheKey, forCache));
  }

  return new Response(upstream.body, { status: upstream.status, headers });
}

/**
 * A stable cache key for a request body.
 *
 * The Cache API keys on URL, so the body is hashed into a synthetic one. The
 * hostname is deliberately unroutable — nothing ever fetches it, it exists only
 * to give the cache something to index.
 */
async function cacheKeyFor(body) {
  const digest = await crypto.subtle.digest(
    "SHA-256", new TextEncoder().encode(body));
  const hex = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return new Request(`https://aimless-cache.invalid/${hex}`, { method: "GET" });
}

/**
 * One line per request, so the next "nothing happened when we tapped generate"
 * can be answered from data instead of reconstructed from a screenshot.
 *
 * The three questions this has to answer are whether the app reached us at all,
 * what we replied, and how much upstream allowance was left — which is exactly
 * what could not be checked after the 2026-08-27 rejection, because the Worker
 * had no logs enabled at all.
 *
 * **No coordinates, and nothing derived from them beyond which backend
 * answered.** PRIVACY.md promises the Worker does not store the coordinates it
 * forwards, and a log line is storage. `servedBy` is the one location-adjacent
 * field here, it is coarse to the scale of a US state, and the privacy policy
 * names it explicitly.
 */
function logOutcome(fields) {
  console.log(JSON.stringify({ event: "route", ...fields }));
}

function json(status, message) {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

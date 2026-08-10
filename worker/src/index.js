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
 * New Jersey's bounding box, used to decide whether a request can be served by
 * our own routing instance.
 *
 * This is deliberately NJ and not the box our graph actually covers. The graph
 * holds NJ plus Pennsylvania, New York and Delaware, which puts its nearest
 * edge hundreds of kilometres from anywhere in New Jersey. That margin is the
 * point: a route generated near the edge of a graph gets silently clipped
 * against roads that stop existing, and returns a plausible-looking loop that
 * is simply too short. Measured from a NJ-only graph, an origin in the
 * north-west corner came back 19% short with no error at all.
 *
 * So: route locally only where we have room to spare, and let HeiGIT — who host
 * the whole planet — handle everywhere else.
 */
const NJ_BBOX = { minLon: -75.56, maxLon: -73.89, minLat: 38.93, maxLat: 41.36 };

/**
 * How long to wait on our own instance before giving up and using HeiGIT.
 *
 * Measured locally at 55-140ms per request, so a second is generous. It is
 * meant to catch a box that is wedged or reclaimed, not one that is briefly
 * busy — Oracle's free tier can shut down instances it considers idle, and that
 * must degrade to "slower" rather than "broken".
 */
const SELF_HOSTED_TIMEOUT_MS = 1000;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json(405, "Method not allowed");
    }

    const url = new URL(request.url);
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

    // Try our own instance first when one is configured and the route starts
    // somewhere it covers well. Unset SELF_HOSTED_ORIGIN and everything goes to
    // HeiGIT exactly as it always has — which is what makes deploying this safe
    // before any server exists.
    if (env.SELF_HOSTED_ORIGIN && originIsInNewJersey(body)) {
      const local = await trySelfHosted(env.SELF_HOSTED_ORIGIN, body);
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

    return passThrough(upstream, "heigit");
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
async function trySelfHosted(origin, body) {
  try {
    const response = await fetch(origin + ALLOWED_PATH, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/geo+json",
      },
      body,
      signal: AbortSignal.timeout(SELF_HOSTED_TIMEOUT_MS),
    });
    return response.status === 200 ? passThrough(response, "self") : null;
  } catch (e) {
    return null;
  }
}

/**
 * Reads the request's starting coordinate and says whether it's in New Jersey.
 *
 * Both request shapes the app sends put the origin first: `round_trip` sends a
 * single [lon, lat], and the verification reroute sends origin, waypoints, then
 * origin again. Note the order — GeoJSON is [longitude, latitude], which is the
 * reverse of how everyone says it out loud.
 *
 * Anything unparseable answers false and goes to HeiGIT. Guessing wrong in that
 * direction costs latency; guessing wrong the other way costs a wrong route.
 */
function originIsInNewJersey(body) {
  try {
    const first = JSON.parse(body)?.coordinates?.[0];
    if (!Array.isArray(first) || first.length < 2) return false;
    const [lon, lat] = first;
    return (
      lon >= NJ_BBOX.minLon &&
      lon <= NJ_BBOX.maxLon &&
      lat >= NJ_BBOX.minLat &&
      lat <= NJ_BBOX.maxLat
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
function passThrough(upstream, servedBy) {
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
  return new Response(upstream.body, { status: upstream.status, headers });
}

function json(status, message) {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

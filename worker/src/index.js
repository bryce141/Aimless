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

    // Status codes must pass through untouched. The client distinguishes 429
    // (rate limited, tell the user to wait) from 404 and 5xx (one dead seed,
    // swallow it silently). Flattening those into a generic error would make a
    // throttled round indistinguishable from a round where nothing matched —
    // exactly the bug the client works hard to avoid.
    //
    // The body matters for the same reason: ORS puts a human-readable message
    // in `error.message` and the client surfaces it.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "Content-Type":
          upstream.headers.get("Content-Type") ?? "application/geo+json",
        "Cache-Control": "no-store",
      },
    });
  },
};

function json(status, message) {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Template. Copy to Aimless/Config.swift and paste your client token.
// Aimless/Config.swift is gitignored; this file is not, so keep it tokenless.
//
// Sits at the repo root rather than inside Aimless/ so Xcode's synchronized
// folder doesn't compile it as a duplicate of the real Config.
//
// There is no OpenRouteService key here. The key lives in a Cloudflare Worker
// secret (`wrangler secret put ORS_API_KEY`) and never reaches the app. What
// the app carries is a token identifying it to that Worker — see worker/README.md
// for why that is not, and cannot be, a security boundary.

import Foundation

enum Config {
    static let clientToken = "PASTE_YOUR_WORKER_CLIENT_TOKEN_HERE"
}

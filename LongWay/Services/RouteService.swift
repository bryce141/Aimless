import CoreLocation
import Foundation

enum RouteServiceError: LocalizedError {
    /// Every seed failed. Distinct from "some failed", which is normal and swallowed.
    case allSeedsFailed(lastMessage: String?)
    /// ORS free tier allows 40 requests/minute. One generate costs ~18, so two
    /// back-to-back are fine and three are not.
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .allSeedsFailed(let msg):
            return "Couldn't build any loops from here. \(msg ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case .rateLimited:
            return "Hit the OpenRouteService rate limit. Wait a minute, then try again."
        }
    }
}

/// Results plus whether the round was degraded by rate limiting.
///
/// Worth threading through: a throttled round looks exactly like a round where
/// no loop matched, and telling the user "no loops near 2 hr" when the real
/// problem is "you asked three times in one minute" sends them chasing the
/// wrong thing.
struct RouteBatch<T> {
    let results: [T]
    let rateLimited: Bool
}

/// ORS client. Two jobs:
///
/// 1. `generateRoundTrips` — ask for candidate loops via `round_trip`.
/// 2. `drivenRoute` — re-route through a candidate's 8 waypoints, which is what
///    Google will do, and is therefore the route we actually show and time.
///
/// Neither knows about the duration picker. The duration-to-request-size table
/// lives in `DurationOption`, because no formula reliably maps one to the other.
struct RouteService {
    static let endpoint = URL(string:
        "https://api.openrouteservice.org/v2/directions/driving-car/geojson")!

    /// Do not lower this. At `points: 3` the generator produces spiky polygons
    /// with hairpins and backtracking, plus more highway.
    static let roundTripPoints = 8

    /// ORS rejects anything larger with HTTP 400 "Request parameters exceed the
    /// server configuration limits". Verified, not assumed.
    static let maxRequestMeters = 100_000

    let apiKey: String
    var session: URLSession = .shared

    // MARK: - Candidates

    /// Fires `seeds` round-trip requests concurrently and returns what came back.
    ///
    /// Individual failures are expected and swallowed — measured ~90% success,
    /// with failures clustering at the largest request sizes. Throws only if
    /// every seed failed.
    ///
    /// `firstSeed` matters more than it looks. A seed is not a dice roll: the
    /// same seed at the same origin and size returns the identical result every
    /// time, failures included. A retry that reuses seed numbers re-fetches the
    /// identical failures, so retries must ask for fresh ones.
    func generateRoundTrips(
        from origin: CLLocationCoordinate2D,
        requestMeters: Int,
        seeds: Int,
        firstSeed: Int = 1
    ) async throws -> RouteBatch<RoundTrip> {
        let meters = min(requestMeters, Self.maxRequestMeters)

        let results = await withTaskGroup(
            of: Result<RoundTrip, Error>.self
        ) { group -> [Result<RoundTrip, Error>] in
            for seed in firstSeed..<(firstSeed + max(seeds, 1)) {
                group.addTask {
                    do {
                        return .success(try await roundTrip(
                            origin: origin, meters: meters, seed: seed))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var out: [Result<RoundTrip, Error>] = []
            for await r in group { out.append(r) }
            return out
        }

        let errors = results.compactMap { r -> Error? in
            if case .failure(let e) = r { return e }
            return nil
        }
        let throttled = errors.contains { ($0 as? ORSHTTPError)?.isRateLimit == true }

        let trips = results.compactMap { try? $0.get() }
        guard !trips.isEmpty else {
            if throttled { throw RouteServiceError.rateLimited }
            throw RouteServiceError.allSeedsFailed(
                lastMessage: errors.last?.localizedDescription)
        }
        return RouteBatch(
            results: trips.sorted { $0.seed < $1.seed },
            rateLimited: throttled)
    }

    // MARK: - Verification

    /// Turns a candidate into the loop the user will drive.
    ///
    /// Downsamples to the handoff waypoints, then asks ORS for an ordinary
    /// point-to-point route through them — the same thing Google does with the
    /// URL we hand off. The returned duration, distance and road stats describe
    /// that rerouted path.
    func drivenRoute(for candidate: RoundTrip) async throws -> Loop {
        guard let origin = candidate.coordinates.first else {
            throw ORSHTTPError(status: 0, body: Data())
        }
        let waypoints = Handoff.waypoints(along: candidate.coordinates)
        guard !waypoints.isEmpty else {
            throw ORSHTTPError(status: 0, body: Data())
        }

        // origin -> each waypoint in order -> back to origin
        let path = [origin] + waypoints + [origin]
        let response = try await post(body: PathRequestBody(
            coordinates: path.map { [$0.longitude, $0.latitude] },
            extraInfo: ["waytype", "waycategory"],
            instructions: false))

        guard let feature = response.features.first,
              let summary = feature.properties.summary else {
            throw ORSHTTPError(status: 200, body: Data())
        }

        return Loop(
            seed: candidate.seed,
            coordinates: Self.coordinates(from: feature.geometry),
            waypoints: waypoints,
            distanceMeters: summary.distance,
            durationSeconds: summary.duration,
            roadStats: Self.roadStats(from: feature.properties.extras),
            plannedDurationSeconds: candidate.durationSeconds)
    }

    /// Verifies candidates concurrently, dropping any that fail.
    func drivenRoutes(for candidates: [RoundTrip]) async -> RouteBatch<Loop> {
        let results = await withTaskGroup(
            of: Result<Loop, Error>.self
        ) { group -> [Result<Loop, Error>] in
            for candidate in candidates {
                group.addTask {
                    do { return .success(try await drivenRoute(for: candidate)) }
                    catch { return .failure(error) }
                }
            }
            var out: [Result<Loop, Error>] = []
            for await r in group { out.append(r) }
            return out
        }

        let throttled = results.contains { r in
            if case .failure(let e) = r {
                return (e as? ORSHTTPError)?.isRateLimit == true
            }
            return false
        }
        return RouteBatch(
            results: results.compactMap { try? $0.get() },
            rateLimited: throttled)
    }

    // MARK: - Requests

    private func roundTrip(
        origin: CLLocationCoordinate2D,
        meters: Int,
        seed: Int
    ) async throws -> RoundTrip {
        let response = try await post(body: RoundTripRequestBody(
            coordinates: [[origin.longitude, origin.latitude]],
            options: .init(roundTrip: .init(
                length: meters, points: Self.roundTripPoints, seed: seed)),
            extraInfo: ["waytype", "waycategory"],
            instructions: false))

        guard let feature = response.features.first,
              let summary = feature.properties.summary else {
            throw ORSHTTPError(status: 200, body: Data())
        }
        let coords = Self.coordinates(from: feature.geometry)
        guard coords.count >= 2 else {
            throw ORSHTTPError(status: 200, body: Data())
        }

        return RoundTrip(
            seed: seed,
            coordinates: coords,
            distanceMeters: summary.distance,
            durationSeconds: summary.duration,
            roadStats: Self.roadStats(from: feature.properties.extras))
    }

    private func post<Body: Encodable>(body: Body) async throws -> ORSResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        // Swallow-worthy failures are both 404 "Route could not be found" and
        // 500 "Could not find a valid point after 3 tries". Treat any non-200
        // the same way: it's one dead seed, not a dead request.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ORSHTTPError(status: http.statusCode, body: data)
        }
        return try JSONDecoder().decode(ORSResponse.self, from: data)
    }

    // MARK: - Parsing

    static func coordinates(
        from geometry: ORSResponse.Geometry
    ) -> [CLLocationCoordinate2D] {
        geometry.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    /// waytype: 1 = state road, 2 = road, 3 = street. 2 and 3 are what we want.
    private static let backroadWaytypes: Set<Int> = [2, 3]
    private static let stateRoadWaytype = 1
    /// waycategory is a bitmask; bit 0 (value 1) is motorway.
    private static let highwayBit = 1

    static func roadStats(from extras: ORSResponse.Extras?) -> RoadStats {
        let waytype = distancesByValue(extras?.waytype)
        let waycategory = distancesByValue(extras?.waycategory)

        // waytype covers the whole route, so it's the denominator. waycategory
        // only reports categorized stretches and would undercount.
        let total = waytype.values.reduce(0, +)
        guard total > 0 else { return .zero }

        let highway = waycategory
            .filter { $0.key & highwayBit != 0 }
            .values.reduce(0, +)
        let backroad = waytype
            .filter { backroadWaytypes.contains($0.key) }
            .values.reduce(0, +)
        let stateRoad = waytype[stateRoadWaytype] ?? 0

        return RoadStats(
            highwayPct: highway / total,
            backroadPct: backroad / total,
            stateRoadPct: stateRoad / total)
    }

    private static func distancesByValue(
        _ block: ORSResponse.ExtraBlock?
    ) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for row in block?.summary ?? [] {
            out[Int(row.value), default: 0] += row.distance
        }
        return out
    }
}

// MARK: - Wire types

private struct RoundTripRequestBody: Encodable {
    let coordinates: [[Double]]   // [lon, lat] — not lat/lon
    let options: Options
    let extraInfo: [String]
    let instructions: Bool

    struct Options: Encodable {
        let roundTrip: RoundTrip
        struct RoundTrip: Encodable {
            let length: Int
            let points: Int
            let seed: Int
        }
    }
}

private struct PathRequestBody: Encodable {
    let coordinates: [[Double]]
    let extraInfo: [String]
    let instructions: Bool
}

struct ORSResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }
    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }
    struct Properties: Decodable {
        let summary: Summary?
        let extras: Extras?
    }
    struct Summary: Decodable {
        let distance: Double
        let duration: Double
    }
    struct Extras: Decodable {
        let waytype: ExtraBlock?
        let waycategory: ExtraBlock?
    }
    struct ExtraBlock: Decodable {
        let summary: [ExtraSummary]
    }
    struct ExtraSummary: Decodable {
        let value: Double
        let distance: Double
    }
}

struct ORSHTTPError: LocalizedError {
    let status: Int
    let body: Data

    var isRateLimit: Bool { status == 429 }

    var errorDescription: String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: body))?
            .error?.message
        return message ?? "HTTP \(status)"
    }
}

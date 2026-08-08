import CoreLocation
import Foundation

enum RouteServiceError: LocalizedError {
    /// Every seed failed. Distinct from "some failed", which is normal and swallowed.
    case allSeedsFailed(lastMessage: String?)

    var errorDescription: String? {
        switch self {
        case .allSeedsFailed(let msg):
            return "Couldn't build any loops from here. \(msg ?? "")"
                .trimmingCharacters(in: .whitespaces)
        }
    }
}

/// ORS round-trip client.
///
/// Takes a request size in meters. It does not know about the duration picker —
/// the duration-to-request-size table lives in the view model, because no
/// formula reliably maps one to the other. See longwayspecmvp.md.
struct RouteService {
    static let endpoint = URL(string:
        "https://api.openrouteservice.org/v2/directions/driving-car/geojson")!

    /// Do not lower this. At `points: 3` the generator produces spiky polygons
    /// with hairpins and backtracking, plus more highway.
    static let roundTripPoints = 8

    let apiKey: String
    var session: URLSession = .shared

    /// Fires `seeds` requests concurrently and returns whatever came back.
    ///
    /// Individual failures are expected and swallowed — measured 94% success at
    /// the Marlboro origin, with failures clustering at the largest request
    /// sizes. Throws only if every single seed failed.
    /// `firstSeed` lets the retry round ask for genuinely new seeds instead of
    /// re-rolling the same ones.
    func generateLoops(
        from origin: CLLocationCoordinate2D,
        requestMeters: Int,
        seeds: Int,
        firstSeed: Int = 1
    ) async throws -> [Loop] {
        let results = await withTaskGroup(
            of: Result<Loop, Error>.self
        ) { group -> [Result<Loop, Error>] in
            for seed in firstSeed..<(firstSeed + max(seeds, 1)) {
                group.addTask {
                    do {
                        return .success(try await fetch(
                            origin: origin, meters: requestMeters, seed: seed))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var out: [Result<Loop, Error>] = []
            for await r in group { out.append(r) }
            return out
        }

        let loops = results.compactMap { try? $0.get() }
        guard !loops.isEmpty else {
            let last = results.compactMap { r -> String? in
                if case .failure(let e) = r { return e.localizedDescription }
                return nil
            }.last
            throw RouteServiceError.allSeedsFailed(lastMessage: last)
        }
        return loops.sorted { $0.seed < $1.seed }
    }

    // MARK: - One request

    private func fetch(
        origin: CLLocationCoordinate2D,
        meters: Int,
        seed: Int
    ) async throws -> Loop {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(RequestBody(
            coordinates: [[origin.longitude, origin.latitude]],
            options: .init(roundTrip: .init(
                length: meters, points: Self.roundTripPoints, seed: seed)),
            extraInfo: ["waytype", "waycategory"],
            instructions: false))

        let (data, response) = try await session.data(for: request)

        // Swallow-worthy failures are both 404 "Route could not be found" and
        // 500 "Could not find a valid point after 3 tries". Treat any non-200
        // the same way: it's one dead seed, not a dead request.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ORSHTTPError(status: http.statusCode, body: data)
        }

        let decoded = try JSONDecoder().decode(ORSResponse.self, from: data)
        guard let loop = Self.makeLoop(from: decoded, seed: seed) else {
            throw ORSHTTPError(status: 200, body: data)
        }
        return loop
    }

    static func makeLoop(from response: ORSResponse, seed: Int) -> Loop? {
        guard let feature = response.features.first,
              let summary = feature.properties.summary else { return nil }

        let coords = feature.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard coords.count >= 2 else { return nil }

        return Loop(
            seed: seed,
            coordinates: coords,
            distanceMeters: summary.distance,
            durationSeconds: summary.duration,
            roadStats: roadStats(from: feature.properties.extras))
    }

    // MARK: - Road classification

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

private struct RequestBody: Encodable {
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

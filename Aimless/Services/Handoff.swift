import CoreLocation
import Foundation

/// Builds the Google Maps handoff URL.
///
/// We are not writing navigation. There is deliberately no Apple Maps fallback —
/// Apple exposes no multi-stop routing API, and a single-destination fallback
/// would navigate the user to where they already are. See SPEC.md.
enum Handoff {
    /// Google's URL API accepts around 9 stops. Origin and destination are both
    /// the loop start, leaving room for 8 interior waypoints. Tested at 70km.
    static let waypointCount = 8

    /// Walks the polyline and takes a point every `total / (count + 1)` meters,
    /// yielding exactly `count` interior waypoints.
    ///
    /// Required: the ORS geometry has thousands of points and the URL API
    /// cannot take them.
    static func waypoints(
        along coordinates: [CLLocationCoordinate2D],
        count: Int = waypointCount
    ) -> [CLLocationCoordinate2D] {
        guard count > 0, coordinates.count > 2 else { return [] }

        let locations = coordinates.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        var cumulative: [CLLocationDistance] = [0]
        cumulative.reserveCapacity(locations.count)
        for i in 1..<locations.count {
            cumulative.append(
                cumulative[i - 1] + locations[i].distance(from: locations[i - 1]))
        }
        guard let total = cumulative.last, total > 0 else { return [] }

        let step = total / Double(count + 1)
        var out: [CLLocationCoordinate2D] = []
        var cursor = 1

        for k in 1...count {
            let target = step * Double(k)
            while cursor < cumulative.count - 1 && cumulative[cursor] < target {
                cursor += 1
            }
            // Interpolate between the bracketing vertices so waypoints land on
            // the line rather than snapping to whichever vertex is nearest.
            let prev = cursor - 1
            let span = cumulative[cursor] - cumulative[prev]
            let t = span > 0 ? (target - cumulative[prev]) / span : 0
            let a = coordinates[prev], b = coordinates[cursor]
            out.append(CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t))
        }
        return out
    }

    /// Universal link form — works whether or not the Google Maps app is
    /// installed. If it isn't, this opens in Safari, which still works.
    ///
    /// Uses the waypoints already stored on the loop rather than re-downsampling
    /// its polyline. The loop's polyline *is* the route through those waypoints,
    /// so downsampling it again would hand Google a different set of stops than
    /// the ones we timed and drew.
    static func googleMapsURL(for loop: Loop) -> URL? {
        guard let start = loop.start else { return nil }
        return googleMapsURL(start: start, waypoints: loop.waypoints)
    }

    static func googleMapsURL(
        start: CLLocationCoordinate2D,
        waypoints: [CLLocationCoordinate2D]
    ) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        let origin = format(start)
        var query = "api=1&origin=\(origin)&destination=\(origin)&travelmode=driving"
        if !waypoints.isEmpty {
            // "|" must be encoded; URLComponents won't do it in a query value.
            query += "&waypoints=" + waypoints.map(format).joined(separator: "%7C")
        }
        components?.percentEncodedQuery = query
        return components?.url
    }

    private static func format(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }
}

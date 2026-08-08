import CoreLocation
import Foundation

/// A raw ORS `round_trip` result — a **candidate**, not something we show.
///
/// This is not the route the user drives. Google reroutes between the handful of
/// waypoints we hand it, and that rerouted path runs 72-82% of this one's
/// duration because it cuts corners onto straighter roads. So a round trip is
/// only ever an input: we downsample it, re-route through the waypoints, and the
/// result of *that* is the `Loop` we display.
///
/// Kept separate from `Loop` on purpose. Conflating the two is what let the app
/// display a duration nobody would actually drive.
struct RoundTrip {
    let seed: Int
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: Double
    let roadStats: RoadStats

    var durationMinutes: Double { durationSeconds / 60 }

    /// Rough guess at what this will become once rerouted, used only to decide
    /// which candidates are worth spending a verification request on.
    /// Measured ratio was 72-82% across every request size from 63km to 100km.
    static let drivenDurationRatio = 0.75

    var estimatedDrivenMinutes: Double { durationMinutes * Self.drivenDurationRatio }
}

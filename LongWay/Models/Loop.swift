import CoreLocation
import Foundation

/// A loop as the user will actually drive it.
///
/// Every number here describes the **rerouted** path through the 8 handoff
/// waypoints, not the ORS round trip that produced it. That's the whole point:
/// the polyline we draw, the duration we print, and the route Google builds are
/// all the same thing.
///
/// The round trip's own duration is kept as `plannedDurationSeconds` for
/// diagnostics only. Never show it — it overstates the drive by 20-30%.
struct Loop: Identifiable {
    let id = UUID()
    let seed: Int

    /// The rerouted polyline. This is what goes on the map.
    let coordinates: [CLLocationCoordinate2D]
    /// The stops handed to Google. Already computed, so the handoff doesn't
    /// re-downsample and risk drifting from what we displayed.
    let waypoints: [CLLocationCoordinate2D]

    let distanceMeters: Double
    let durationSeconds: Double
    let roadStats: RoadStats

    /// The originating round trip's duration. Diagnostics only.
    let plannedDurationSeconds: Double

    var distanceMiles: Double { distanceMeters / 1609.344 }
    var durationMinutes: Double { durationSeconds / 60 }

    /// Where the loop starts and ends.
    var start: CLLocationCoordinate2D? { coordinates.first }
}

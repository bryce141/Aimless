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

    /// Fraction of the drive spent on road covered on a separate pass, 0...1.
    ///
    /// Computed from `coordinates` at construction — it describes the rerouted
    /// path like every other number here, not the round trip that produced it.
    ///
    /// The App Store description promises loops that come back "without
    /// retracing themselves" and nothing verified it until now. Measured
    /// 2026-09-04: median 7.8% at the 30-minute size against 3.5% at 120, and
    /// **18.9% at 30 minutes in Marlboro.** See HANDOFF.md.
    let retraceFraction: Double

    var distanceMiles: Double { distanceMeters / 1609.344 }
    var durationMinutes: Double { durationSeconds / 60 }
    var retracePct: Double { retraceFraction * 100 }

    /// Whether the repeated road is worth telling the user about.
    ///
    /// 10% is where the map starts visibly drawing over itself. Below it the
    /// doubled stretch is a corner or a short connector and calling it out
    /// would be noise.
    var hasNotableRetrace: Bool { retraceFraction >= 0.10 }

    /// Where the loop starts and ends.
    var start: CLLocationCoordinate2D? { coordinates.first }
}

import CoreLocation
import Foundation

/// One generated round trip.
///
/// `durationSeconds` comes straight from ORS and is the only trustworthy time
/// estimate available — neither the request size nor the returned distance
/// predicts drive time. See the duration-variance finding in longwayspecmvp.md.
struct Loop: Identifiable {
    let id = UUID()
    let seed: Int
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: Double
    let roadStats: RoadStats

    var distanceMiles: Double { distanceMeters / 1609.344 }
    var distanceKm: Double { distanceMeters / 1000 }
    var durationMinutes: Double { durationSeconds / 60 }

    /// Where the loop starts and ends. Loops are closed, so this is also the
    /// destination for the Google Maps handoff.
    var start: CLLocationCoordinate2D? { coordinates.first }
}

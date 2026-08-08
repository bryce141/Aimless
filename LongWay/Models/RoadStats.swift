import Foundation

/// Road-class breakdown for a loop, as fractions of total distance (0...1).
///
/// Derived from ORS `extras.waytype` and `extras.waycategory`. Per the spec,
/// highway share is the only signal worth filtering on: in New Jersey "state
/// road" lumps Route 9 in with pleasant county roads, so it's reported for
/// display but not used to reject anything.
struct RoadStats: Equatable {
    let highwayPct: Double
    let backroadPct: Double
    let stateRoadPct: Double

    static let zero = RoadStats(highwayPct: 0, backroadPct: 0, stateRoadPct: 0)
}

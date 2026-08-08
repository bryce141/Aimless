import Foundation

/// Filters and ranks raw candidates.
///
/// Filters on **duration, not distance**. The user picks minutes, so minutes is
/// what we judge against — and ORS hands us a duration in every response, which
/// is the only trustworthy estimate we have. Request size and returned distance
/// both fail to predict drive time (the same 13km request returned drives from
/// 40 to 90 minutes).
enum LoopScorer {
    /// Well calibrated, leave it. Rejects exactly the blowout seeds, which are
    /// the same ones that overshoot distance badly.
    static let maxHighwayShare = 0.15

    static let tolerance = 0.25
    /// Used on the retry round rather than firing the same filter at new seeds.
    static let widenedTolerance = 0.40

    static let desiredCount = 3

    static func rank(
        _ loops: [Loop],
        targetMinutes: Double,
        tolerance: Double = tolerance
    ) -> [Loop] {
        let low = targetMinutes * (1 - tolerance)
        let high = targetMinutes * (1 + tolerance)

        return loops
            .filter { $0.roadStats.highwayPct <= maxHighwayShare }
            .filter { (low...high).contains($0.durationMinutes) }
            .sorted { a, b in
                // Most candidates come back at exactly 0% highway, so in
                // practice duration closeness is what does the ordering.
                if a.roadStats.highwayPct != b.roadStats.highwayPct {
                    return a.roadStats.highwayPct < b.roadStats.highwayPct
                }
                return abs(a.durationMinutes - targetMinutes)
                     < abs(b.durationMinutes - targetMinutes)
            }
    }

    static func top(
        _ loops: [Loop],
        targetMinutes: Double,
        tolerance: Double = tolerance
    ) -> [Loop] {
        Array(rank(loops, targetMinutes: targetMinutes, tolerance: tolerance)
            .prefix(desiredCount))
    }
}

import Foundation

/// Filters and ranks.
///
/// Filters on **duration, not distance**. The user picks minutes, so minutes is
/// what we judge against. Request size and returned distance both fail to
/// predict drive time (the same 13km request returned drives from 40 to 90
/// minutes), so the only usable number is the one ORS returns.
///
/// Note `rank` runs on `Loop`, which is the *driven* route. Candidates get a
/// cheap `worthVerifying` pass first so we only spend a verification request on
/// the ones that might survive.
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

    // MARK: - Candidate pre-filter

    /// Verification costs one request per candidate, so don't spend it on
    /// obvious losers. Deliberately looser than the real filters, because a
    /// candidate's round-trip numbers only approximate its driven ones.
    static let candidateMaxHighwayShare = 0.20
    static let candidateTolerance = 0.45
    /// Cap on verification requests per round.
    static let maxToVerify = 6

    /// Picks which candidates are worth a verification request, best first.
    ///
    /// Measured: a candidate's driven highway share tracks its round-trip share
    /// closely but usually runs a little higher, hence the 20% gate against a
    /// 15% final one.
    static func worthVerifying(
        _ candidates: [RoundTrip],
        targetMinutes: Double
    ) -> [RoundTrip] {
        let low = targetMinutes * (1 - candidateTolerance)
        let high = targetMinutes * (1 + candidateTolerance)

        return candidates
            .filter { $0.roadStats.highwayPct <= candidateMaxHighwayShare }
            .filter { (low...high).contains($0.estimatedDrivenMinutes) }
            .sorted {
                abs($0.estimatedDrivenMinutes - targetMinutes)
              < abs($1.estimatedDrivenMinutes - targetMinutes)
            }
            .prefix(maxToVerify)
            .map { $0 }
    }
}

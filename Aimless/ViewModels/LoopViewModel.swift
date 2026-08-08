import CoreLocation
import Observation

@Observable
@MainActor
final class LoopViewModel {
    /// Not driven by HTTP failures, which are uncommon, but by spread — only
    /// some candidates land near the target once rerouted. In-band rates ran
    /// around 40-60% depending on size, so 12 clears 3 survivors.
    static let seedsPerRound = 12

    var duration: DurationOption = .sixty
    var loops: [Loop] = []
    var isGenerating = false
    var errorMessage: String?

    private let service = RouteService(clientToken: Config.clientToken)

    var hasResults: Bool { !loops.isEmpty }

    /// Two phases per round:
    ///
    /// 1. Ask for 12 round-trip candidates.
    /// 2. Verify the promising ones by rerouting through their handoff
    ///    waypoints, which is what Google will do. Those rerouted routes are
    ///    what we filter, rank, draw and time.
    ///
    /// Roughly 18 requests per generate. The free tier allows 40/minute, so two
    /// back-to-back generates are fine and a third will be throttled.
    func generate(from origin: CLLocationCoordinate2D) async {
        isGenerating = true
        errorMessage = nil
        loops = []
        defer { isGenerating = false }

        let meters = duration.requestMeters
        let target = duration.minutes
        var throttled = false

        do {
            let batch = try await service.generateRoundTrips(
                from: origin, requestMeters: meters, seeds: Self.seedsPerRound)
            throttled = batch.rateLimited

            var candidates = batch.results
            var verified = await verify(candidates,
                                        targetMinutes: target,
                                        throttled: &throttled)
            var ranked = LoopScorer.top(verified, targetMinutes: target)

            // A retry round costs about a second. Ask for *fresh* seeds — the
            // same seed at the same origin and size returns an identical result
            // every time, so re-rolling 1...12 would change nothing.
            //
            // Skipped when already throttled: another 18 requests into a rate
            // limit just burns quota and returns nothing.
            if ranked.count < LoopScorer.desiredCount && !throttled {
                if let more = try? await service.generateRoundTrips(
                    from: origin,
                    requestMeters: meters,
                    seeds: Self.seedsPerRound,
                    firstSeed: Self.seedsPerRound + 1) {
                    throttled = throttled || more.rateLimited
                    candidates += more.results
                    verified += await verify(more.results,
                                             targetMinutes: target,
                                             throttled: &throttled)
                }
                ranked = LoopScorer.top(
                    verified,
                    targetMinutes: target,
                    tolerance: LoopScorer.widenedTolerance)
            }

            if ranked.isEmpty {
                errorMessage = if throttled {
                    RouteServiceError.rateLimited.localizedDescription
                } else if candidates.isEmpty {
                    "Couldn't build any loops from here."
                } else {
                    "Found loops, but none close to \(duration.label). Try a different length."
                }
            }
            loops = ranked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify(
        _ candidates: [RoundTrip],
        targetMinutes: Double,
        throttled: inout Bool
    ) async -> [Loop] {
        let batch = await service.drivenRoutes(for:
            LoopScorer.worthVerifying(candidates, targetMinutes: targetMinutes))
        throttled = throttled || batch.rateLimited
        return batch.results
    }
}

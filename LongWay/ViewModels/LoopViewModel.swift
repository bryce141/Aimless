import CoreLocation
import Observation

@Observable
@MainActor
final class LoopViewModel {
    /// Not driven by HTTP failures, which are rare (94% success measured), but
    /// by duration spread. In-band rates at +/-25% ran around 60%, so 12 seeds
    /// clears 3 survivors comfortably — and costs 1 to 2 seconds, since ORS
    /// responds in well under a second.
    static let seedsPerRound = 12

    var duration: DurationOption = .sixty
    var loops: [Loop] = []
    var isGenerating = false
    var errorMessage: String?

    private let service = RouteService(apiKey: Config.orsAPIKey)

    var hasResults: Bool { !loops.isEmpty }

    func generate(from origin: CLLocationCoordinate2D) async {
        isGenerating = true
        errorMessage = nil
        loops = []
        defer { isGenerating = false }

        let meters = duration.requestMeters
        let target = duration.minutes

        do {
            var candidates = try await service.generateLoops(
                from: origin, requestMeters: meters, seeds: Self.seedsPerRound)
            var ranked = LoopScorer.top(candidates, targetMinutes: target)

            // A retry round costs about a second, so it's cheap. Widen the band
            // over the combined pool rather than re-running the same filter.
            if ranked.count < LoopScorer.desiredCount {
                let more = try? await service.generateLoops(
                    from: origin,
                    requestMeters: meters,
                    seeds: Self.seedsPerRound,
                    firstSeed: Self.seedsPerRound + 1)
                candidates += more ?? []
                ranked = LoopScorer.top(
                    candidates,
                    targetMinutes: target,
                    tolerance: LoopScorer.widenedTolerance)
            }

            if ranked.isEmpty {
                errorMessage = candidates.isEmpty
                    ? "Couldn't build any loops from here."
                    : "Found loops, but none close to \(duration.label). Try a different length."
            }
            loops = ranked
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

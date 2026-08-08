import Foundation

/// The duration picker.
///
/// **The floor is 60 minutes, and that's deliberate.** A real 30-minute drive
/// needs roughly a 4km request, and those loops spend 87% of their length within
/// 2km of the start — a lap around the block. That isn't a bug to fix, it's what
/// a 30-minute round trip from a fixed origin geometrically is.
///
/// `requestMeters` is a **measured** lookup, not a computed one. Don't replace it
/// with a speed constant: back roads run 25-44 km/h depending on loop size, and
/// ORS overshoots the requested length by 1.4x to 3.2x depending on size. Two
/// wrong constants multiplied together is how "30 minutes" became 62 minutes.
///
/// The table only has to land in the right ballpark — `LoopScorer` does the real
/// work by filtering on the duration ORS returns.
enum DurationOption: Int, CaseIterable, Identifiable {
    case sixty = 60
    case ninety = 90
    case twoHours = 120

    var id: Int { rawValue }
    var minutes: Double { Double(rawValue) }
    var label: String { self == .twoHours ? "2 hr" : "\(rawValue) min" }

    /// Sized to hit the target as a **driven** duration, not as a round-trip
    /// duration. The rerouted path runs 72-82% of the round trip, so the
    /// candidates have to be correspondingly larger.
    ///
    /// 120 is measured directly: an 85km request produced a median driven
    /// duration of 116 min. 60 and 90 are derived from the measured ratio.
    /// `LoopScorer` filters on the real driven duration, so table error costs
    /// candidates, not accuracy.
    ///
    /// Do not raise past 100km — ORS rejects it with HTTP 400. Verified.
    var requestMeters: Int {
        switch self {
        case .sixty:    return 33_000
        case .ninety:   return 70_000
        case .twoHours: return 85_000   // -> median 116 min driven
        }
    }
}

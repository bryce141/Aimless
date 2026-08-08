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

    /// Measured medians at the Marlboro origin. 60 and 120 are measured
    /// directly; 90 is interpolated between measured points at 31km and 47km.
    var requestMeters: Int {
        switch self {
        case .sixty:    return 14_000   // -> ~26 km, ~61 min
        case .ninety:   return 34_000   // -> ~55 km, ~90 min
        case .twoHours: return 63_000   // -> ~84 km, ~113 min
        }
    }
}

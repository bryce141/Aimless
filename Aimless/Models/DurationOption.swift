import Foundation

/// The duration picker.
///
/// **The floor is 30 minutes as of 2026-09-02.** It used to be 60, on the
/// grounds that a 30-minute loop stays within 2km of the start — a lap around
/// the block. That geometry is real and unchanged; what changed is that it is
/// the *point* for a test drive, where you have to hand the car back. Measured
/// at 6,500 m: ~27 min driven, 15.5 km, never more than 3.6 km from the start.
///
/// Do not lower it further. At the sizes that land near 20 minutes the whole
/// drive sits inside a 1.2 km radius, which is a circuit of your own street.
///
/// `requestMeters` is a **measured** lookup, not a computed one. Don't replace it
/// with a speed constant: back roads run 25-44 km/h depending on loop size, and
/// ORS overshoots the requested length by 1.4x to 3.2x depending on size. Two
/// wrong constants multiplied together is how "30 minutes" became 62 minutes.
///
/// **`.neighborhood` is a different drive, not a different length** (added
/// 2026-10-01, for Christmas-lights drives): a ~45-minute tour through *other*
/// neighbourhoods. A 15-minute version was tried first and rejected by Bryce
/// on the phone: it circled his own street. Its handoff stops are placed on
/// residential street (`Handoff.residentialWaypoints`) and loops are picked and
/// ranked by residential share (`prefersStreets`).
///
/// Measured over 12 origins through the full pipeline: 29% of the drive on
/// residential street against ~12% for an ordinary loop this size, median 41
/// min, no empty results. **That ceiling is structural:** ORS builds loops from
/// fastest roads and Google drives fastest roads between stops, so main roads
/// connect the neighbourhoods. A server-side "prefer residential" custom model
/// needs a full graph rebuild (`enable_custom_models`) and would still lose
/// to Google between stops; not worth it. See HANDOFF.md.
///
/// The table only has to land in the right ballpark — `LoopScorer` does the real
/// work by filtering on the duration ORS returns.
enum DurationOption: Int, CaseIterable, Identifiable {
    /// First, so it sits at the left end of the slider: a mode, not a length.
    /// The raw value is the target in minutes at ORS speeds.
    case neighborhood = 45
    case thirty = 30
    case sixty = 60
    case ninety = 90
    case twoHours = 120

    var id: Int { rawValue }
    var minutes: Double { Double(rawValue) }
    var label: String { self == .twoHours ? "2 hr" : "\(rawValue) min" }

    /// Rank loops by share of residential street rather than by closeness to
    /// the target time.
    var prefersStreets: Bool { self == .neighborhood }

    /// How a person would say it. "90 min" is a spec; "1½ hours" is a plan for
    /// the afternoon. Used for the big readout above the slider.
    var spokenLabel: String {
        switch self {
        case .neighborhood: return "Neighborhood"
        case .thirty:   return "30 minutes"
        case .sixty:    return "1 hour"
        case .ninety:   return "1½ hours"
        case .twoHours: return "2 hours"
        }
    }

    /// Short form for the slider's tick marks, where space is tight.
    var tickLabel: String {
        switch self {
        case .neighborhood: return "Near"
        case .thirty:   return "30m"
        case .sixty:    return "1 hr"
        case .ninety:   return "1½"
        case .twoHours: return "2 hr"
        }
    }

    /// Sized to hit the target as a **driven** duration, not as a round-trip
    /// duration. The rerouted path runs 72-82% of the round trip, so the
    /// candidates have to be correspondingly larger.
    ///
    /// 120 is measured directly: an 85km request produced a median driven
    /// duration of 116 min. 60 and 90 are derived from the measured ratio.
    /// `LoopScorer` filters on the real driven duration, so table error costs
    /// candidates, not accuracy.
    ///
    /// 30 is measured directly too, on 2026-09-02: 24 seeds each at 5.0 / 5.5 /
    /// 6.0 / 6.5 / 7.0 km through the full two-stage pipeline — round trip,
    /// downsample to the 8 handoff waypoints, reroute, take *that* duration.
    /// 6,500 m won on in-band survival at 50%, or 6 of 12 seeds against a
    /// `desiredCount` of 3. For comparison the shipped rows survive at 62% (60),
    /// 38% (90) and 29% (120). Median lands at 27.4 min rather than 30, which is
    /// well inside the ±25% band; centring it costs 12 points of survival and is
    /// not worth it. Differences between 5.0 and 6.5 km were inside the noise at
    /// 24 seeds, so don't re-tune this without many more.
    ///
    /// Do not raise past 100km — ORS rejects it with HTTP 400. Verified.
    var requestMeters: Int {
        switch self {
        case .neighborhood: return 15_000  // -> median 41 min, residential stops, 2026-10-01
        case .thirty:   return 6_500   // -> median 27.4 min driven, 50% in band
        case .sixty:    return 33_000
        case .ninety:   return 70_000
        case .twoHours: return 85_000   // -> median 116 min driven
        }
    }
}

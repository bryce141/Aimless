import CoreLocation
import Foundation

// Cross-checks Geometry.swift against tools/measure-geometry.py on real ORS
// routes. Two independent implementations agreeing on real data beats any
// hand-written fixture. Run: tools/geometry-check/run.sh

struct Fixture: Decodable {
    let name: String
    let coordinates: [[Double]]   // GeoJSON [lon, lat]
    let retrace: Double           // percent, from Python
    let curviness: Double         // deg/mile, from Python
    let points: Int
}

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "fixtures.json"

guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    exit(2)
}
let fixtures = try JSONDecoder().decode([Fixture].self, from: data)

// Tolerances. These are two implementations of the same algorithm in different
// languages, so agreement should be near-exact; anything looser than this would
// be hiding a real divergence rather than absorbing float noise.
let retraceTolerance = 0.01    // percentage points
let curvinessTolerance = 0.05  // degrees per mile

var failures: [String] = []
var maxRetraceDelta = 0.0
var maxCurvinessDelta = 0.0

for f in fixtures {
    let coords = f.coordinates.map {
        CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
    }

    let swiftRetrace = Geometry.retraceFraction(coords) * 100
    let swiftCurviness = Geometry.curvinessDegreesPerMile(coords)

    let dR = abs(swiftRetrace - f.retrace)
    let dC = abs(swiftCurviness - f.curviness)
    maxRetraceDelta = max(maxRetraceDelta, dR)
    maxCurvinessDelta = max(maxCurvinessDelta, dC)

    if dR > retraceTolerance {
        failures.append(String(
            format: "%@  retrace: swift %.4f%%  python %.4f%%  Δ%.4f",
            f.name, swiftRetrace, f.retrace, dR))
    }
    if dC > curvinessTolerance {
        failures.append(String(
            format: "%@  curviness: swift %.3f  python %.3f  Δ%.3f",
            f.name, swiftCurviness, f.curviness, dC))
    }
}

let totalPoints = fixtures.reduce(0) { $0 + $1.points }
print("fixtures: \(fixtures.count)   points: \(totalPoints)")
print(String(format: "max Δ retrace:   %.6f pp (tolerance %.2f)",
             maxRetraceDelta, retraceTolerance))
print(String(format: "max Δ curviness: %.6f deg/mi (tolerance %.2f)",
             maxCurvinessDelta, curvinessTolerance))

// Degenerate inputs must not crash or produce nonsense. The retrace filter is
// a new way for the app to show nothing, and an empty or 2-point polyline
// reaching it should return 0, not trap.
let edge: [(String, [CLLocationCoordinate2D])] = [
    ("empty", []),
    ("single", [CLLocationCoordinate2D(latitude: 40.4, longitude: -74.3)]),
    ("two identical", Array(repeating:
        CLLocationCoordinate2D(latitude: 40.4, longitude: -74.3), count: 2)),
    ("ten identical", Array(repeating:
        CLLocationCoordinate2D(latitude: 40.4, longitude: -74.3), count: 10)),
]
for (label, coords) in edge {
    let r = Geometry.retraceFraction(coords)
    let c = Geometry.curvinessDegreesPerMile(coords)
    guard r.isFinite, c.isFinite, r >= 0, r <= 1, c >= 0 else {
        failures.append("edge case '\(label)': retrace=\(r) curviness=\(c)")
        continue
    }
}

// An out-and-back on one road is 100% retrace by definition. This is the case
// the whole feature exists for, so it is asserted rather than assumed.
var outAndBack: [CLLocationCoordinate2D] = []
for i in 0...200 {
    outAndBack.append(CLLocationCoordinate2D(
        latitude: 40.4 + Double(i) * 0.0009, longitude: -74.3))
}
outAndBack += outAndBack.reversed()
let oab = Geometry.retraceFraction(outAndBack) * 100
print(String(format: "synthetic out-and-back retrace: %.1f%% (expect ~100)", oab))
if oab < 95 {
    failures.append(String(format: "out-and-back scored %.1f%%, expected ~100%%", oab))
}

// A straight line must be ~0 curviness and 0 retrace.
let straight = (0...200).map {
    CLLocationCoordinate2D(latitude: 40.4 + Double($0) * 0.0009, longitude: -74.3)
}
let sc = Geometry.curvinessDegreesPerMile(straight)
let sr = Geometry.retraceFraction(straight) * 100
print(String(format: "synthetic straight line: %.3f deg/mi, %.1f%% retrace (expect ~0, 0)", sc, sr))
if sc > 1.0 { failures.append(String(format: "straight line scored %.3f deg/mi", sc)) }
if sr > 0.01 { failures.append(String(format: "straight line retrace %.3f%%", sr)) }

print("")
if failures.isEmpty {
    print("PASS — Swift and Python agree on all \(fixtures.count) real loops")
    exit(0)
} else {
    print("FAIL — \(failures.count) disagreement(s):")
    for f in failures.prefix(25) { print("  \(f)") }
    exit(1)
}

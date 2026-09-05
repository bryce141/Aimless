import CoreLocation
import Foundation

/// Shape measurements on a finished `Loop` polyline.
///
/// Both functions are **pure** — coordinates in, number out, no network and no
/// state. That matters for two reasons: they are the only part of tasks 13-15
/// testable without Xcode (`tools/geometry-check/`, cross-checked against
/// `tools/measure-geometry.py` on real routes), and the layer they live in has
/// never once caused an App Review rejection. See HANDOFF.md,
/// "Retrace and reversal, measured 2026-09-04".
enum Geometry {

    // MARK: - Retrace

    /// Grid cell size for retrace detection. 25 m is a compromise: small enough
    /// that two genuinely different parallel roads land in different cells,
    /// large enough that GPS-level jitter on one pass does not.
    static let retraceGridMeters = 25.0

    /// A cell's point indices must jump by more than this to count as a
    /// *separate* pass rather than the route continuing through it.
    static let retraceRunGap = 3

    /// Fraction of driven length spent on road covered on a separate pass, 0...1.
    ///
    /// The app promises loops that come back "without retracing themselves" and
    /// has never verified it. This is that check.
    ///
    /// **Both passes are counted**, which is what makes the number mean "this
    /// much of your drive is repeated road" rather than "this much road is
    /// repeated". That matches the 11%-at-4km figure in SPEC.md's Known floors.
    ///
    /// Approximate by construction — treat ±2 points as noise. Measured on 113
    /// real loops: median 7.8% at the 30-minute size against 3.5% at 120, and
    /// **18.9% at 30 minutes in Marlboro specifically.**
    static func retraceFraction(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        let repeated = retracedPointIndices(coordinates)
        guard !repeated.isEmpty else { return 0 }

        var total = 0.0, doubled = 0.0
        for i in 0..<(coordinates.count - 1) {
            let d = distance(coordinates[i], coordinates[i + 1])
            total += d
            if repeated.contains(i) { doubled += d }
        }
        return total > 0 ? doubled / total : 0
    }

    /// The doubled stretches, as drawable polylines.
    ///
    /// This is what makes the retrace legible instead of merely counted: on a
    /// repeated stretch the route draws over itself and reads as a single
    /// straight line, with nothing to say it is two passes. Drawing these on top
    /// in another colour is the fix.
    ///
    /// Runs shorter than `minDrawableRun` points are dropped — a two-point
    /// speck is visual noise at any zoom the loop is viewed at.
    static let minDrawableRun = 3

    static func retracedSegments(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [[CLLocationCoordinate2D]] {
        let repeated = retracedPointIndices(coordinates)
        guard !repeated.isEmpty else { return [] }

        var out: [[CLLocationCoordinate2D]] = []
        var run: [CLLocationCoordinate2D] = []

        for i in 0..<coordinates.count {
            if repeated.contains(i) {
                run.append(coordinates[i])
            } else if !run.isEmpty {
                // Carry one extra vertex so the highlight meets the base line
                // instead of stopping a segment short of it.
                run.append(coordinates[i])
                if run.count >= minDrawableRun { out.append(run) }
                run = []
            }
        }
        if run.count >= minDrawableRun { out.append(run) }
        return out
    }

    /// Indices of points sitting in a cell the route enters on two separate
    /// passes. Shared by `retraceFraction` and `retracedSegments` so the number
    /// on screen and the line on the map can never disagree.
    private static func retracedPointIndices(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> Set<Int> {
        guard coordinates.count >= 3 else { return [] }

        // Cell size in degrees, fixed at the loop's own latitude. A loop never
        // spans enough latitude for the longitude scale to drift meaningfully,
        // and holding it constant keeps the grid square rather than sheared.
        let latRef = coordinates[0].latitude
        let dLat = retraceGridMeters / 111_320.0
        let dLon = retraceGridMeters
            / (111_320.0 * max(0.2, cos(latRef * .pi / 180)))

        struct Cell: Hashable { let y: Int; let x: Int }
        func cell(_ c: CLLocationCoordinate2D) -> Cell {
            Cell(y: Int((c.latitude / dLat).rounded()),
                 x: Int((c.longitude / dLon).rounded()))
        }

        var visits: [Cell: [Int]] = [:]
        visits.reserveCapacity(coordinates.count)
        for (i, c) in coordinates.enumerated() {
            visits[cell(c), default: []].append(i)
        }

        var retraced: Set<Cell> = []
        for (key, indices) in visits where indices.count > 1 {
            var runs = 1
            for j in 1..<indices.count where indices[j] - indices[j - 1] > retraceRunGap {
                runs += 1
            }
            if runs >= 2 { retraced.insert(key) }
        }
        guard !retraced.isEmpty else { return [] }

        var out: Set<Int> = []
        for i in 0..<coordinates.count where retraced.contains(cell(coordinates[i])) {
            out.insert(i)
        }
        return out
    }

    // MARK: - Curviness

    /// Total absolute heading change in **degrees per mile**.
    ///
    /// The app currently ranks on highway share, which cannot tell a dead-straight
    /// county road from a great winding one — both come back at 0% highway.
    /// This can.
    ///
    /// **It is direction-agnostic on purpose and by nature:** total turning is
    /// identical whichever way round the loop you drive, so it is not a
    /// substitute for offering reversal.
    ///
    /// Segments shorter than `minSegmentMeters` are skipped for bearing — over a
    /// metre or two the bearing is mostly noise, and summing that noise would
    /// score a straight road as curvy purely on how densely it was sampled.
    static let minSegmentMeters = 1.0

    static func curvinessDegreesPerMile(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 3 else { return 0 }

        var totalTurn = 0.0
        var totalMeters = 0.0
        var previous: Double?

        for i in 0..<(coordinates.count - 1) {
            let d = distance(coordinates[i], coordinates[i + 1])
            totalMeters += d
            guard d >= minSegmentMeters else { continue }

            let b = bearing(from: coordinates[i], to: coordinates[i + 1])
            if let prev = previous {
                var delta = (b - prev).truncatingRemainder(dividingBy: 360)
                delta = abs(delta)
                if delta > 180 { delta = 360 - delta }
                totalTurn += delta
            }
            previous = b
        }

        let miles = totalMeters / 1609.344
        return miles > 0 ? totalTurn / miles : 0
    }

    // MARK: - Primitives

    /// Haversine. Deliberately not `CLLocation.distance(from:)` — allocating a
    /// `CLLocation` per vertex across ~50k points is wasteful, and this has to
    /// agree exactly with the Python reference implementation.
    static func distance(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let p = Double.pi / 180
        let x = 0.5 - cos((b.latitude - a.latitude) * p) / 2
            + cos(a.latitude * p) * cos(b.latitude * p)
            * (1 - cos((b.longitude - a.longitude) * p)) / 2
        return 12_742_000 * asin(sqrt(max(0, x)))
    }

    /// Initial bearing in degrees, -180...180.
    static func bearing(
        from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D
    ) -> Double {
        let p = Double.pi / 180
        let lat1 = a.latitude * p, lat2 = b.latitude * p
        let dLon = (b.longitude - a.longitude) * p
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) / p
    }
}

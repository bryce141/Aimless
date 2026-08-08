import CoreLocation
import Observation

/// Thin wrapper over CLLocationManager. v1 needs a single fix, not tracking —
/// nothing here requires motion.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Every state the Generate button cares about. A single enum rather than a
    /// pile of bools: "denied", "no fix yet" and "fix is fuzzed" need different
    /// words on screen and only one of them is recoverable by waiting.
    enum Status: Equatable {
        case locating
        case ready
        case denied
        /// Precise Location is off. CoreLocation still returns a coordinate, but
        /// it is fuzzed by kilometers — a loop built from it starts somewhere the
        /// driver isn't, and the handoff sends them there. Worse than an error,
        /// so it blocks generation rather than warning.
        case reducedAccuracy
        /// A fix was requested and CoreLocation gave up. Retryable.
        case failed
    }

    private let manager = CLLocationManager()

    var current: CLLocationCoordinate2D?
    var status: Status = .locating

    /// Generation needs a fix we trust, not just any fix.
    var isUsable: Bool { current != nil && status == .ready }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Call on appear, on return to the foreground, and to retry after a failure.
    /// `requestLocation()` is one-shot, so nothing here refreshes without it.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            requestFix()
        }
    }

    private func requestFix() {
        guard manager.accuracyAuthorization == .fullAccuracy else {
            status = .reducedAccuracy
            return
        }
        status = .locating
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        case .denied, .restricted:
            status = .denied
        default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        if let coordinate = locations.last?.coordinate {
            current = coordinate
            status = .ready
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // This has to be visible. Without it the button stays disabled forever
        // under a "Finding you…" that stopped being true, and the only way out
        // is force-quitting the app.
        //
        // A failure after we already have a fix is not worth discarding a good
        // coordinate over — an old fix beats no fix for picking a start point.
        if current == nil { status = .failed }
    }
}

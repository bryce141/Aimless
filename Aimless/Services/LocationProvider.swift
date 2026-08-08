import CoreLocation
import Observation

/// Thin wrapper over CLLocationManager. v1 needs a single fix, not tracking —
/// nothing here requires motion.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var current: CLLocationCoordinate2D?
    var isDenied = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isDenied = true
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isDenied = false
            manager.requestLocation()
        case .denied, .restricted:
            isDenied = true
        default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        if let coordinate = locations.last?.coordinate { current = coordinate }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix just leaves `current` nil, which keeps Generate disabled.
    }
}

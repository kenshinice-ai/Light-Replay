import CoreLocation
import Foundation

/// Heading and location while the Inspect screen is open, stamped onto each Capture (docs/01 §4).
@MainActor
final class InspectSensors: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Snapshot: Sendable {
        var headingDeg: Double?
        var headingAccuracyDeg: Double?
        var latitude: Double?
        var longitude: Double?
    }

    @Published private(set) var snapshot = Snapshot()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let valid = newHeading.headingAccuracy >= 0
        let heading = valid ? newHeading.trueHeading : nil
        let accuracy = valid ? newHeading.headingAccuracy : nil
        MainActor.assumeIsolated {
            self.snapshot.headingDeg = heading
            self.snapshot.headingAccuracyDeg = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude = last.coordinate.latitude, longitude = last.coordinate.longitude
        MainActor.assumeIsolated {
            self.snapshot.latitude = latitude
            self.snapshot.longitude = longitude
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

#if DEBUG
import CaptureCore
import CoreLocation
import Foundation

/// How often the compass reports on this device, with and without the one-degree filter. Run with the device lying
/// still: `devicectl device process launch --console … com.pwegroup.propertyreplay -- -probeCompass`. It answers the
/// one question the simulator cannot: does a phone that is not turning get readings at all.
@MainActor
final class CompassProbe: NSObject, CLLocationManagerDelegate {
    static let shared = CompassProbe()
    private let manager = CLLocationManager()
    private var readings: [Date] = []

    func run(seconds: Double = 4) {
        manager.delegate = self
        Task {
            var lines: [String] = []
            for (name, filter) in [("every reading", kCLHeadingFilterNone), ("one-degree filter", 1.0)] {
                readings = []
                manager.headingFilter = filter
                manager.startUpdatingHeading()
                try? await Task.sleep(for: .seconds(seconds))
                manager.stopUpdatingHeading()
                var kept = 0, last: Date?
                for at in readings where CaptureRecorder.keepsHeading(at: at, lastKept: last) { kept += 1; last = at }
                lines.append("\(name): \(readings.count) readings in \(Int(seconds)) s, \(kept) kept at \(Int(CaptureRecorder.poseLogHz)) a second")
            }
            print("[compass] " + lines.joined(separator: "; "))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let at = newHeading.timestamp
        MainActor.assumeIsolated { readings.append(at) }
    }
}
#endif

import CoreLocation
import PropertyModel
import SwiftData
import SwiftUI

/// During. Pick the property you are standing in (nearest first when location is allowed) and start.
struct InspectTabView: View {
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @StateObject private var locator = NearbyLocator()

    private var ordered: [Property] {
        guard let here = locator.location else { return properties }
        return properties.sorted { ($0.distance(from: here) ?? .greatestFiniteMagnitude) < ($1.distance(from: here) ?? .greatestFiniteMagnitude) }
    }

    var body: some View {
        NavigationStack {
            List {
                if properties.isEmpty {
                    ContentUnavailableView("Add a property first", systemImage: "house", description: Text("Inspect starts from a property in your list."))
                } else {
                    Section {
                        Button {
                            locator.request()
                        } label: {
                            Label(locator.location == nil ? "Sort by my location" : "Sorted by distance", systemImage: "location")
                        }
                        .disabled(locator.location != nil)
                    }
                    Section("Which property are you at?") {
                        ForEach(ordered) { property in
                            NavigationLink { InspectView(property: property) } label: {
                                PropertyRow(property: property, distanceText: locator.location.flatMap { property.distance(from: $0) }.map(Formatting.distance))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inspect")
        }
    }
}

/// One-shot when-in-use location for ordering the list. Camera and microphone are requested later, at the action (ADR-0015).
@MainActor
final class NearbyLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude = last.coordinate.latitude, longitude = last.coordinate.longitude
        MainActor.assumeIsolated { self.location = CLLocation(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

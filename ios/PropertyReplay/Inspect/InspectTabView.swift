import CoreLocation
import PropertyModel
import SwiftData
import SwiftUI

/// During. Pick the home you are standing in and start. With location allowed the nearest home is listed first, but
/// nearness never picks for you: two neighbouring homes are a tap apart, and a wrong pick would file the whole
/// inspection under the wrong address (UI/UX review U11).
struct InspectTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @StateObject private var locator = NearbyLocator()
    @State private var inspecting: Property?

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
                    Section { locationRow }
                    Section("Which home are you at?") {
                        ForEach(ordered) { property in
                            Button { inspecting = property } label: {
                                HStack {
                                    PropertyRow(property: property, distanceText: locator.location.flatMap { property.distance(from: $0) }.map(Formatting.distance))
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Inspect")
            // Camera-style, full screen on every device; Done is the way out.
            .fullScreenCover(item: $inspecting) { property in
                NavigationStack { InspectView(property: property) }
            }
            .task { locator.refreshIfAllowed() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { locator.refreshIfAllowed() }   // arriving at the next home re-sorts the list
            }
        }
    }

    /// Says what the order is based on, and offers the next step for each state.
    @ViewBuilder
    private var locationRow: some View {
        switch locator.access {
        case .notAsked:
            Button { locator.request() } label: { Label("Put the nearest home first", systemImage: "location") }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Location is off for Property Replay, so the homes are in the order you added them.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url).font(.footnote.weight(.semibold))
                }
            }
        case .allowed:
            HStack {
                Label(locator.location == nil ? (locator.failed ? "Couldn't find where you are" : "Finding where you are…") : "Nearest first",
                      systemImage: "location.fill")
                    .foregroundStyle(locator.failed && locator.location == nil ? Color.cautionText : Color.primary)
                Spacer()
                Button { locator.request() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Update my location")
            }
        }
    }
}

/// When-in-use location for ordering the list. Camera and microphone are requested later, at the action (ADR-0015).
@MainActor
final class NearbyLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Access { case notAsked, denied, allowed }

    @Published private(set) var location: CLLocation?
    @Published private(set) var access: Access = .notAsked
    @Published private(set) var failed = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters   // neighbouring homes are tens of metres apart
        access = Self.access(for: manager.authorizationStatus)
    }

    /// Asks for permission if it has not been asked, then for a fix.
    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        failed = false
        manager.requestLocation()
    }

    /// A fresh fix without ever prompting.
    func refreshIfAllowed() {
        guard access == .allowed else { return }
        failed = false
        manager.requestLocation()
    }

    private static func access(for status: CLAuthorizationStatus) -> Access {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude = last.coordinate.latitude, longitude = last.coordinate.longitude
        MainActor.assumeIsolated {
            self.location = CLLocation(latitude: latitude, longitude: longitude)
            self.failed = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { self.failed = true }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            self.access = Self.access(for: status)
            if self.access == .allowed { self.manager.requestLocation() }
        }
    }
}

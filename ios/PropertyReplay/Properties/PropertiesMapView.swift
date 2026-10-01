import MapKit
import PropertyModel
import SwiftData
import SwiftUI

/// Apple Maps with one pin per home that has a location. The selection, the camera and the filtered set all belong
/// to PropertiesView, so switching between List and Map keeps the same home and the same view (UI/UX review U09).
struct PropertiesMapView: View {
    let properties: [Property]
    /// Every home, before search and filter, for the "N of M" line.
    let total: Int
    @Binding var selectedID: PersistentIdentifier?
    @Binding var position: MapCameraPosition
    /// On a phone the selected home gets a card; on a wide window the detail column already shows it.
    let showsCard: Bool
    let open: (PersistentIdentifier) -> Void
    let showList: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var located: [Property] { properties.filter { $0.coordinate != nil } }
    private var selected: Property? { properties.first { $0.persistentModelID == selectedID } }

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(located) { property in
                if let coordinate = property.coordinate {
                    Marker(property.shortAddress, systemImage: markerSymbol(property.status), coordinate: coordinate)
                        .tint(markerColor(property.status))
                        .tag(property.persistentModelID)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // The card and the count sit in the safe area, so they never cover pins or the map's legal line (review U10).
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if showsCard, let selected { card(selected) }
                countLine
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: selectedID)
        }
    }

    /// The whole card opens the home; directions hand over to Apple Maps. Nothing here says "you are at this home".
    private func card(_ property: Property) -> some View {
        HStack(spacing: 10) {
            Button { open(property.persistentModelID) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(property.shortAddress).font(.headline).multilineTextAlignment(.leading)
                        Text([property.suburb, property.status.displayName].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            .accessibilityHint("Opens this home")
            if let coordinate = property.coordinate {
                Button {
                    let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
                    item.name = property.shortAddress
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Directions in Maps")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    /// What the pins stand for: how many of the listed homes are on the map, and the way to the ones that are not.
    @ViewBuilder
    private var countLine: some View {
        let missing = properties.count - located.count
        if missing > 0 || properties.count != total {
            Button(action: showList) {
                Text(missing > 0
                     ? "\(located.count) of \(properties.count) on the map. \(missing) need a pin: see the list."
                     : "\(properties.count) of \(total) homes match.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(missing == 0)
        }
    }

    private func markerSymbol(_ status: PropertyStatus) -> String {
        switch status {
        case .toInspect: "calendar"
        case .inspected: "checkmark"
        case .shortlisted: "star.fill"
        case .dropped: "xmark"
        }
    }

    private func markerColor(_ status: PropertyStatus) -> Color {
        switch status {
        case .toInspect: .blue
        case .inspected: .green
        case .shortlisted: .orange
        case .dropped: .gray
        }
    }
}

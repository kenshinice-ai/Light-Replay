import MapKit
import PropertyModel
import SwiftUI

/// Apple Maps with one pin per property that has coordinates. Selecting a pin shows a card with the way in.
struct PropertiesMapView: View {
    let properties: [Property]
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: Property?

    private var located: [Property] { properties.filter { $0.coordinate != nil } }
    private var unlocatedCount: Int { properties.count - located.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selected) {
                ForEach(located) { property in
                    if let coordinate = property.coordinate {
                        Marker(property.shortAddress, systemImage: markerSymbol(property.status), coordinate: coordinate)
                            .tint(markerColor(property.status))
                            .tag(property)
                    }
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)

            if let selected {
                selectedCard(selected)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if unlocatedCount > 0 {
                Text("\(unlocatedCount) without a location yet")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(8).background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .animation(.default, value: selected != nil)
    }

    private func selectedCard(_ property: Property) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.shortAddress).font(.headline)
                Text(property.suburb ?? "").font(.footnote).foregroundStyle(.secondary)
                Text(property.status.displayName).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink { PropertyDetailView(property: property) } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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

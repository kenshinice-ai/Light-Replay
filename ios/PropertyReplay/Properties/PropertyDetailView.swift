import MapKit
import PropertyModel
import SwiftData
import SwiftUI

/// One scrolling hierarchy (docs/14 §1): snapshot, prep, inspection, replay, questions. Later sections are stubs
/// until lines A/B land; they say so instead of showing empty chrome.
struct PropertyDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var property: Property
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                if let coordinate = property.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))) {
                        Marker(property.shortAddress, coordinate: coordinate)
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())
                    .allowsHitTesting(false)
                }
                Text(property.address)
                Picker("Status", selection: $property.status) {
                    ForEach(PropertyStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                DatePicker("Inspection", selection: Binding(get: { property.inspectionAt ?? Date() }, set: { property.inspectionAt = $0 }))
                if property.inspectionAt != nil {
                    Button("Clear inspection time", role: .destructive) { property.inspectionAt = nil }
                }
            }
            Section("Prep · 3 things to notice") {
                Text("Arrives with the sun engine: window orientation, sun at your inspection time, where to Measure.")
                    .foregroundStyle(.secondary)
            }
            Section("Your inspection") {
                let observations = property.allObservations
                if observations.isEmpty {
                    Text("Nothing captured yet. Use Inspect when you are at the property.").foregroundStyle(.secondary)
                } else {
                    ForEach(observations.prefix(3)) { ObservationRow(observation: $0) }
                    NavigationLink("All \(observations.count) recorded") { InspectionSummaryView(property: property) }
                }
                NavigationLink { InspectView(property: property) } label: { Label("Inspect now", systemImage: "camera.viewfinder") }
            }
            Section("Replay") {
                Text("Light Replay appears after the first Measure at this property.").foregroundStyle(.secondary)
            }
            Section {
                Button("Remove property", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(property.shortAddress)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this property and everything recorded for it?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                context.delete(property)
                dismiss()
            }
        }
    }
}

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
    @State private var pinNote: String?
    @State private var placingPin = false
    @State private var scanningLight = false

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
                TextField("Address", text: $property.address)
                    .onSubmit { Task { await placePin() } }
                Button {
                    Task { await placePin() }
                } label: {
                    Label(property.coordinate == nil ? "Place pin" : "Place pin again", systemImage: "mappin.and.ellipse")
                }
                .disabled(placingPin)
                if property.isPinStale && pinNote == nil {
                    Text("The pin was for the previous address, so it is hidden. Place the pin again.").font(.footnote).foregroundStyle(.orange)
                }
                if let pinNote { Text(pinNote).font(.footnote).foregroundStyle(.orange) }
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
            Section("Light") {
                let scans = property.allObservations.filter { $0.kind == .light }
                if scans.isEmpty {
                    Text("Stand where you'd sit and scan the sky. You'll see where the sun passes through the year.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scans.prefix(3)) { ObservationRow(observation: $0) }
                }
                Button { scanningLight = true } label: {
                    Label(scans.isEmpty ? "Scan the light here" : "Scan again", systemImage: "sun.max")
                }
            }
            Section {
                Button("Remove property", role: .destructive) { confirmingDelete = true }
            }
        }
        .fullScreenCover(isPresented: $scanningLight) { LightScanView(property: property, roomLabel: nil) }
        .navigationTitle(property.shortAddress)
        .task(id: property.address) { pinNote = nil }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this property and everything recorded for it?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                do {
                    try PropertyStore.delete(property, in: context)
                } catch {
                    // The deletion stays pending and completes with the next save; this page must not outlive it.
                    StoreHealth.shared.note("Removing a property didn't finish saving (\(error.localizedDescription)); it completes with the next save.")
                }
                dismiss()
            }
        }
    }

    /// Resolves the current address. A result for an address the buyer has since edited is dropped (R07).
    private func placePin() async {
        let query = property.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        placingPin = true
        defer { placingPin = false }
        let hit = await AddressCompleter.resolve(query)
        guard property.address.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
        if let hit {
            property.setPin(latitude: hit.latitude, longitude: hit.longitude, suburb: hit.locality, forAddress: property.address)
            pinNote = nil
        } else {
            pinNote = "Couldn't find this address on the map. Check the spelling or add the suburb."
        }
    }
}

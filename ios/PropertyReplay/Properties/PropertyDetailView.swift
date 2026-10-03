import MapKit
import PropertyModel
import SwiftData
import SwiftUI

/// One home: what it is, the two things to do there (Inspect, Light), then what was recorded. Editing the address,
/// the pin and the inspection time lives behind Edit, so a stray touch never changes the address (review U12).
struct PropertyDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var property: Property
    @State private var editing = false
    @State private var removeRequested = false
    @State private var inspecting = false
    @State private var scanningLight = false
    @State private var addingNote = false
    /// Set just before the property is deleted: the page stops reading a model that is about to go.
    @State private var removed = false

    var body: some View {
        if removed {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                if let coordinate = property.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))) {
                        Marker(property.shortAddress, coordinate: coordinate)
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())
                    .allowsHitTesting(false)
                    .accessibilityLabel("Map showing \(property.shortAddress)")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(property.address).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Label(inspectionText, systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
                    if property.coordinate == nil {
                        Label(property.isPinStale ? String(localized: "The pin was for the previous address. Edit to place it again.") : String(localized: "Not on the map yet. Edit to place the pin."),
                              systemImage: "mappin.slash")
                            .font(.footnote).foregroundStyle(Color.cautionText)
                    }
                }
                .padding(.vertical, 2)
                actions
                Picker("Status", selection: $property.status) {
                    ForEach(PropertyStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Your inspection") {
                let observations = property.allObservations.filter { $0.kind != .light }
                if observations.isEmpty {
                    Text("Nothing recorded yet. Use Inspect when you are at the property, or write a note from here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(observations.prefix(3)) { item in
                        NavigationLink { ObservationDetailView(observation: item) } label: { ObservationRow(observation: item) }
                    }
                    NavigationLink("All \(property.allObservations.count) recorded") { InspectionSummaryView(property: property) }
                }
                // Things the camera cannot catch (school zone, commute, the price) are written down here, at any time.
                Button { addingNote = true } label: { Label("Add a note", systemImage: "square.and.pencil") }
            }
            Section("Light") {
                let scans = property.allObservations.filter { $0.kind == .light }
                if scans.isEmpty {
                    Text("Stand where you'd sit and scan the sky to see where the sun passes through the year.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scans.prefix(3)) { item in
                        NavigationLink { ObservationDetailView(observation: item) } label: { ObservationRow(observation: item) }
                    }
                }
            }
        }
        .navigationTitle(property.shortAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
        }
        // Inspect is camera-style: full screen on every device, not squeezed into the detail column of a split view.
        .fullScreenCover(isPresented: $inspecting) { NavigationStack { InspectView(property: property) } }
        .fullScreenCover(isPresented: $scanningLight) { LightScanView(property: property, roomLabel: nil) }
        .sheet(isPresented: $addingNote) { NoteEditor(property: property, category: nil) }
        .sheet(isPresented: $editing, onDismiss: removeIfRequested) {
            EditPropertyView(property: property, removeRequested: $removeRequested)
        }
    }

    /// The two things to do at this home. Side by side only when both labels fit on one line with their icons;
    /// otherwise stacked, where a label may wrap at large text sizes.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                inspectButton(singleLine: true)
                lightButton(singleLine: true)
            }
            VStack(spacing: 10) {
                inspectButton(singleLine: false)
                lightButton(singleLine: false)
            }
        }
        .padding(.vertical, 4)
    }

    private func inspectButton(singleLine: Bool) -> some View {
        Button { inspecting = true } label: {
            actionLabel("Inspect now", systemImage: "camera.viewfinder", singleLine: singleLine)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func lightButton(singleLine: Bool) -> some View {
        Button { scanningLight = true } label: {
            actionLabel("Scan light", systemImage: "sun.max.fill", singleLine: singleLine)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    /// Icon and words as an explicit pair. A `Label` here drops its title when it is told not to wrap (seen on
    /// iPhone and iPad, 2026-10-01), which left two unlabelled buttons.
    private func actionLabel(_ title: LocalizedStringKey, systemImage: String, singleLine: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            if singleLine {
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            } else {
                Text(title).multilineTextAlignment(.center)
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 28)
    }

    /// The booked time, or plainly that there is none. Never today's date standing in for a booking.
    private var inspectionText: String {
        property.inspectionAt.map { String(localized: "Inspection \(Formatting.inspectionDate.string(from: $0))") } ?? String(localized: "No inspection time set")
    }

    private func removeIfRequested() {
        guard removeRequested else { return }
        removed = true
        do {
            try PropertyStore.delete(property, in: context)
        } catch {
            // The deletion stays pending and completes with the next save; this page must not outlive it.
            StoreHealth.shared.note(String(localized: "Removing a property didn't finish saving (\(error.localizedDescription)); it completes with the next save."))
        }
        dismiss()
    }
}

/// Address, pin, inspection time, and removing the property. Edits apply on Save, not while typing, so the map pin
/// never points at a half-typed address (R07).
struct EditPropertyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let property: Property
    @Binding var removeRequested: Bool

    @State private var address = ""
    @State private var hasInspection = false
    @State private var inspectionAt = Date()
    @State private var isSaving = false
    @State private var pinFailed = false
    @State private var saveError: String?
    @State private var confirmingRemove = false
    @FocusState private var addressFocused: Bool

    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var addressChanged: Bool { trimmedAddress != property.address }

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    TextField("Address", text: $address, axis: .vertical)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($addressFocused)
                        .onChange(of: address) { _, _ in pinFailed = false }
                    if pinFailed {
                        Text("Couldn't find this address on the map. Check the spelling or add the suburb, or save it without a pin.")
                            .font(.footnote).foregroundStyle(Color.cautionText)
                    } else if property.coordinate == nil && !addressChanged {
                        Button("Place the pin") { Task { await save() } }
                    }
                }
                Section("Inspection") {
                    Toggle("Inspection booked", isOn: $hasInspection.animation())
                    if hasInspection {
                        DatePicker("When", selection: $inspectionAt)
                    }
                }
                if let saveError {
                    Section { Text(saveError).font(.footnote).foregroundStyle(Color.problemText) }
                }
                Section {
                    // The question is attached to the button that asks it, and names the home.
                    Button("Remove property", role: .destructive) { confirmingRemove = true }
                        .confirmationDialog("Remove \(property.shortAddress) and everything recorded for it?",
                                            isPresented: $confirmingRemove, titleVisibility: .visible) {
                            Button("Remove", role: .destructive) {
                                removeRequested = true
                                dismiss()
                            }
                        }
                }
            }
            .navigationTitle("Edit property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pinFailed ? String(localized: "Save without pin") : String(localized: "Save")) { Task { await save() } }
                        .disabled(trimmedAddress.isEmpty || isSaving)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear {
                address = property.address
                hasInspection = property.inspectionAt != nil
                inspectionAt = property.inspectionAt ?? Self.nextSaturdayMorning
            }
        }
    }

    static var nextSaturdayMorning: Date {
        var components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 7
        components.hour = 11
        let saturday = Calendar.current.date(from: components) ?? Date()
        return saturday > Date() ? saturday : saturday.addingTimeInterval(7 * 86_400)
    }

    /// Looks the address up first; if the map can't find it, the buyer decides to save it without a pin.
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let typed = trimmedAddress
        let needsPin = addressChanged || property.coordinate == nil
        var hit: AddressCompleter.Pick?
        if needsPin, !pinFailed {
            hit = await AddressCompleter.resolve(typed)
            guard trimmedAddress == typed else { return }   // edited while looking it up: the answer is for old text
            if hit == nil {
                pinFailed = true
                return
            }
        }
        property.address = typed
        if let hit { property.setPin(latitude: hit.latitude, longitude: hit.longitude, suburb: hit.locality, forAddress: typed) }
        property.inspectionAt = hasInspection ? inspectionAt : nil
        do {
            try PropertyStore.commit(context)
            dismiss()
        } catch {
            saveError = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }
}

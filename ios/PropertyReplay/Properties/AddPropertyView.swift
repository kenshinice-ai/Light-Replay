import CoreLocation
import PropertyModel
import SwiftData
import SwiftUI

/// Manual entry (ADR-0014 tier A). Address is geocoded with Apple's geocoder for the pin; nothing else is fetched.
struct AddPropertyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var inspectionAt: Date? = nil
    @State private var hasInspection = false
    @State private var isSaving = false
    @State private var geocodeNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    TextField("e.g. 12 Example Street, Brunswick VIC", text: $address, axis: .vertical)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                }
                Section {
                    Toggle("Inspection booked", isOn: $hasInspection.animation())
                    if hasInspection {
                        DatePicker("When", selection: Binding(get: { inspectionAt ?? nextSaturdayMorning }, set: { inspectionAt = $0 }))
                    }
                }
                Section {
                    Text("Only the address you type is used. It is geocoded to place a pin and kept on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let geocodeNote { Text(geocodeNote).font(.footnote).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Add property")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private var nextSaturdayMorning: Date {
        var components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 7
        components.hour = 11
        let saturday = Calendar.current.date(from: components) ?? Date()
        return saturday > Date() ? saturday : saturday.addingTimeInterval(7 * 86_400)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let property = Property(address: trimmed, inspectionAt: hasInspection ? (inspectionAt ?? nextSaturdayMorning) : nil)
        if let hit = try? await Geocoder.locate(trimmed) {
            property.latitude = hit.latitude
            property.longitude = hit.longitude
            property.suburb = hit.locality
        } else {
            geocodeNote = "Couldn't place this address on the map. Saved without a pin; you can edit it later."
        }
        context.insert(property)
        dismiss()
    }
}

enum Geocoder {
    struct Hit: Sendable {
        let latitude: Double
        let longitude: Double
        let locality: String?
    }

    /// Runs off the main actor so the non-Sendable placemarks never cross an isolation boundary.
    nonisolated static func locate(_ address: String) async throws -> Hit? {
        let placemarks = try await CLGeocoder().geocodeAddressString(address)
        guard let mark = placemarks.first, let location = mark.location else { return nil }
        return Hit(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, locality: mark.locality)
    }
}

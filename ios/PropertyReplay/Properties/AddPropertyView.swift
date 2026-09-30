import CoreLocation
import MapKit
import PropertyModel
import SwiftData
import SwiftUI

/// Manual entry with Apple Maps address completion (ADR-0014 tier A). Only the address the buyer types or picks goes to
/// Apple; the pin comes back with it. Nothing else is fetched.
struct AddPropertyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = AddressCompleter()
    @State private var hasInspection = false
    @State private var inspectionAt: Date? = nil
    @State private var isSaving = false
    @State private var pinFailed = false
    @State private var storageError: String?
    @State private var picked: AddressCompleter.Pick?

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    TextField("Start typing an address", text: $completer.query)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: completer.query) { _, _ in picked = nil; pinFailed = false }
                    if picked == nil {
                        ForEach(completer.suggestions) { suggestion in
                            Button {
                                Task { await choose(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                    Text(suggestion.subtitle).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let picked {
                        Label(picked.locality ?? "Pin placed", systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Inspection booked", isOn: $hasInspection.animation())
                    if hasInspection {
                        DatePicker("When", selection: Binding(get: { inspectionAt ?? nextSaturdayMorning }, set: { inspectionAt = $0 }))
                    }
                }
                Section {
                    Text("Only the address you type is sent to Apple Maps, to suggest matches and place the pin. The property is kept on this device and, with iCloud sync on, in your iCloud.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if pinFailed {
                        Text("Couldn't place this address on the map. You can save it without a pin and place the pin later from the property page.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let storageError {
                        Text("Couldn't save: \(storageError). Nothing was added; try again.").font(.footnote).foregroundStyle(.red)
                    }
                    if !StoreHealth.shared.isPersistent {
                        Text("Storage problem: saving is disabled until the app can write to disk.").font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add property")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pinFailed ? "Save without pin" : "Save") { Task { await save() } }
                        .disabled(completer.query.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || !StoreHealth.shared.isPersistent)
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

    private func choose(_ suggestion: AddressCompleter.Suggestion) async {
        if let hit = await AddressCompleter.resolve(suggestion) {
            picked = hit
            completer.query = hit.address
        } else {
            completer.query = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            pinFailed = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        storageError = nil
        let typed = completer.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var hit = picked
        if hit == nil, !pinFailed {
            hit = await AddressCompleter.resolve(typed)
            if hit == nil { pinFailed = true; return }   // stay here: the buyer decides to save without a pin (F08)
        }
        let property = Property(address: hit?.address ?? typed, suburb: hit?.locality,
                                latitude: hit?.latitude, longitude: hit?.longitude,
                                inspectionAt: hasInspection ? (inspectionAt ?? nextSaturdayMorning) : nil)
        context.insert(property)
        do {
            try PropertyStore.commit(context, discardingInserted: [property])   // a retry never adds a second row (R06)
        } catch {
            storageError = error.localizedDescription
            return
        }
        dismiss()
    }
}

/// Address suggestions from MapKit's completer, and resolution of a pick to a pin.
// MapKit calls the completer delegate on the main thread; @preconcurrency lets the main-actor class implement it directly.
@MainActor
final class AddressCompleter: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {   // holds MKLocalSearchCompletion (not Sendable); only ever touched on the main actor
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    struct Pick: Sendable, Equatable {
        let address: String
        let locality: String?
        let latitude: Double
        let longitude: Double
    }

    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var suggestions: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Bias toward Victoria; it is a hint, not a filter (docs/01 §2).
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631),
                                              latitudinalMeters: 300_000, longitudinalMeters: 300_000)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(6).map { Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        suggestions = []
    }

    static func resolve(_ suggestion: Suggestion) async -> Pick? {
        await resolve(request: MKLocalSearch.Request(completion: suggestion.completion))
    }

    static func resolve(_ text: String) async -> Pick? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        return await resolve(request: request)
    }

    private static func resolve(request: MKLocalSearch.Request) async -> Pick? {
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        let address = item.address?.fullAddress ?? item.name ?? ""
        return Pick(address: address, locality: item.addressRepresentations?.cityName,
                    latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

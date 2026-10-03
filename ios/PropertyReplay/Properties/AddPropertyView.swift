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
    @State private var storageError: String?
    @State private var answer: PinAnswer?
    @FocusState private var addressFocused: Bool

    /// What Maps said about one exact address text. Tied to that text, so editing the field retires the answer
    /// without anything having to reset it. (An `onChange` that cleared the pick on every edit also cleared the pick
    /// it had just been given, because choosing a suggestion rewrites the field: found 2026-10-01.)
    private struct PinAnswer: Equatable {
        let text: String
        let pick: AddressCompleter.Pick?   // nil: Maps could not place this text
    }

    private var picked: AddressCompleter.Pick? { answer?.text == completer.query ? answer?.pick : nil }
    private var pinFailed: Bool { answer.map { $0.text == completer.query && $0.pick == nil } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    TextField("Start typing an address", text: $completer.query)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($addressFocused)
                    // Under the field, where the eye is: lower down it sat behind the keyboard.
                    if pinFailed {
                        Text("Couldn't find this address on the map. Check the spelling or add the suburb, or save it without a pin and place it later from the property page.")
                            .font(.footnote).foregroundStyle(Color.cautionText)
                    } else if picked == nil, let note = completer.lookupNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if picked == nil {
                        ForEach(completer.suggestions) { suggestion in
                            Button {
                                Task { await choose(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                    Text(suggestion.subtitle).font(.footnote).foregroundStyle(.secondary)
                                }
                                // The whole row answers, not only the words: a plain button is otherwise as wide as
                                // its text, and a tap beside a short suggestion did nothing.
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let picked {
                        Label(picked.locality.map { String(localized: "Pin placed in \($0)") } ?? String(localized: "Pin placed"), systemImage: "mappin.and.ellipse")
                            .font(.footnote).foregroundStyle(.secondary)
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
                    if let storageError {
                        Text("Couldn't save: \(storageError). Nothing was added; try again.").font(.footnote).foregroundStyle(Color.problemText)
                    }
                    if !StoreHealth.shared.isPersistent {
                        Text("Storage problem: saving is disabled until the app can write to disk.").font(.footnote).foregroundStyle(Color.problemText)
                    }
                }
            }
            .navigationTitle("Add property")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pinFailed ? String(localized: "Save without pin") : String(localized: "Save")) { Task { await save() } }
                        .disabled(completer.query.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || !StoreHealth.shared.isPersistent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .task { addressFocused = true }   // the one thing this sheet is for
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
        let asked = completer.query
        let hit = await AddressCompleter.resolve(suggestion)
        guard completer.query == asked else { return }   // typed on while Maps was answering: the answer is for old text
        let shown = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        let text = hit.flatMap { $0.address.isEmpty ? nil : $0.address } ?? shown
        completer.query = text
        answer = PinAnswer(text: text, pick: hit)
        addressFocused = false   // the address is settled; putting the keyboard away gives the rest of the form back
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        storageError = nil
        let shown = completer.query
        let typed = shown.trimmingCharacters(in: .whitespacesAndNewlines)
        var hit = picked
        if hit == nil, !pinFailed {
            hit = await AddressCompleter.resolve(typed)
            guard completer.query == shown else { return }   // edited while Maps was answering: the answer is for old text
            if hit == nil {   // stay here: the buyer decides to save without a pin (F08)
                answer = PinAnswer(text: shown, pick: nil)
                return
            }
        }
        // What the field shows is what is saved, the same as in Edit; Maps adds only the pin and the suburb.
        let property = Property(address: typed, suburb: hit?.locality,
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
        fileprivate let completion: MKLocalSearchCompletion?   // nil only for the UI tests' stand-ins
    }

    struct Pick: Sendable, Equatable {
        let address: String
        let locality: String?
        let latitude: Double
        let longitude: Double
    }

    /// Where the lookup stands, so an empty list is never mistaken for "no such address" (UI/UX review U21).
    enum Lookup: Equatable { case idle, searching, found, noMatches, failed }

    @Published var query = "" {
        didSet {
            let worthAsking = query.trimmingCharacters(in: .whitespaces).count >= 3
            #if DEBUG
            if StandIn.isOn {
                suggestions = worthAsking ? StandIn.suggestions(for: query) : []
                lookup = worthAsking ? (suggestions.isEmpty ? .noMatches : .found) : .idle
                return
            }
            #endif
            completer.queryFragment = query
            lookup = worthAsking ? .searching : .idle
        }
    }
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var lookup: Lookup = .idle

    /// One line under the field for the states that need saying.
    var lookupNote: String? {
        switch lookup {
        case .idle, .found: nil
        case .searching: String(localized: "Looking for matches…")
        case .noMatches: String(localized: "No Australian matches yet. Keep typing, or save the address as you typed it.")
        case .failed: String(localized: "Couldn't reach Apple Maps. You can still save the address as you typed it.")
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = Self.australia
        completer.regionPriority = .required
    }

    /// Mainland Australia and Tasmania with a margin. V1's homes are Australian (docs/01 §1), so suggestions and
    /// lookups are limited to it. The limit holds while something in the region matches; when nothing does, Maps
    /// falls back to the whole world ("12 Exa" was completed with addresses in Japan, 2026-10-01), so suggestions
    /// are also checked by their text and resolved pins by their coordinates.
    static let australia = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -27.0, longitude: 134.0),
                                              span: MKCoordinateSpan(latitudeDelta: 36, longitudeDelta: 46))

    /// True for coordinates inside the box above.
    nonisolated static func isInAustralia(latitude: Double, longitude: Double) -> Bool {
        (-45.0 ... -9.0).contains(latitude) && (111.0 ... 157.0).contains(longitude)
    }

    /// True when a suggestion names Australia or one of its states and territories. Maps writes Australian matches
    /// as "Collingwood, VIC, Australia"; a fallback match ends in another country.
    nonisolated static func looksAustralian(title: String, subtitle: String) -> Bool {
        let text = "\(title), \(subtitle)"
        if text.localizedCaseInsensitiveContains("Australia") { return true }
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !words.isDisjoint(with: ["VIC", "NSW", "QLD", "TAS", "ACT", "NT", "SA", "WA"])
            && !["United States", "USA", "Canada"].contains { text.localizedCaseInsensitiveContains($0) }   // WA, SA, NT exist elsewhere
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
            .filter { Self.looksAustralian(title: $0.title, subtitle: $0.subtitle) }
            .prefix(6)
            .map { Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0) }
        if lookup != .idle { lookup = suggestions.isEmpty ? .noMatches : .found }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        suggestions = []
        if lookup != .idle { lookup = .failed }
    }

    static func resolve(_ suggestion: Suggestion) async -> Pick? {
        guard let completion = suggestion.completion else {
            return await resolve([suggestion.title, suggestion.subtitle].joined(separator: ", "))
        }
        return await resolve(request: MKLocalSearch.Request(completion: completion))
    }

    static func resolve(_ text: String) async -> Pick? {
        #if DEBUG
        if StandIn.isOn { return StandIn.pick(for: text) }
        #endif
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        request.region = australia
        request.regionPriority = .required
        return await resolve(request: request)
    }

    private static func resolve(request: MKLocalSearch.Request) async -> Pick? {
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        // A match outside Australia is the world-wide fallback, not this home: better no pin than a pin abroad.
        guard isInAustralia(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
        let address = item.address?.fullAddress ?? item.name ?? ""
        return Pick(address: address, locality: item.addressRepresentations?.cityName,
                    latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    #if DEBUG
    /// UI tests (`-uitest`) get two made-up homes in place of Apple Maps: adding a property is tested without the
    /// network, and no test sends an address anywhere. Titles and subtitles have the shape Maps gives.
    enum StandIn {
        static let isOn = ProcessInfo.processInfo.arguments.contains("-uitest")
        static let homes = [
            Pick(address: "5 Sample Court, Carlton VIC 3053", locality: "Carlton", latitude: -37.8000, longitude: 144.9670),
            Pick(address: "5 Sample Close, Coburg VIC 3058", locality: "Coburg", latitude: -37.7430, longitude: 144.9650)
        ]

        static func suggestions(for query: String) -> [Suggestion] {
            let wanted = query.trimmingCharacters(in: .whitespaces)
            return homes.filter { $0.address.localizedCaseInsensitiveContains(wanted) }.map { home in
                let parts = home.address.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return Suggestion(title: parts[0], subtitle: parts.count > 1 ? parts[1] : "", completion: nil)
            }
        }

        static func pick(for text: String) -> Pick? {
            homes.first { $0.address.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        }
    }
    #endif
}

import CloudKit
import PropertyModel
import SwiftData
import SwiftUI

/// Priorities, profile, preferences, privacy and data. Only controls that do something today appear here.
struct YouView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @Query private var properties: [Property]
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var noteLanguages: [NoteLanguages.Option] = []
    @State private var iCloudAccount: String?
    @AppStorage(SyncSettings.key) private var syncWanted = true

    var body: some View {
        NavigationStack {
            List {
                if let preferences = preferencesRows.first {
                    let binding = Bindable(preferences)
                    Section("Priorities") {
                        NavigationLink {
                            PrioritiesView(preferences: preferences)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What you care about")
                                Text(preferences.priorities.isEmpty ? "None chosen" : preferences.priorities.map(\.displayName).joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Profile") {
                        TextField("Your name (optional)", text: binding.displayName)
                        LabeledContent("Partner", value: "Sharing arrives in Phase 3")
                    }
                    Section("Preferences") {
                        Picker("Note language", selection: Binding(
                            get: { preferences.noteLanguage ?? "" },
                            set: { preferences.noteLanguage = $0.isEmpty ? nil : $0 })) {
                            Text("Follow phone (\(Locale.current.identifier))").tag("")
                            ForEach(noteLanguages) { Text($0.name).tag($0.id) }
                        }
                        if noteLanguages.isEmpty {
                            Text("No English or Chinese transcription locales reported by this phone yet.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle("Haptics on the timeline", isOn: binding.hapticsEnabled)
                        LabeledContent("Measure height") {
                            Stepper(String(format: "%.2f m", preferences.targetHeightM), value: binding.targetHeightM, in: 0.3...2.0, step: 0.05)
                        }
                    }
                    Section("Advanced (spike)") {
                        LabeledContent("Viewpoint tolerance") {
                            Stepper(String(format: "%.2f m", preferences.viewpointToleranceM), value: binding.viewpointToleranceM, in: 0.05...0.5, step: 0.05)
                        }
                        NavigationLink("Capture validator (unbound, debug)") { CaptureValidatorView(property: nil, roomLabel: nil) }
                    }
                }
                Section("Privacy & data") {
                    Toggle("iCloud sync", isOn: $syncWanted)
                    LabeledContent("Now", value: storageSummary)
                    if syncWanted != (StoreHealth.shared.mode == .iCloud) && StoreHealth.shared.isPersistent {
                        Text("Takes effect the next time you open the app.").font(.footnote).foregroundStyle(.orange)
                    }
                    Text("Addresses go to Apple Maps only to place a pin. Properties, photos, notes and measurements stay on this device and, with iCloud sync on, in your private iCloud so your iPad sees them too. No one else, including us, can read them. Nothing else is uploaded unless you share a page.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Properties", value: "\(properties.count)")
                    Button("Delete everything", role: .destructive) { confirmingDelete = true }
                    ForEach(StoreHealth.shared.messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    NavigationLink("What the evidence labels mean") { EvidenceLegendView() }
                    NavigationLink("Device capabilities") { CapabilitiesView() }
                }
            }
            .navigationTitle("You")
            .task {
                _ = try? PropertyStore.preferences(in: context)
                noteLanguages = await NoteLanguages.available()
                iCloudAccount = await Self.iCloudAccountStatus()
            }
            .confirmationDialog(StoreHealth.shared.mode == .iCloud
                                ? "Delete every property, note and measurement on this device and in your iCloud?"
                                : "Delete every property, note and measurement on this device?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    do { try PropertyStore.deleteEverything(in: context) } catch { deleteError = error.localizedDescription }
                }
            }
            .alert("Couldn't delete everything", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
        }
    }
}

extension YouView {
    private var storageSummary: String {
        switch StoreHealth.shared.mode {
        case .iCloud: iCloudAccount.map { "iCloud · \($0)" } ?? "iCloud"
        case .deviceOnly: "This device only"
        case .memory: "Not saved (storage problem)"
        }
    }

    static func iCloudAccountStatus() async -> String {
        guard let status = try? await CKContainer(identifier: PropertyStore.cloudContainerID).accountStatus() else { return "status unknown" }
        switch status {
        case .available: return "signed in"
        case .noAccount: return "not signed in to iCloud"
        case .restricted: return "restricted on this device"
        case .temporarilyUnavailable: return "temporarily unavailable"
        default: return "status unknown"
        }
    }
}

struct PrioritiesView: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        List {
            Section {
                Text("Pick up to \(UserPreferences.maximumPriorities). Compare shows only these. Nothing here becomes a score.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                ForEach(PriorityDimension.allCases) { dimension in
                    let selected = preferences.priorities.contains(dimension)
                    Button { preferences.toggle(dimension) } label: {
                        HStack {
                            Label(dimension.displayName, systemImage: dimension.systemImage)
                            Spacer()
                            if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!selected && preferences.priorities.count >= UserPreferences.maximumPriorities)
                }
            }
        }
        .navigationTitle("Priorities")
    }
}

struct EvidenceLegendView: View {
    private let rows: [(String, String)] = [
        ("Verified", "A fact you confirmed, or licensed data with a source."),
        ("Observed · measured", "Measured on site by the sensors and passed the quality gates."),
        ("Observed · noted", "Something you photographed, said or tagged on site."),
        ("Strong indication", "Several sources agree."),
        ("Indicative", "A model's estimate. Worth verifying."),
        ("Unknown", "Not enough information. Shown, never hidden.")
    ]

    var body: some View {
        List(rows, id: \.0) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.0).font(.body.weight(.semibold))
                Text(row.1).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Evidence labels")
    }
}

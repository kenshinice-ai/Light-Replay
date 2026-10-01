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
    @State private var iCloudAccount: ICloudAccount?
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
                    }
                    Section {
                        Picker("Note language", selection: Binding(
                            get: { preferences.noteLanguage ?? "" },
                            set: { preferences.noteLanguage = $0.isEmpty ? nil : $0 })) {
                            Text("Follow phone (\(Locale.current.identifier))").tag("")
                            ForEach(noteLanguages) { Text($0.name).tag($0.id) }
                        }
                        if noteLanguages.isEmpty {
                            Text("No English or Chinese transcription locales reported by this phone yet.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle("Haptics", isOn: binding.hapticsEnabled)
                        LabeledContent("Light scan height") {
                            Stepper(String(format: "%.2f m", preferences.targetHeightM), value: binding.targetHeightM, in: 0.3...2.0, step: 0.05)
                        }
                    } header: {
                        Text("Preferences")
                    } footer: {
                        Text("Haptics mark a photo taken, a note started and finished, and a light scan locking on and being covered. Light scan height is where you hold the phone: 1.15 m is eye height when seated.")
                    }
                }
                Section("Privacy & data") {
                    Toggle("iCloud sync", isOn: $syncWanted)
                    // What is true right now, from what really happened; never "synced" just because of a sign-in (U16).
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncHeadline).font(.subheadline)
                        if let detail = syncDetail {
                            Text(detail).font(.footnote).foregroundStyle(syncIsProblem ? Color.cautionText : Color.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    // Only when the switch was moved in this session; a sync that failed to start is a different message.
                    if let atLaunch = SyncSettings.wantedAtLaunch, syncWanted != atLaunch {
                        Text("The switch takes effect the next time you open the app.").font(.footnote).foregroundStyle(Color.cautionText)
                    }
                    Text("Addresses go to Apple Maps only to place a pin. Properties, photos, notes and measurements stay on this device and, with iCloud sync on, in your private iCloud so your iPad sees them too. No one else, including us, can read them. Nothing else is uploaded unless you share a page.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Properties", value: "\(properties.count)")
                    Button("Delete everything", role: .destructive) { confirmingDelete = true }
                        // Attached to the button that asks, and saying how far the deletion reaches.
                        .confirmationDialog(StoreHealth.shared.mode == .iCloud
                                            ? "Delete every property, note and scan on this device and in your iCloud?"
                                            : "Delete every property, note and scan on this device?",
                                            isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete everything", role: .destructive) {
                                do { try PropertyStore.deleteEverything(in: context) } catch { deleteError = error.localizedDescription }
                            }
                        }
                    ForEach(StoreHealth.shared.messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(Color.cautionText) }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    NavigationLink("What the evidence labels mean") { EvidenceLegendView() }
                }
                #if DEBUG
                // Internal builds only: none of this is something a buyer needs to understand to inspect a home (U15).
                Section("Developer") {
                    if let preferences = preferencesRows.first {
                        LabeledContent("Viewpoint tolerance") {
                            Stepper(String(format: "%.2f m", preferences.viewpointToleranceM), value: Bindable(preferences).viewpointToleranceM, in: 0.05...0.5, step: 0.05)
                        }
                    }
                    NavigationLink("Capture validator (unbound)") { CaptureValidatorView(property: nil, roomLabel: nil) }
                    NavigationLink("Device capabilities") { CapabilitiesView() }
                }
                #endif
            }
            .navigationTitle("You")
            .task {
                _ = try? PropertyStore.preferences(in: context)
                noteLanguages = await NoteLanguages.available()
                iCloudAccount = await Self.iCloudAccountStatus()
            }
            .alert("Couldn't delete everything", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
        }
    }
}

extension YouView {
    private var syncHeadline: String {
        switch StoreHealth.shared.mode {
        case .memory: return "Not being saved (storage problem)"
        case .deviceOnly: return "Kept on this device only"
        case .iCloud:
            guard iCloudAccount == .available else { return "iCloud sync is on, but not working on this device" }
            switch SyncMonitor.shared.status.summary {
            case .failed: return "iCloud sync is on, but the last attempt failed"
            case .lastSucceeded: return "Syncing with your private iCloud"
            case .working: return "Talking to iCloud…"
            case .nothingYet: return "iCloud sync is on"
            }
        }
    }

    private var syncDetail: String? {
        switch StoreHealth.shared.mode {
        case .memory: return "Nothing you add will survive quitting the app."
        case .deviceOnly: return SyncSettings.attemptedAtLaunch ? "iCloud sync couldn't start this time, so nothing is being sent." : nil
        case .iCloud:
            switch iCloudAccount {
            case .available: break
            case .noAccount: return "This device isn't signed in to iCloud. Your records stay here until it is."
            case .restricted: return "iCloud is restricted on this device. Your records stay here."
            case .unknown: return "Couldn't check the iCloud account. Your records are on this device."
            case nil: return nil
            }
            switch SyncMonitor.shared.status.summary {
            case .failed(let failure):
                let what = failure.kind == .send ? "send to" : (failure.kind == .receive ? "receive from" : "set up")
                return "Couldn't \(what) iCloud at \(failure.at.formatted(date: .omitted, time: .shortened)): \(failure.reason). Your records are safe on this device and the app keeps trying."
            case .lastSucceeded(let sent, let received):
                let parts = [sent.map { "Last sent \($0.formatted(date: .abbreviated, time: .shortened))" },
                             received.map { "last received \($0.formatted(date: .abbreviated, time: .shortened))" }].compactMap { $0 }
                return parts.joined(separator: ", ") + ". Anything recorded since may still be on its way."
            case .working: return nil
            case .nothingYet: return "Nothing has been sent or received since the app opened."
            }
        }
    }

    private var syncIsProblem: Bool {
        if StoreHealth.shared.mode != .iCloud { return StoreHealth.shared.mode == .memory || SyncSettings.attemptedAtLaunch }
        if let iCloudAccount, iCloudAccount != .available { return true }
        if case .failed = SyncMonitor.shared.status.summary { return true }
        return false
    }

    enum ICloudAccount: Equatable { case available, noAccount, restricted, unknown }

    static func iCloudAccountStatus() async -> ICloudAccount {
        guard let status = try? await CKContainer(identifier: PropertyStore.cloudContainerID).accountStatus() else { return .unknown }
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return .unknown
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
                        .contentShape(Rectangle())   // the gap between the name and the tick is part of the row
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

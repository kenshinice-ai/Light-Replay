import PropertyModel
import SwiftData
import SwiftUI

@main
struct PropertyReplayApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { StartupTasks.run(in: container.mainContext) }
        }
        .modelContainer(container)
    }

    /// iCloud when the person wants it (ADR-0017), else this device only, else memory. A failure never takes the app
    /// down; it is shown as a banner and under You › Privacy & data.
    @MainActor
    private static func makeContainer() -> ModelContainer {
        let health = StoreHealth.shared
        if SyncSettings.isEnabled {
            do {
                let container = try PropertyStore.container(iCloudSync: true)
                health.mode = .iCloud
                return container
            } catch {
                health.note("iCloud sync unavailable, keeping data on this device: \(error)")
            }
        }
        do {
            let container = try PropertyStore.container()
            health.mode = .deviceOnly
            return container
        } catch {
            health.note("Persistent store unavailable, using memory: \(error)")
            health.mode = .memory
            return try! PropertyStore.container(inMemory: true)
        }
    }
}

/// One-time and every-launch housekeeping that needs the database.
@MainActor
enum StartupTasks {
    static func run(in context: ModelContext) {
        guard StoreHealth.shared.isPersistent else { return }
        do {
            let report = try LegacyFiles.migrate(in: context)
            if report.photos + report.scenes > 0 {
                StoreHealth.shared.note("Moved \(report.photos) photos and \(report.scenes) measurements into the library.")
            }
            try LegacyFiles.sweep(in: context)
        } catch {
            StoreHealth.shared.note("Couldn't move older files into the library yet: \(error.localizedDescription)")
        }
        let pending = PendingCaptures.recover(in: context)
        if pending.recovered > 0 { StoreHealth.shared.note("Added \(pending.recovered) measurement(s) that weren't saved last time.") }
        if pending.waiting > 0 { StoreHealth.shared.note("\(pending.waiting) measurement(s) are waiting for a property that no longer exists.") }
        _ = try? PropertyStore.preferences(in: context)
    }
}

/// Whether the store mirrors to iCloud. Read once at launch, because the container is configured once.
enum SyncSettings {
    static let key = "iCloudSyncEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Where the data lives this session, plus diagnostics shown under You.
@MainActor
@Observable
final class StoreHealth {
    enum Mode: Equatable { case iCloud, deviceOnly, memory }

    static let shared = StoreHealth()
    var mode: Mode = .deviceOnly
    /// False when the on-disk store failed to open and everything lives in memory until the app quits.
    var isPersistent: Bool { mode != .memory }
    private(set) var messages: [String] = []
    func note(_ message: String) { messages.append(message) }
}

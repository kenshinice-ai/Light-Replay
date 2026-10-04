import CaptureCore
import PropertyModel
import SwiftData
import SwiftUI
import UIKit

@main
struct PropertyReplayApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        #if DEBUG
        // XCTest counts UIKit animations to decide the app is idle; a keyboard arriving under SwiftUI chrome can leave
        // that count stuck and every step waits 60 s. UI-test launches run without UIKit animations (SwiftUI's own
        // still run); nobody using the app is affected (group memory xcuitest-animation-count-leak-keyboard-toolbar).
        if ProcessInfo.processInfo.arguments.contains("-uitest") { UIView.setAnimationsEnabled(false) }
        // Before deploying the CloudKit schema to production: on a device signed into iCloud,
        // `devicectl device process launch --console … com.pwegroup.propertyreplay -initializeCloudKitSchema`.
        if ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema") {
            Task.detached {
                let outcome: String
                do { outcome = try PropertyStore.initializeCloudKitSchema() } catch { outcome = "CloudKit schema initialisation failed: \(error)" }
                print("[schema] \(outcome)")
                await MainActor.run { StoreHealth.shared.note(outcome) }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { StartupTasks.run(in: container.mainContext) }
        }
        .modelContainer(container)
        .commands { InspectCommands() }
    }

    /// iCloud when the person wants it (ADR-0017), else this device only, else memory. A failure never takes the app
    /// down; it is shown as a banner and under You › Privacy & data.
    @MainActor
    private static func makeContainer() -> ModelContainer {
        let health = StoreHealth.shared
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest") {
            // UI tests: a clean in-memory library with the fictional samples on every launch; never touches real data.
            let container = try! PropertyStore.container(inMemory: true)
            // -uitestEmpty: the library as a new buyer finds it, for the empty states.
            if !ProcessInfo.processInfo.arguments.contains("-uitestEmpty") { try? SampleData.insert(into: container.mainContext) }
            health.mode = .deviceOnly
            return container
        }
        #endif
        SyncSettings.wantedAtLaunch = SyncSettings.isEnabled
        if SyncSettings.isEnabled {
            SyncSettings.attemptedAtLaunch = true
            do {
                SyncMonitor.shared.start()   // before the container, so the mirror's first events are not missed
                let container = try PropertyStore.container(iCloudSync: true)
                health.mode = .iCloud
                return container
            } catch {
                health.note(String(localized: "iCloud sync unavailable, keeping data on this device: \(error.localizedDescription)"))
            }
        }
        do {
            let container = try PropertyStore.container()
            health.mode = .deviceOnly
            return container
        } catch {
            health.note(String(localized: "Persistent store unavailable, using memory: \(error.localizedDescription)"))
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
                StoreHealth.shared.note(String(localized: "Moved \(report.photos) photos and \(report.scenes) measurements into the library."))
            }
            try LegacyFiles.sweep(in: context)
        } catch {
            StoreHealth.shared.note(String(localized: "Couldn't move older files into the library yet: \(error.localizedDescription)"))
        }
        // Photos saved before thumbnails existed get one now, a bounded batch per launch (never the whole library at once).
        if let photos = try? PropertyStore.photosWithoutThumbnails(in: context), !photos.isEmpty {
            for observation in photos {
                guard let data = observation.photoData else { continue }
                let thumbnail = PhotoScaler.thumbnail(data)
                observation.thumbnailData = thumbnail ?? Data()   // Data() marks "tried": not an image, so not asked again
                // The count is only trusted from bytes that decode: a store missing its file hands back a short reference.
                if thumbnail != nil, observation.photoByteCount == 0 { observation.photoByteCount = data.count }
            }
            try? PropertyStore.commit(context)
        }
        let pending = PendingCaptures.recover(in: context)
        // Light rows from before the digest: the status moves out of the buyer's column (ADR-0022).
        _ = try? LightStatusMigration.migrate(in: context)
        sweepSpools(in: context)
        if pending.recovered > 0 { StoreHealth.shared.note(String(localized: "Added \(pending.recovered) measurement(s) that weren't saved last time.")) }
        if pending.waiting > 0 { StoreHealth.shared.note(String(localized: "\(pending.waiting) measurement(s) are waiting for a property that no longer exists.")) }
        _ = try? PropertyStore.preferences(in: context)
    }
}

extension StartupTasks {
    /// Frames kept for analysis go when their scan is gone or their keeping time is over (docs/04 §12). A row whose
    /// frames expired is told, so it never offers an analysis that can no longer run.
    static func sweepSpools(in context: ModelContext) {
        let light = ObservationKind.light.rawValue
        let rows = (try? context.fetch(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.kindRaw == light }))) ?? []
        let live = Set(rows.map(\.uuid.uuidString)).union(PendingCaptures.all().compactMap { $0.observationUUID?.uuidString })
        let swept = FrameSpool.sweep(keeping: live)
        guard !swept.expired.isEmpty else { return }
        for row in rows where swept.expired.contains(row.uuid.uuidString) {
            guard var digest = row.lightDigest, digest.spoolFrames != nil else { continue }
            digest.spoolFrames = nil
            row.lightDigest = digest
        }
        try? PropertyStore.commit(context)
    }
}

/// Whether the store mirrors to iCloud. Read once at launch, because the container is configured once.
@MainActor
enum SyncSettings {
    static let key = "iCloudSyncEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    /// What the switch said when the container was configured; nil in the UI-test rig, which never syncs.
    static var wantedAtLaunch: Bool?
    /// True when this launch tried to open the iCloud-mirrored store, whether or not it worked.
    static var attemptedAtLaunch = false
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

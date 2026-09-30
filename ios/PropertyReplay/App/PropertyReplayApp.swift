import PropertyModel
import SwiftData
import SwiftUI

@main
struct PropertyReplayApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PropertyStore.container()
        } catch {
            // A broken on-disk store must not take the app down; fall back to memory and surface it in You › About.
            container = try! PropertyStore.container(inMemory: true)
            StoreHealth.shared.isPersistent = false
            StoreHealth.shared.note("Persistent store unavailable, using memory: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// Tiny diagnostics sink shown under You › About.
@MainActor
final class StoreHealth {
    static let shared = StoreHealth()
    /// False when the on-disk store failed to open and everything lives in memory until the app quits.
    var isPersistent = true
    private(set) var messages: [String] = []
    func note(_ message: String) { messages.append(message) }
}

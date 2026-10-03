import CoreData
import Foundation
import PropertyModel

/// Listens to the CloudKit mirror under SwiftData and keeps the last thing that really happened (UI/UX review U16).
/// The only source for "sent" and "received" on the You page; the account being signed in is never shown as synced.
@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    private(set) var status = SyncStatus()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                          object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let kind: SyncStatus.Kind
            switch event.type {
            case .import: kind = .receive
            case .export: kind = .send
            default: kind = .setup
            }
            let finishedAt = event.endDate, succeeded = event.succeeded, reason = event.error?.localizedDescription
            MainActor.assumeIsolated {
                self?.status.record(kind, finishedAt: finishedAt, succeeded: succeeded, reason: reason)
            }
        }
    }
}

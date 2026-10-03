import Foundation

/// What can honestly be said about iCloud sync, from the events the CloudKit mirror reports (UI/UX review U16).
/// Being signed in is not being synced: only a finished, successful send or receive counts, and a failure is shown
/// as a failure. It never claims that every record has arrived somewhere; it reports the last thing that worked.
public struct SyncStatus: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case setup
        /// Changes arriving from iCloud (the mirror's import).
        case receive
        /// This device's changes going to iCloud (the mirror's export).
        case send
    }

    public struct Failure: Equatable, Sendable {
        public let kind: Kind
        public let at: Date
        public let reason: String
    }

    public enum Summary: Equatable, Sendable {
        /// Sync is on and nothing has finished since the app opened.
        case nothingYet
        /// Something is running and nothing has finished yet.
        case working
        /// The last send and receive that worked. Records made after `sent` may still be waiting.
        case lastSucceeded(sent: Date?, received: Date?)
        case failed(Failure)
    }

    public private(set) var lastSent: Date?
    public private(set) var lastReceived: Date?
    /// The failure still standing for each kind of event. Kept apart, so a receive that fails and then recovers
    /// cannot take a send failure away with it.
    public private(set) var failures: [Kind: Failure] = [:]
    public private(set) var inProgress: Set<Kind> = []

    /// The most recent failure that nothing of its own kind has succeeded after.
    public var lastFailure: Failure? { failures.values.max { $0.at < $1.at } }

    public init() {}

    /// One event from the mirror. `finishedAt` is nil while the event is still running.
    public mutating func record(_ kind: Kind, finishedAt: Date?, succeeded: Bool, reason: String?) {
        guard let finishedAt else {
            inProgress.insert(kind)
            return
        }
        inProgress.remove(kind)
        guard succeeded else {
            if let standing = failures[kind], standing.at > finishedAt { return }   // an older event reported late
            failures[kind] = Failure(kind: kind, at: finishedAt, reason: reason ?? "no reason given")
            return
        }
        switch kind {
        case .send: lastSent = max(lastSent ?? finishedAt, finishedAt)
        case .receive: lastReceived = max(lastReceived ?? finishedAt, finishedAt)
        case .setup: break
        }
        // Only the same kind of event succeeding later takes a failure back: receiving fine says nothing about sending.
        if let failure = failures[kind], failure.at <= finishedAt { failures[kind] = nil }
    }

    public var summary: Summary {
        if let lastFailure { return .failed(lastFailure) }
        if lastSent != nil || lastReceived != nil { return .lastSucceeded(sent: lastSent, received: lastReceived) }
        return inProgress.isEmpty ? .nothingYet : .working
    }
}

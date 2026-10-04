import Foundation
import SwiftData

/// A light measurement between "record encoded" and "row saved" (reaudit R02). It is written to Application Support
/// before the database is touched and removed once the row exists, so a failed save or a crash never loses a capture.
/// `scene_id` makes committing idempotent: a capture already on a row is not added twice.
public struct PendingCapture: Codable, Sendable, Equatable {
    public var sceneID: String
    public var propertyUUID: UUID
    public var roomLabel: String?
    public var capturedAt: Date
    public var record: Data
    /// Before 2026-10-04: the sentence written into the row's `text`. Captures with a `digest` leave `text` alone.
    public var note: String?
    /// The identity of the row this becomes, fixed when the scan started (it is the capture's session id). `scene_id`
    /// is a number for people and can repeat across devices on the same day; this cannot (ADR-0022, review V2-04).
    /// Nil only in files written before it existed.
    public var observationUUID: UUID?
    /// `LightDigest`, encoded.
    public var digest: Data?
    /// The hero photo and its thumbnail.
    public var photo: Data?
    public var thumbnail: Data?

    public init(sceneID: String, propertyUUID: UUID, roomLabel: String?, capturedAt: Date, record: Data, note: String? = nil,
                observationUUID: UUID? = nil, digest: Data? = nil, photo: Data? = nil, thumbnail: Data? = nil) {
        self.sceneID = sceneID
        self.propertyUUID = propertyUUID
        self.roomLabel = roomLabel
        self.capturedAt = capturedAt
        self.record = record
        self.note = note
        self.observationUUID = observationUUID
        self.digest = digest
        self.photo = photo
        self.thumbnail = thumbnail
    }

    /// What the pending file is named after: the row's identity when there is one, the scene id for older files.
    var key: String { observationUUID?.uuidString ?? sceneID }
}

public enum PendingCaptures {
    public static var root: URL { URL.applicationSupportDirectory.appending(path: "PendingCaptures", directoryHint: .isDirectory) }

    public static func write(_ capture: PendingCapture, root: URL = root) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(capture).write(to: file(capture.key, root), options: .atomic)
    }

    public static func all(root: URL = root) -> [PendingCapture] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap {
            try? JSONDecoder().decode(PendingCapture.self, from: Data(contentsOf: root.appending(path: $0)))
        }
    }

    public static func remove(_ capture: PendingCapture, root: URL = root) throws {
        try LegacyFiles.removeUnlessMissing(file(capture.key, root))
    }

    /// Saves the capture as a light observation on the property's open inspection, then drops the pending file.
    /// Its level is Unknown until an analysis passes (ADR-0013).
    @MainActor @discardableResult
    public static func commit(_ capture: PendingCapture, to property: Property, in context: ModelContext,
                              root: URL = root) throws -> InspectionObservation {
        // Already on a row: by its own identity when the capture has one. Two scans may share a scene id (two devices,
        // one day); only a file from before identities existed is matched by scene id.
        let existing = try capture.observationUUID.map { try observation(uuid: $0, in: context) } ?? observation(sceneID: capture.sceneID, in: context)
        if let existing {
            try? remove(capture, root: root)
            return existing
        }
        let observation = InspectionObservation(kind: .light, category: .naturalLight, source: .sensor,
                                                roomLabel: capture.roomLabel, capturedAt: capture.capturedAt)
        if let uuid = capture.observationUUID { observation.uuid = uuid }
        observation.sceneId = capture.sceneID
        observation.sceneRecordData = capture.record
        if let digest = capture.digest {
            observation.lightDigestData = digest   // the status is derived from this; `text` stays the buyer's
        } else {
            observation.text = capture.note ?? String(localized: "Light measurement recorded (analysis pending)", bundle: .module)
        }
        if let photo = capture.photo { observation.attachPhoto(photo, thumbnail: capture.thumbnail) }
        try PropertyStore.record(observation, for: property, in: context)
        try? remove(capture, root: root)   // a leftover is recognised by its identity next time
        return observation
    }

    /// Commits leftovers from an earlier failure or crash. Captures whose property is gone stay on disk and are counted.
    @MainActor
    public static func recover(in context: ModelContext, root: URL = root) -> (recovered: Int, waiting: Int) {
        var recovered = 0, waiting = 0
        for capture in all(root: root) {
            let uuid = capture.propertyUUID
            guard let property = try? context.fetch(FetchDescriptor<Property>(predicate: #Predicate { $0.uuid == uuid })).first,
                  (try? commit(capture, to: property, in: context, root: root)) != nil else {
                waiting += 1
                continue
            }
            recovered += 1
        }
        return (recovered, waiting)
    }

    /// Every scene id already used on this account: rows (including synced ones) and pending captures.
    @MainActor
    public static func takenSceneIDs(in context: ModelContext, root: URL = root) -> Set<String> {
        let rows = (try? context.fetch(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.sceneId != nil }))) ?? []
        return Set(rows.compactMap(\.sceneId)).union(all(root: root).map(\.sceneID))
    }

    @MainActor
    static func observation(uuid: UUID, in context: ModelContext) throws -> InspectionObservation? {
        try context.fetch(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.uuid == uuid })).first
    }

    @MainActor
    static func observation(sceneID: String, in context: ModelContext) throws -> InspectionObservation? {
        try context.fetch(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.sceneId == sceneID })).first
    }

    private static func file(_ key: String, _ root: URL) -> URL { root.appending(path: "\(key).json") }
}

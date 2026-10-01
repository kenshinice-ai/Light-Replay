import CaptureCore
import Foundation
import PropertyModel
import SceneRecord
import SwiftData

/// Turns a finished capture into a SceneRecord and puts it on the property (reaudit R02, ADR-0017): the record is
/// written as a PendingCapture before the database is touched, so a failed save or a crash never loses it.
@MainActor
enum LightCaptureSaver {
    struct Outcome {
        let sceneID: String
        /// A temporary copy for the share sheet.
        let shareURL: URL
        /// Set when the record is safe on disk but not yet on the property; retry with `attach`.
        let pending: PendingCapture?
        let attachError: String?
    }

    /// Unbound captures (no property) are only written as a share copy.
    static func save(_ log: CaptureLog, property: Property?, roomLabel: String?, note: String?,
                     in context: ModelContext) throws -> Outcome {
        let legacy = (try? FileManager.default.contentsOfDirectory(atPath: LegacyFiles.scenesRoot.path)) ?? []
        let taken = PendingCaptures.takenSceneIDs(in: context).union(legacy)
        let sceneID = SceneRecordBuilder.nextSceneID(taken: taken, date: log.endedAt, timezone: log.timezone)
        let record = try SceneRecordBuilder.build(log, sceneID: sceneID).encoded()
        let shareURL = try shareCopy(record, sceneID: sceneID)
        guard let property else { return Outcome(sceneID: sceneID, shareURL: shareURL, pending: nil, attachError: nil) }
        let capture = PendingCapture(sceneID: sceneID, propertyUUID: property.uuid, roomLabel: roomLabel,
                                     capturedAt: log.endedAt, record: record, note: note)
        try PendingCaptures.write(capture)
        do {
            try PendingCaptures.commit(capture, to: property, in: context)
            return Outcome(sceneID: sceneID, shareURL: shareURL, pending: nil, attachError: nil)
        } catch {
            return Outcome(sceneID: sceneID, shareURL: shareURL, pending: capture, attachError: error.localizedDescription)
        }
    }

    /// Retries putting a pending record on its property. Idempotent by scene id.
    static func attach(_ capture: PendingCapture, to property: Property, in context: ModelContext) throws {
        try PendingCaptures.commit(capture, to: property, in: context)
    }

    private static func shareCopy(_ record: Data, sceneID: String) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "scenes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(sceneID).json")
        try record.write(to: url, options: .atomic)
        return url
    }
}

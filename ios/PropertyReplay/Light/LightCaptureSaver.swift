import CaptureCore
import Foundation
import PropertyModel
import SceneRecord
import SwiftData

/// Turns a finished capture into a SceneRecord and puts it on the property (reaudit R02, ADR-0017): the record is
/// written as a PendingCapture before the database is touched, so a failed save or a crash never loses it. The row
/// it becomes has the capture session's identity (ADR-0022): the frames kept for analysis are filed under the same
/// id, so a row and its frames can never be mismatched, whatever their scene ids.
@MainActor
enum LightCaptureSaver {
    struct Outcome {
        let sceneID: String
        /// A temporary copy for the share sheet.
        let shareURL: URL
        /// Set when the record is safe on disk but not yet on the property; retry with `attach`.
        let pending: PendingCapture?
        let attachError: String?
        /// Frames kept on this device for analysis; nil when none were.
        let spoolFrames: Int?
    }

    /// Unbound captures (no property) are only written as a share copy, and keep no frames.
    static func save(_ log: CaptureLog, property: Property?, roomLabel: String?, question: String?, sweptCoveragePct: Int?,
                     in context: ModelContext) throws -> Outcome {
        let legacy = (try? FileManager.default.contentsOfDirectory(atPath: LegacyFiles.scenesRoot.path)) ?? []
        let taken = PendingCaptures.takenSceneIDs(in: context).union(legacy)
        let sceneID = SceneRecordBuilder.nextSceneID(taken: taken, date: log.endedAt, timezone: log.timezone)
        let document = try SceneRecordBuilder.build(log, sceneID: sceneID)
        let record = try document.encoded()
        let shareURL = try shareCopy(record, sceneID: sceneID)
        // "Kept for analysis" is only said of frames that are all there (docs/04 §12, recovery check 1).
        let kept = log.spool.flatMap { FrameSpool.isIntact($0) ? $0.frames.count : nil }
        guard let property else {
            FrameSpool.remove(sessionID: log.sessionID)
            return Outcome(sceneID: sceneID, shareURL: shareURL, pending: nil, attachError: nil, spoolFrames: nil)
        }
        if kept == nil { FrameSpool.remove(sessionID: log.sessionID) }
        let quality = document.fields["quality"]
        var gates: [String: String] = [:]
        var level = "R0"
        if case .object(let q)? = quality {
            if case .string(let stated)? = q["level"] { level = stated }
            if case .object(let lights)? = q["gates"] {
                for (name, light) in lights { if case .string(let value) = light { gates[name] = value } }
            }
        }
        let digest = LightDigest(level: level, gates: gates, question: question, sweptCoveragePct: sweptCoveragePct, revision: 0, spoolFrames: kept)
        let capture = PendingCapture(sceneID: sceneID, propertyUUID: property.uuid, roomLabel: roomLabel, capturedAt: log.endedAt, record: record,
                                     observationUUID: UUID(uuidString: log.sessionID) ?? UUID(), digest: digest.encoded,
                                     photo: log.hero?.data, thumbnail: log.hero.flatMap { PhotoScaler.thumbnail($0.data) })
        try PendingCaptures.write(capture)
        do {
            try PendingCaptures.commit(capture, to: property, in: context)
            return Outcome(sceneID: sceneID, shareURL: shareURL, pending: nil, attachError: nil, spoolFrames: kept)
        } catch {
            return Outcome(sceneID: sceneID, shareURL: shareURL, pending: capture, attachError: error.localizedDescription, spoolFrames: kept)
        }
    }

    /// Retries putting a pending record on its property. Idempotent by the row's identity.
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

import Foundation
import SceneRecord

/// Writes a SceneRecord to `<root>/<scene_id>/scene.json`. A scene id is written once: the folder must not exist yet.
public enum SceneExporter {
    public struct Result: Sendable, Equatable {
        public let sceneID: String
        public let fileURL: URL
    }

    /// Allocates the next id for the day and writes the record. `.withoutOverwriting` is deliberate and must not be
    /// combined with `.atomic` (Foundation asserts on that pair; it crashed the device on 2026-09-30).
    public static func export(_ log: CaptureLog, root: URL, now: Date = Date()) throws -> Result {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sceneID = try SceneRecordBuilder.nextSceneID(in: root, date: log.endedAt, timezone: log.timezone)
        let document = try SceneRecordBuilder.build(log, sceneID: sceneID, createdAt: now)
        return try write(document, sceneID: sceneID, root: root)
    }

    public static func write(_ document: SceneRecordDocument, sceneID: String, root: URL) throws -> Result {
        let folder = root.appending(path: sceneID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)   // throws if it exists
        let file = folder.appending(path: "scene.json")
        try document.encoded().write(to: file, options: [.withoutOverwriting])
        return Result(sceneID: sceneID, fileURL: file)
    }
}

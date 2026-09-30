import Foundation

/// Observation photos live in the app sandbox, referenced by relative path (docs/15 §4). Deleting is physical.
public enum MediaStore {
    public static var root: URL {
        URL.documentsDirectory.appending(path: "observations", directoryHint: .isDirectory)
    }

    public static func url(for relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// Writes JPEG data for an observation and returns the relative path to store on the model.
    @discardableResult
    public static func saveJPEG(_ data: Data, for observationID: UUID) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "\(observationID.uuidString).jpg"
        try data.write(to: root.appending(path: name), options: .atomic)
        return name
    }

    public static func delete(_ relativePath: String?) {
        guard let relativePath else { return }
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }

    public static func deleteAll() {
        try? FileManager.default.removeItem(at: root)
    }
}

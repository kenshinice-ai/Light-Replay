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
        removeIgnoringMissing(url(for: relativePath))
    }

    /// Removes every photo. Throws on anything other than "nothing there".
    public static func deleteAll() throws {
        try removeThrowingUnlessMissing(root)
    }

    static func removeIgnoringMissing(_ url: URL) {
        try? removeThrowingUnlessMissing(url)
    }

    static func removeThrowingUnlessMissing(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT { return }
    }
}

/// Measurement records (SceneRecord folders, docs/03 §9) live beside the photos under Documents/scenes.
public enum SceneStore {
    public static var root: URL {
        URL.documentsDirectory.appending(path: "scenes", directoryHint: .isDirectory)
    }

    public static func folder(for sceneID: String) -> URL {
        root.appending(path: sceneID, directoryHint: .isDirectory)
    }

    public static func delete(sceneID: String?) {
        guard let sceneID else { return }
        MediaStore.removeIgnoringMissing(folder(for: sceneID))
    }

    public static func deleteAll() throws {
        try MediaStore.removeThrowingUnlessMissing(root)
    }
}

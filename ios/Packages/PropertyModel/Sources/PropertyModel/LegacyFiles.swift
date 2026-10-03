import Foundation
import SwiftData

/// Before ADR-0017, photos lived in Documents/observations and SceneRecords in Documents/scenes, referenced by path.
/// Now the bytes live on the row. `migrate` moves them in once; files are removed only after the rows are saved.
public enum LegacyFiles {
    public static var mediaRoot: URL { URL.documentsDirectory.appending(path: "observations", directoryHint: .isDirectory) }
    public static var scenesRoot: URL { URL.documentsDirectory.appending(path: "scenes", directoryHint: .isDirectory) }

    public struct Report: Equatable, Sendable {
        public var photos = 0
        public var scenes = 0
        /// Rows whose file was already gone; their path is cleared because nothing can bring it back.
        public var missing = 0
    }

    @MainActor @discardableResult
    public static func migrate(in context: ModelContext, mediaRoot: URL = mediaRoot, scenesRoot: URL = scenesRoot) throws -> Report {
        var report = Report()
        var migratedFiles: [URL] = []
        let files = FileManager.default
        for observation in try context.fetch(FetchDescriptor<InspectionObservation>()) {
            if let path = observation.mediaPath, observation.photoData == nil {
                let url = mediaRoot.appending(path: path)
                if let data = try? Data(contentsOf: url) {
                    observation.photoData = data
                    observation.photoByteCount = data.count   // the thumbnail follows in this launch's backfill (StartupTasks)
                    observation.mediaPath = nil
                    migratedFiles.append(url)
                    report.photos += 1
                } else if !files.fileExists(atPath: url.path) {
                    observation.mediaPath = nil
                    report.missing += 1
                }   // exists but unreadable (for example still protected): keep the path and try on the next launch
            }
            if let sceneID = observation.sceneId, observation.sceneRecordData == nil {
                let folder = scenesRoot.appending(path: sceneID, directoryHint: .isDirectory)
                if let data = try? Data(contentsOf: folder.appending(path: "scene.json")) {
                    observation.sceneRecordData = data
                    migratedFiles.append(folder)
                    report.scenes += 1
                }
            }
        }
        guard report != Report() else { return report }
        try PropertyStore.commit(context)
        // The rows hold the bytes now; a file that fails to go is a harmless copy, swept below or on a later launch.
        for url in migratedFiles { try? removeUnlessMissing(url) }
        return report
    }

    /// Removes the legacy photo folder once no row points into it.
    @MainActor
    public static func sweep(in context: ModelContext, mediaRoot: URL = mediaRoot) throws {
        let referenced = try context.fetchCount(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.mediaPath != nil }))
        if referenced == 0 { try removeUnlessMissing(mediaRoot) }
    }

    /// Everything, including unbound debug captures in Documents/scenes. Used by "Delete everything".
    public static func removeAll(mediaRoot: URL = mediaRoot, scenesRoot: URL = scenesRoot) throws {
        try removeUnlessMissing(mediaRoot)
        try removeUnlessMissing(scenesRoot)
    }

    /// Only "nothing there" is ignored; permission and I/O errors are thrown (reaudit R01).
    static func removeUnlessMissing(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT { return }
    }
}

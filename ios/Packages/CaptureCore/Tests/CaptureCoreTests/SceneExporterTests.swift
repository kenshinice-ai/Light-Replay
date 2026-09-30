import Foundation
import SceneRecord
import XCTest
@testable import CaptureCore

final class SceneExporterTests: XCTestCase {
    private func emptyLog() -> CaptureLog {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CaptureLog(sessionID: "S", startedAt: start, endedAt: start.addingTimeInterval(5), firstFrameAt: nil,
                          timezone: TimeZone(identifier: "Australia/Melbourne")!,
                          device: DeviceInfo(model: "test", os: "iOS 27.0", lidar: false, sceneDepth: false, geoTracking: "unavailable"),
                          appVersion: "0", appBuild: "0", targetLabel: "Synthetic, not a real property", targetHeightM: nil,
                          frames: [], anchor: nil, anchorFrameID: nil, maxDriftM: nil, headings: [], location: nil)
    }

    func testExportWritesOncePerIDAndNeverOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
        let log = emptyLog()
        let expected = { (n: Int) in SceneRecordBuilder.sceneID(date: log.endedAt, sequence: n, timezone: log.timezone) }
        let first = try SceneExporter.export(log, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertEqual(first.sceneID, expected(1))
        // Re-parse what was written: it must be a valid record.
        XCTAssertNoThrow(try SceneRecordDocument(data: try Data(contentsOf: first.fileURL)))
        let second = try SceneExporter.export(log, root: root)
        XCTAssertEqual(second.sceneID, expected(2))
        // Writing the same id again must fail rather than overwrite.
        let document = try SceneRecordBuilder.build(emptyLog(), sceneID: first.sceneID)
        XCTAssertThrowsError(try SceneExporter.write(document, sceneID: first.sceneID, root: root))
    }
}

import CoreLocation
import SwiftData
import XCTest
@testable import PropertyModel

/// Reaudit R01/R02/R07 and ADR-0017: bytes live on rows, captures survive a failed save, stale pins are not used.
@MainActor
final class StorageTests: XCTestCase {
    private let scratch = FileManager.default.temporaryDirectory.appending(path: "pr-storage-\(UUID().uuidString)", directoryHint: .isDirectory)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// The container is held for the whole test: a context does not keep it alive (group memory
    /// swiftdata-test-container-lifetime).
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try PropertyStore.container(inMemory: true)
        self.container = container
        return ModelContext(container)
    }

    private func capture(_ id: String, for property: Property) -> PendingCapture {
        PendingCapture(sceneID: id, propertyUUID: property.uuid, roomLabel: "Living", capturedAt: Date(),
                       record: Data(#"{"scene_id":"\#(id)"}"#.utf8))
    }

    func testPendingCaptureCommitsOnceAndLeavesNoFile() throws {
        let context = try makeContext()
        let property = Property(address: "4 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let pending = capture("PR-20260930-01", for: property)
        try PendingCaptures.write(pending, root: scratch)
        XCTAssertEqual(PendingCaptures.all(root: scratch), [pending])

        let first = try PendingCaptures.commit(pending, to: property, in: context, root: scratch)
        XCTAssertEqual(first.level, .unknown)
        XCTAssertEqual(first.sceneRecordData, pending.record)
        XCTAssertTrue(PendingCaptures.all(root: scratch).isEmpty)

        // A leftover file (for example the remove failed) must not create a second row.
        try PendingCaptures.write(pending, root: scratch)
        let again = try PendingCaptures.commit(pending, to: property, in: context, root: scratch)
        XCTAssertEqual(again.uuid, first.uuid)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InspectionObservation>()), 1)
        XCTAssertEqual(PendingCaptures.takenSceneIDs(in: context, root: scratch), ["PR-20260930-01"])
    }

    func testRecoverAttachesToTheRightPropertyAndKeepsOrphans() throws {
        let context = try makeContext()
        let a = Property(address: "5 Test Lane, Nowhere VIC 3000")
        let b = Property(address: "6 Test Lane, Nowhere VIC 3000")
        context.insert(a); context.insert(b)
        try context.save()
        try PendingCaptures.write(capture("PR-20260930-01", for: b), root: scratch)
        let gone = Property(address: "deleted before recovery")
        try PendingCaptures.write(capture("PR-20260930-02", for: gone), root: scratch)

        let result = PendingCaptures.recover(in: context, root: scratch)
        XCTAssertEqual(result.recovered, 1)
        XCTAssertEqual(result.waiting, 1)
        XCTAssertTrue(a.allObservations.isEmpty, "never attached to another property")
        XCTAssertEqual(b.allObservations.first?.sceneId, "PR-20260930-01")
        XCTAssertEqual(PendingCaptures.all(root: scratch).map(\.sceneID), ["PR-20260930-02"])
    }

    func testLegacyFilesMoveIntoRowsThenLeaveDisk() throws {
        let context = try makeContext()
        let media = scratch.appending(path: "observations", directoryHint: .isDirectory)
        let scenes = scratch.appending(path: "scenes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scenes.appending(path: "PR-20260930-01"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scenes.appending(path: "PR-20260930-09"), withIntermediateDirectories: true)   // unbound debug capture
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        try jpeg.write(to: media.appending(path: "a.jpg"))
        try Data("{}".utf8).write(to: scenes.appending(path: "PR-20260930-01/scene.json"))

        let property = Property(address: "7 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let photo = InspectionObservation(kind: .photo, source: .userPhoto)
        photo.mediaPath = "a.jpg"
        let gone = InspectionObservation(kind: .photo, source: .userPhoto)
        gone.mediaPath = "missing.jpg"
        let light = InspectionObservation(kind: .light, source: .sensor)
        light.sceneId = "PR-20260930-01"
        for o in [photo, gone, light] { try PropertyStore.record(o, for: property, in: context) }

        let report = try LegacyFiles.migrate(in: context, mediaRoot: media, scenesRoot: scenes)
        XCTAssertEqual(report, LegacyFiles.Report(photos: 1, scenes: 1, missing: 1))
        XCTAssertEqual(photo.photoData, jpeg)
        XCTAssertNil(photo.mediaPath)
        XCTAssertEqual(light.sceneRecordData, Data("{}".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.appending(path: "a.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scenes.appending(path: "PR-20260930-01").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scenes.appending(path: "PR-20260930-09").path), "unbound captures are not touched")

        try LegacyFiles.sweep(in: context, mediaRoot: media)
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path))
        XCTAssertEqual(try LegacyFiles.migrate(in: context, mediaRoot: media, scenesRoot: scenes), LegacyFiles.Report(), "second run is a no-op")
    }

    func testRemovalReportsPermissionErrors() throws {
        let locked = scratch.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data([1]).write(to: locked.appending(path: "x.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try LegacyFiles.removeUnlessMissing(locked.appending(path: "x.jpg")))
        XCTAssertNoThrow(try LegacyFiles.removeUnlessMissing(scratch.appending(path: "never-existed")))
    }

    func testEditingTheAddressMakesThePinStale() {
        let property = Property(address: "8 Test Lane, Nowhere VIC 3000", latitude: -37.8, longitude: 144.9)
        XCTAssertNotNil(property.coordinate)
        property.address = "9 Other Street, Elsewhere VIC 3001"
        XCTAssertTrue(property.isPinStale)
        XCTAssertNil(property.coordinate)
        XCTAssertNil(property.distance(from: CLLocation(latitude: -37.8, longitude: 144.9)))
        property.setPin(latitude: -37.7, longitude: 145.0, suburb: "Elsewhere", forAddress: property.address)
        XCTAssertFalse(property.isPinStale)
        XCTAssertEqual(property.coordinate?.latitude, -37.7)
    }

    func testDuplicatePreferencesFromTwoDevicesCollapseToTheOldest() throws {
        let context = try makeContext()
        let older = UserPreferences(displayName: "phone")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = UserPreferences(displayName: "ipad")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        context.insert(newer); context.insert(older)
        try context.save()
        XCTAssertEqual(try PropertyStore.preferences(in: context).displayName, "phone")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserPreferences>()), 1)
    }
}

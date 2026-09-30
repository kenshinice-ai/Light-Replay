import SwiftData
import XCTest
@testable import PropertyModel

/// Saves that fail, on a real on-disk store. The app must neither crash nor leave half a change behind, and must never
/// call `rollback()` (it traps after deleting a model with external storage; group memory, PWE Receipts 2026-09-30).
@MainActor
final class FailureInjectionTests: XCTestCase {
    private struct DiskFull: Error {}
    private var folder: URL!
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pr-failure-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        container = try PropertyStore.container(storeURL: folder.appending(path: "library.store"))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        PropertyStore.save = { try $0.save() }
        context = nil
        container = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func failingSaves() { PropertyStore.save = { _ in throw DiskFull() } }
    private func workingSaves() { PropertyStore.save = { try $0.save() } }
    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int { try context.fetchCount(FetchDescriptor<T>()) }

    private func propertyWithPhoto() throws -> (Property, InspectionObservation) {
        let property = Property(address: "10 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let photo = InspectionObservation(kind: .photo, source: .userPhoto)
        photo.photoData = Data(repeating: 0xAB, count: 200_000)   // large enough to go to external storage
        try PropertyStore.record(photo, for: property, in: context)
        return (property, photo)
    }

    func testFailedRecordLeavesNothingAndRetrySavesOnce() throws {
        let property = Property(address: "11 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        try context.save()

        failingSaves()
        let note = InspectionObservation(kind: .voice, source: .userVoice, text: "first try")
        XCTAssertThrowsError(try PropertyStore.record(note, for: property, in: context))
        XCTAssertEqual(property.status, .toInspect, "status change undone")

        workingSaves()
        let again = InspectionObservation(kind: .voice, source: .userVoice, text: "second try")
        try PropertyStore.record(again, for: property, in: context)
        XCTAssertEqual(try count(InspectionObservation.self), 1)
        XCTAssertEqual(try count(Inspection.self), 1, "the failed attempt's inspection is gone too")
        XCTAssertEqual(property.allObservations.map(\.text), ["second try"])
    }

    func testFailedDeleteOfAPhotoDoesNotTrapAndCompletesLater() throws {
        let (_, photo) = try propertyWithPhoto()
        failingSaves()
        XCTAssertThrowsError(try PropertyStore.delete(photo, in: context))   // would trap here with rollback()
        workingSaves()
        try PropertyStore.commit(context)
        XCTAssertEqual(try count(InspectionObservation.self), 0)
    }

    func testFailedPropertyDeleteWithPhotosDoesNotTrap() throws {
        let (property, _) = try propertyWithPhoto()
        failingSaves()
        XCTAssertThrowsError(try PropertyStore.delete(property, in: context))
        XCTAssertThrowsError(try PropertyStore.deleteEverything(in: context))
        workingSaves()
        try PropertyStore.commit(context)
        XCTAssertEqual(try count(Property.self), 0)
        XCTAssertEqual(try count(InspectionObservation.self), 0)
    }

    func testFailedAddThenRetryKeepsOneProperty() throws {
        failingSaves()
        let first = Property(address: "12 Test Lane, Nowhere VIC 3000")
        context.insert(first)
        XCTAssertThrowsError(try PropertyStore.commit(context, discardingInserted: [first]))
        workingSaves()
        let second = Property(address: "12 Test Lane, Nowhere VIC 3000")
        context.insert(second)
        try PropertyStore.commit(context, discardingInserted: [second])
        XCTAssertEqual(try count(Property.self), 1)
    }

    func testPendingCaptureSurvivesAFailedSave() throws {
        let property = Property(address: "13 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        try context.save()
        let pending = PendingCapture(sceneID: "PR-20260930-01", propertyUUID: property.uuid, roomLabel: nil,
                                     capturedAt: Date(), record: Data("{}".utf8))
        try PendingCaptures.write(pending, root: folder)
        failingSaves()
        XCTAssertThrowsError(try PendingCaptures.commit(pending, to: property, in: context, root: folder))
        XCTAssertEqual(PendingCaptures.all(root: folder), [pending], "the capture is still on disk")
        workingSaves()
        XCTAssertEqual(PendingCaptures.recover(in: context, root: folder).recovered, 1)
        XCTAssertEqual(try count(InspectionObservation.self), 1)
    }
}

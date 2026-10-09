import SwiftData
import XCTest
@testable import PropertyModel

/// The Light row's own facts live in a digest, the buyer's words in `text`, and a scan is known by its row identity
/// rather than its scene id (ADR-0022, reviews V2-04 and R06). Fictional homes only.
final class LightDigestTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL.temporaryDirectory.appending(path: "light-digest-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    /// Held for the whole test: a context does not keep its container alive (group memory swiftdata-test-container-lifetime).
    private var container: ModelContainer?

    @MainActor
    private func home() throws -> (ModelContext, Property) {
        let container = try PropertyStore.container(inMemory: true)
        self.container = container
        let context = container.mainContext
        let property = Property(address: "20 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        try context.save()
        return (context, property)
    }

    private func capture(_ sceneID: String, for property: Property, uuid: UUID? = UUID(), digest: LightDigest? = LightDigest(question: "winter", sweptCoveragePct: 94)) -> PendingCapture {
        PendingCapture(sceneID: sceneID, propertyUUID: property.uuid, roomLabel: "Living", capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
                       record: Data("{}".utf8), observationUUID: uuid, digest: digest?.encoded,
                       photo: Data(repeating: 0xAB, count: 4_000), thumbnail: Data(repeating: 0x01, count: 300))
    }

    @MainActor
    func testANewScanKeepsItsIdentityItsHeroAndLeavesTheBuyersWordsAlone() throws {
        let (context, property) = try home()
        let pending = capture("PR-20261004-01", for: property)
        try PendingCaptures.write(pending, root: scratch)
        let row = try PendingCaptures.commit(pending, to: property, in: context, root: scratch)
        XCTAssertEqual(row.uuid, pending.observationUUID)
        XCTAssertNil(row.text, "the status is not written into the buyer's column")
        XCTAssertEqual(row.lightDigest?.sweptCoveragePct, 94)
        XCTAssertEqual(row.headline, "Light scan · camera covered 94% of the winter sun path · sunlight not calculated")
        XCTAssertEqual(row.photoByteCount, 4_000)
        XCTAssertEqual(row.thumbnailData?.count, 300)
        XCTAssertTrue(PendingCaptures.all(root: scratch).isEmpty)
        // The buyer writes something; the headline is theirs from then on, and the digest is untouched.
        row.correctText(to: "Bright even at four in the afternoon")
        XCTAssertEqual(row.headline, "Bright even at four in the afternoon")
        XCTAssertEqual(row.lightDigest?.sweptCoveragePct, 94)
    }

    @MainActor
    func testCommittingTwiceAddsOneRow() throws {
        let (context, property) = try home()
        let pending = capture("PR-20261004-01", for: property)
        let first = try PendingCaptures.commit(pending, to: property, in: context, root: scratch)
        try PendingCaptures.write(pending, root: scratch)   // a leftover from a crash after the save
        let again = try PendingCaptures.commit(pending, to: property, in: context, root: scratch)
        XCTAssertEqual(first.uuid, again.uuid)
        XCTAssertEqual(property.allObservations.count, 1)
    }

    /// Two devices number their scans independently, so two scans can share a scene id (recovery check 8). They are
    /// different scans and must become different rows, each with its own pending file.
    @MainActor
    func testTwoScansWithOneSceneIDStayTwoScans() throws {
        let (context, property) = try home()
        let one = capture("PR-20261004-01", for: property), other = capture("PR-20261004-01", for: property)
        try PendingCaptures.write(one, root: scratch)
        try PendingCaptures.write(other, root: scratch)
        XCTAssertEqual(PendingCaptures.all(root: scratch).count, 2, "one file each, not one overwriting the other")
        XCTAssertEqual(PendingCaptures.recover(in: context, root: scratch).recovered, 2)
        XCTAssertEqual(Set(property.allObservations.map(\.uuid)), [one.observationUUID!, other.observationUUID!])
    }

    @MainActor
    func testAFileFromBeforeIdentitiesStillCommitsOnceByItsSceneID() throws {
        let (context, property) = try home()
        let old = PendingCapture(sceneID: "PR-20260930-01", propertyUUID: property.uuid, roomLabel: nil, capturedAt: Date(),
                                 record: Data("{}".utf8), note: "Light measurement recorded (analysis pending)")
        let first = try PendingCaptures.commit(old, to: property, in: context, root: scratch)
        let again = try PendingCaptures.commit(old, to: property, in: context, root: scratch)
        XCTAssertEqual(first.uuid, again.uuid)
        XCTAssertEqual(first.text, "Light measurement recorded (analysis pending)")
        XCTAssertNil(first.lightDigestData)
    }

    func testOnlyASentenceTheAppWroteIsRecognised() {
        let winter = LightStatusMigration.digest(fromGenerated: "Light scan · camera covered 94% of the winter sun path · sunlight not calculated")
        XCTAssertEqual(winter, LightDigest(question: "winter", sweptCoveragePct: 94))
        let chinese = LightStatusMigration.digest(fromGenerated: "光线扫描 · 镜头覆盖了98路径的 全年阳光% · 日照未计算")
        XCTAssertEqual(chinese, LightDigest(question: "allYear", sweptCoveragePct: 98))
        XCTAssertEqual(LightStatusMigration.digest(fromGenerated: "Light scan · winter sun path 92% seen · analysis pending"),
                       LightDigest(question: "winter", sweptCoveragePct: 92))
        XCTAssertEqual(LightStatusMigration.digest(fromGenerated: "Light measurement recorded (analysis pending)"), LightDigest())
        // Close is not the same: a buyer who wrote around the sentence keeps every word.
        for theirs in ["Light scan · camera covered 94% of the winter sun path · sunlight not calculated — but it felt dark",
                       "light scan · camera covered 94% of the winter sun path · sunlight not calculated",
                       "Camera covered 94% of the winter sun path", ""] {
            XCTAssertNil(LightStatusMigration.digest(fromGenerated: theirs), theirs)
        }
    }

    @MainActor
    func testMigrationMovesGeneratedSentencesAndNothingElse() throws {
        let (context, property) = try home()
        func scan(_ text: String?, edited original: String? = nil) throws -> InspectionObservation {
            let row = InspectionObservation(kind: .light, category: .naturalLight, source: .sensor, text: text)
            row.originalText = original
            try PropertyStore.record(row, for: property, in: context)
            return row
        }
        let generated = try scan("Light scan · camera covered 91% of the winter sun path · sunlight not calculated")
        let edited = try scan("Checked again in the afternoon", edited: "Light scan · camera covered 91% of the winter sun path · sunlight not calculated")
        // Reads like the app's sentence, but the buyer edited the row: their text is not the app's to remove.
        let lookalike = try scan("Light scan · camera covered 91% of the winter sun path · sunlight not calculated", edited: "something they said first")
        let photo = InspectionObservation(kind: .photo, source: .userPhoto, text: "Light scan · camera covered 91% of the winter sun path · sunlight not calculated")
        try PropertyStore.record(photo, for: property, in: context)

        XCTAssertEqual(try LightStatusMigration.migrate(in: context), 3)
        XCTAssertNil(generated.text)
        XCTAssertEqual(generated.lightDigest, LightDigest(question: "winter", sweptCoveragePct: 91))
        XCTAssertEqual(generated.headline, "Light scan · camera covered 91% of the winter sun path · sunlight not calculated")
        XCTAssertEqual(edited.text, "Checked again in the afternoon")
        XCTAssertEqual(edited.lightDigest, LightDigest())
        XCTAssertEqual(lookalike.text, "Light scan · camera covered 91% of the winter sun path · sunlight not calculated")
        XCTAssertNil(photo.lightDigestData, "only light rows")
        XCTAssertNotNil(photo.text)
        XCTAssertEqual(try LightStatusMigration.migrate(in: context), 0, "nothing left to do the second time")
    }
}

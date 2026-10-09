import SwiftData
import XCTest
@testable import PropertyModel

@MainActor
final class ObservationTests: XCTestCase {
    /// The container is held for the whole test: a context does not keep it alive (group memory
    /// swiftdata-test-container-lifetime).
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try PropertyStore.container(inMemory: true)
        self.container = container
        return ModelContext(container)
    }

    func testOpenInspectionIsReusedUntilEnded() throws {
        let context = try makeContext()
        let property = Property(address: "1 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let first = PropertyStore.openInspection(for: property, in: context)
        let again = PropertyStore.openInspection(for: property, in: context)
        XCTAssertEqual(first.uuid, again.uuid)
        first.endedAt = Date()
        let next = PropertyStore.openInspection(for: property, in: context)
        XCTAssertNotEqual(first.uuid, next.uuid)
        XCTAssertEqual(property.inspections?.count, 2)
    }

    func testObservationLevelsFollowRules() {
        XCTAssertEqual(InspectionObservation.level(for: .photo, source: .userPhoto), .observedNoted)
        XCTAssertEqual(InspectionObservation.level(for: .voice, source: .userVoice), .observedNoted)
        XCTAssertEqual(InspectionObservation.level(for: .light, source: .sensor), .unknown, "light is never measured by construction")
        XCTAssertEqual(InspectionObservation.level(for: .voice, source: .model), .indicative)
        XCTAssertEqual(InspectionObservation.lightLevel(qualityLevel: "R1", falseValidGuard: "passed", bandState: "direct"), .observedMeasured)
        XCTAssertEqual(InspectionObservation.lightLevel(qualityLevel: "R1", falseValidGuard: "passed", bandState: "sensitive"), .indicative)
        XCTAssertEqual(InspectionObservation.lightLevel(qualityLevel: "R1", falseValidGuard: "passed", bandState: "unknown"), .unknown)
        XCTAssertEqual(InspectionObservation.lightLevel(qualityLevel: "R0", falseValidGuard: "blocked", bandState: "direct"), .unknown)
        XCTAssertEqual(InspectionObservation.lightLevel(qualityLevel: "R2", falseValidGuard: "blocked", bandState: "direct"), .unknown)
    }

    func testAskSetsFollowUpAndCascadeDelete() throws {
        let context = try makeContext()
        let property = Property(address: "2 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let observation = InspectionObservation(kind: .voice, category: .naturalLight, source: .userVoice, text: "Ask about the extension permit", roomLabel: "Living")
        observation.sentiment = .ask
        observation.photoData = Data([0xFF, 0xD8])
        try PropertyStore.record(observation, for: property, in: context)
        XCTAssertTrue(observation.followUp)
        XCTAssertEqual(property.allObservations.count, 1)
        XCTAssertEqual(property.status, .inspected, "recording something marks the property inspected")
        context.delete(property)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<InspectionObservation>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Inspection>()).count, 0)
    }

    func testHeadlinePrefersBuyerWords() {
        let photo = InspectionObservation(kind: .photo, source: .userPhoto)
        XCTAssertEqual(photo.headline, "Photo")
        let voice = InspectionObservation(kind: .voice, source: .userVoice, text: "Felt darker than the listing photos")
        XCTAssertEqual(voice.headline, "Felt darker than the listing photos")
        voice.text = nil
        voice.summary = "Darker than photos"
        XCTAssertEqual(voice.headline, "Darker than photos")
    }
}

extension ObservationTests {
    func testAPhotoKeepsItsSizeAndThumbnailAndNoticesLostBytes() {
        let photo = InspectionObservation(kind: .photo, source: .userPhoto)
        XCTAssertFalse(photo.photoIsHere)
        let bytes = Data(repeating: 0xAB, count: 50_000)
        photo.attachPhoto(bytes, thumbnail: Data(repeating: 0x01, count: 900))
        XCTAssertTrue(photo.photoIsHere)
        XCTAssertEqual(photo.photoByteCount, 50_000)
        XCTAssertEqual(photo.thumbnailData?.count, 900)
        // What a store with a missing external file hands back: a short reference, not nil (group memory).
        photo.photoData = Data(repeating: 0x00, count: 38)
        XCTAssertFalse(photo.photoIsHere, "38 bytes are not a 50,000-byte photo")
        let old = InspectionObservation(kind: .photo, source: .userPhoto)
        old.photoData = bytes   // a row from before counts were kept
        XCTAssertTrue(old.photoIsHere, "rows without a recorded count are trusted")
    }

    @MainActor
    func testPhotosWithoutThumbnailsAreFoundWithoutLoadingThem() throws {
        let container = try PropertyStore.container(inMemory: true)
        let context = container.mainContext
        let property = Property(address: "20 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let legacy = InspectionObservation(kind: .photo, source: .userPhoto)
        legacy.photoData = Data(repeating: 0xCD, count: 10_000)   // migrated from a file: no thumbnail yet
        try PropertyStore.record(legacy, for: property, in: context)
        let fresh = InspectionObservation(kind: .photo, source: .userPhoto)
        fresh.attachPhoto(Data(repeating: 0xEF, count: 10_000), thumbnail: Data(repeating: 0x02, count: 500))
        try PropertyStore.record(fresh, for: property, in: context)
        let note = InspectionObservation(kind: .voice, source: .userVoice, text: "no photo at all")
        try PropertyStore.record(note, for: property, in: context)

        let pending = try PropertyStore.photosWithoutThumbnails(in: context)
        XCTAssertEqual(pending.map(\.uuid), [legacy.uuid], "only the photo with no thumbnail, never the note")
        legacy.thumbnailData = Data()
        try PropertyStore.commit(context)
        XCTAssertTrue(try PropertyStore.photosWithoutThumbnails(in: context).isEmpty)
    }

    func testCorrectingATranscriptKeepsTheOriginalOnce() {
        let note = InspectionObservation(kind: .voice, source: .userVoice, text: "The living room felt dimmer than the fotos")
        XCTAssertNil(note.originalText)
        note.correctText(to: "The living room felt dimmer than the photos")
        XCTAssertEqual(note.originalText, "The living room felt dimmer than the fotos")
        note.correctText(to: "The living room felt darker than the photos ")
        XCTAssertEqual(note.text, "The living room felt darker than the photos")
        XCTAssertEqual(note.originalText, "The living room felt dimmer than the fotos", "only the first version is the original")
        XCTAssertEqual(note.level, .observedNoted, "still the buyer's own words")
        note.correctText(to: "The living room felt dimmer than the fotos")
        XCTAssertNil(note.originalText, "back to the original: nothing was corrected")

        let photo = InspectionObservation(kind: .photo, source: .userPhoto)
        photo.correctText(to: "North window")
        XCTAssertEqual(photo.text, "North window")
        XCTAssertNil(photo.originalText, "a first caption has no original")
    }
}

import SwiftData
import XCTest
@testable import PropertyModel

@MainActor
final class ObservationTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try PropertyStore.container(inMemory: true))
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
        XCTAssertEqual(property.inspections.count, 2)
    }

    func testObservationLevelsFollowRules() {
        XCTAssertEqual(InspectionObservation.level(for: .photo, source: .userPhoto), .observedNoted)
        XCTAssertEqual(InspectionObservation.level(for: .voice, source: .userVoice), .observedNoted)
        XCTAssertEqual(InspectionObservation.level(for: .light, source: .sensor), .observedMeasured)
        XCTAssertEqual(InspectionObservation.level(for: .voice, source: .model), .indicative)
    }

    func testAskSetsFollowUpAndCascadeDelete() throws {
        let context = try makeContext()
        let property = Property(address: "2 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        let inspection = PropertyStore.openInspection(for: property, in: context)
        let observation = InspectionObservation(kind: .voice, category: .naturalLight, source: .userVoice, text: "Ask about the extension permit", roomLabel: "Living")
        observation.sentiment = .ask
        observation.inspection = inspection
        inspection.observations.append(observation)
        try context.save()
        XCTAssertTrue(observation.followUp)
        XCTAssertEqual(property.allObservations.count, 1)
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

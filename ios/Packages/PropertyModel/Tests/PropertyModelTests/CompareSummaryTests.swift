import SwiftData
import XCTest
@testable import PropertyModel

@MainActor
final class CompareSummaryTests: XCTestCase {
    private var container: ModelContainer?

    private func makeProperty() throws -> (Property, ModelContext) {
        let container = try PropertyStore.container(inMemory: true)
        self.container = container
        let context = ModelContext(container)
        let property = Property(address: "20 Test Lane, Nowhere VIC 3000")
        context.insert(property)
        return (property, context)
    }

    private func add(_ kind: ObservationKind, _ category: ObservationCategory, _ sentiment: Sentiment,
                     to property: Property, in context: ModelContext) throws {
        let source: EvidenceSource = kind == .light ? .sensor : (kind == .photo ? .userPhoto : .userVoice)
        try PropertyStore.record(InspectionObservation(kind: kind, category: category, sentiment: sentiment, source: source),
                                 for: property, in: context)
    }

    func testEveryKindOfNothingIsNamed() throws {
        let (property, context) = try makeProperty()
        XCTAssertEqual(CompareSummary.cell(for: .privacy, at: property).state, .notRecorded)
        XCTAssertEqual(CompareSummary.cell(for: .privacy, at: property).headline, "Not recorded")
        XCTAssertEqual(CompareSummary.cell(for: .commute, at: property).state, .noSource, "no category records commute yet")
        XCTAssertEqual(CompareSummary.cell(for: .commute, at: property).headline, "Not in the app yet")

        try add(.light, .naturalLight, .neutral, to: property, in: context)
        let light = CompareSummary.cell(for: .naturalLight, at: property)
        XCTAssertEqual(light.state, .scannedNotCalculated, "a scan is not a sunlight result")
        XCTAssertEqual(light.headline, "Scanned, sunlight not calculated")
        XCTAssertNil(light.detail)
        XCTAssertEqual(CompareSummary.cell(for: .privacy, at: property).state, .notRecorded, "a light scan says nothing about privacy")
    }

    func testCellsCountTheBuyersOwnTags() throws {
        let (property, context) = try makeProperty()
        try add(.photo, .noise, .concern, to: property, in: context)
        try add(.voice, .noise, .like, to: property, in: context)
        try add(.voice, .noise, .like, to: property, in: context)
        try add(.voice, .noise, .ask, to: property, in: context)
        try add(.voice, .noise, .neutral, to: property, in: context)
        try add(.voice, .space, .like, to: property, in: context)

        let quiet = CompareSummary.cell(for: .quiet, at: property)
        XCTAssertEqual(quiet.state, .noted)
        XCTAssertEqual(quiet.headline, "2 likes · 1 concern · 1 to confirm · 1 note")
        XCTAssertEqual(CompareSummary.observations(for: .quiet, at: property).count, 5)
        XCTAssertEqual(CompareSummary.cell(for: .space, at: property).headline, "1 like")

        try add(.voice, .naturalLight, .concern, to: property, in: context)
        try add(.light, .naturalLight, .neutral, to: property, in: context)
        let light = CompareSummary.cell(for: .naturalLight, at: property)
        XCTAssertEqual(light.headline, "Scanned, sunlight not calculated")
        XCTAssertEqual(light.detail, "1 concern", "the buyer's own note sits under the scan state")
        XCTAssertEqual(light.scans, 1)
    }

    func testEveryPriorityHasACellAndNoneIsANumberOutOfTen() throws {
        let (property, _) = try makeProperty()
        for dimension in PriorityDimension.allCases {
            let cell = CompareSummary.cell(for: dimension, at: property)
            XCTAssertFalse(cell.headline.isEmpty)
            XCTAssertFalse(cell.headline.contains("/"), "no scores")
            XCTAssertFalse(cell.hasEvidence)
        }
    }
}

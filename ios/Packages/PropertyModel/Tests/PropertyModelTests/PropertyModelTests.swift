import CoreLocation
import SwiftData
import XCTest
@testable import PropertyModel

@MainActor
final class PropertyModelTests: XCTestCase {
    /// The container is held for the whole test: a context does not keep it alive (group memory
    /// swiftdata-test-container-lifetime).
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try PropertyStore.container(inMemory: true)
        self.container = container
        return ModelContext(container)
    }

    func testInsertAndFetchProperty() throws {
        let context = try makeContext()
        context.insert(Property(address: "1 Test Lane, Nowhere VIC 3000", latitude: -37.8, longitude: 144.9))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Property>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.shortAddress, "1 Test Lane")
        XCTAssertEqual(fetched.first?.status, .toInspect)
        XCTAssertNotNil(fetched.first?.coordinate)
    }

    func testPropertyWithoutCoordinatesHasNoDistance() throws {
        let property = Property(address: "No coordinates yet")
        XCTAssertNil(property.coordinate)
        XCTAssertNil(property.distance(from: CLLocation(latitude: 0, longitude: 0)))
    }

    func testPreferencesSingletonAndPriorityCap() throws {
        let context = try makeContext()
        let first = try PropertyStore.preferences(in: context)
        let second = try PropertyStore.preferences(in: context)
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        first.priorities = []
        for dimension in PriorityDimension.allCases { first.toggle(dimension) }
        XCTAssertEqual(first.priorities.count, UserPreferences.maximumPriorities)
        first.toggle(.naturalLight)   // toggling a selected one removes it
        XCTAssertFalse(first.priorities.contains(.naturalLight))
    }

    func testSamplesAreLabelledAndDeletable() throws {
        let context = try makeContext()
        try SampleData.insert(into: context)
        let properties = try context.fetch(FetchDescriptor<Property>())
        XCTAssertEqual(properties.count, SampleData.items.count)
        XCTAssertTrue(properties.allSatisfy(\.isSample))
        try PropertyStore.deleteEverything(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Property>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreferences>()).count, 0)
    }
}

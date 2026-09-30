import Foundation
import SwiftData

/// Container factory and the few queries that are not one-liners.
public enum PropertyStore {
    public static let schema = Schema([Property.self, Inspection.self, InspectionObservation.self, UserPreferences.self])

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The single preferences row, created on first use.
    @MainActor
    public static func preferences(in context: ModelContext) throws -> UserPreferences {
        if let existing = try context.fetch(FetchDescriptor<UserPreferences>()).first { return existing }
        let created = UserPreferences()
        context.insert(created)
        try context.save()
        return created
    }

    /// Removes every property and resets preferences. Physical deletion, no soft delete (docs/15 §4).
    @MainActor
    public static func deleteEverything(in context: ModelContext) throws {
        try context.delete(model: InspectionObservation.self)
        try context.delete(model: Inspection.self)
        try context.delete(model: Property.self)
        try context.delete(model: UserPreferences.self)
        try context.save()
        MediaStore.deleteAll()
    }

    /// Finds the open inspection for a property or starts one.
    @MainActor
    public static func openInspection(for property: Property, in context: ModelContext) -> Inspection {
        if let open = property.openInspection { return open }
        let inspection = Inspection(property: property)
        context.insert(inspection)
        property.inspections.append(inspection)
        return inspection
    }
}

/// Fictional properties for simulator and prototype sessions. Addresses do not exist; coordinates are generic
/// suburb centres, not real dwellings (docs/CLAUDE.md: examples are fictional and labelled).
public enum SampleData {
    public struct Item: Sendable {
        public let address: String
        public let suburb: String
        public let latitude: Double
        public let longitude: Double
        public let status: PropertyStatus
        public let inspectionOffsetDays: Int?
    }

    public static let items: [Item] = [
        Item(address: "12 Example Street, Brunswick VIC 3056", suburb: "Brunswick", latitude: -37.7677, longitude: 144.9600, status: .toInspect, inspectionOffsetDays: 2),
        Item(address: "8 Sample Avenue, Box Hill VIC 3128", suburb: "Box Hill", latitude: -37.8190, longitude: 145.1210, status: .inspected, inspectionOffsetDays: -5),
        Item(address: "3/21 Placeholder Road, Richmond VIC 3121", suburb: "Richmond", latitude: -37.8230, longitude: 144.9980, status: .shortlisted, inspectionOffsetDays: -12)
    ]

    @MainActor
    public static func insert(into context: ModelContext, now: Date = Date()) throws {
        for item in items {
            let inspectionAt = item.inspectionOffsetDays.map { now.addingTimeInterval(Double($0) * 86_400) }
            context.insert(Property(address: item.address, suburb: item.suburb, latitude: item.latitude,
                                    longitude: item.longitude, source: .sample, status: item.status,
                                    inspectionAt: inspectionAt))
        }
        try context.save()
    }
}

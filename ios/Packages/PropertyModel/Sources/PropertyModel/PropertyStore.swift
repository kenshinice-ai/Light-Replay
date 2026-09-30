import Foundation
import SwiftData

/// Container factory, transactions and the few queries that are not one-liners. The database is the single source of
/// truth for rows and their bytes (ADR-0017).
///
/// Failure rule: never `ModelContext.rollback()`. It traps once a model with an external-storage attribute has been
/// deleted in the context (group memory swiftdata-rollback-after-delete-traps; found in PWE Receipts 2026-09-30).
/// A failed insert removes what it inserted by hand; a failed delete stays pending and completes on the next save.
public enum PropertyStore {
    public static let schema = Schema([Property.self, Inspection.self, InspectionObservation.self, UserPreferences.self])
    /// The CloudKit container for the private database (ADR-0017). Must match the app's iCloud entitlement.
    public static let cloudContainerID = "iCloud.com.pwegroup.propertyreplay"

    /// `iCloudSync` mirrors the store to the person's private CloudKit database; tests and the memory fallback never sync.
    public static func container(inMemory: Bool = false, iCloudSync: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: iCloudSync && !inMemory ? .private(cloudContainerID) : .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An on-disk store at a given URL, never synced. For failure-injection tests on a real store.
    public static func container(storeURL: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
    }

    /// The save itself. Tests replace it to inject failures.
    @MainActor public static var save: (ModelContext) throws -> Void = { try $0.save() }

    /// Saves; on failure deletes the models this change inserted (so a retry never duplicates them) and rethrows.
    /// Callers detach relationships to surviving models first, so nothing keeps pointing at a discarded model.
    @MainActor
    public static func commit(_ context: ModelContext, discardingInserted inserted: [any PersistentModel] = []) throws {
        do { try save(context) } catch {
            for model in inserted { context.delete(model) }
            throw error
        }
    }

    /// The preferences row, created on first use. Two devices can each create one before they sync; the oldest wins
    /// and the others are removed, so every screen reads the same row.
    @MainActor
    public static func preferences(in context: ModelContext) throws -> UserPreferences {
        let rows = try context.fetch(FetchDescriptor<UserPreferences>(sortBy: [SortDescriptor(\.createdAt)]))
        if let oldest = rows.first {
            if rows.count > 1 {
                rows.dropFirst().forEach(context.delete)
                try commit(context)
            }
            return oldest
        }
        let created = UserPreferences()
        context.insert(created)
        try commit(context, discardingInserted: [created])
        return created
    }

    /// Removes every property and resets preferences, here and (with sync on) in iCloud. Physical deletion, no soft
    /// delete (docs/15 §4). Rows go first because they hold the bytes; legacy folders are removed afterwards and an
    /// error there is reported, not hidden.
    /// Deletes row by row: SwiftData's batch `delete(model:)` traps on save when the context already holds a pending
    /// delete of a model with external storage (FailureInjectionTests, 2026-09-30).
    @MainActor
    public static func deleteEverything(in context: ModelContext) throws {
        for property in try context.fetch(FetchDescriptor<Property>()) where !property.isDeleted { context.delete(property) }
        for inspection in try context.fetch(FetchDescriptor<Inspection>()) where !inspection.isDeleted { context.delete(inspection) }
        for observation in try context.fetch(FetchDescriptor<InspectionObservation>()) where !observation.isDeleted { context.delete(observation) }
        for preferences in try context.fetch(FetchDescriptor<UserPreferences>()) where !preferences.isDeleted { context.delete(preferences) }
        try commit(context)
        try LegacyFiles.removeAll()
    }

    /// Deletes one property with everything recorded for it (cascade). Photos and records go with their rows. If the save
    /// fails the deletion stays pending and completes with the next successful save.
    @MainActor
    public static func delete(_ property: Property, in context: ModelContext) throws {
        context.delete(property)
        try commit(context)
    }

    /// Deletes one observation and its photo or record.
    @MainActor
    public static func delete(_ observation: InspectionObservation, in context: ModelContext) throws {
        context.delete(observation)
        try commit(context)
    }

    /// Finds the open inspection for a property or starts one. Does not save.
    @MainActor
    public static func openInspection(for property: Property, in context: ModelContext) -> Inspection {
        if let open = property.openInspection { return open }
        let inspection = Inspection()
        context.insert(inspection)
        inspection.property = property
        return inspection
    }

    /// Adds an observation to the property's open inspection and saves; on failure nothing of this change is kept.
    @MainActor
    public static func record(_ observation: InspectionObservation, for property: Property, in context: ModelContext) throws {
        let startsInspection = property.openInspection == nil
        let inspection = openInspection(for: property, in: context)
        let previousStatus = property.status
        context.insert(observation)
        observation.inspection = inspection
        if property.status == .toInspect { property.status = .inspected }
        do {
            try save(context)
        } catch {
            // Undo by hand (never rollback): detach, then delete what this call inserted.
            observation.inspection = nil
            context.delete(observation)
            if startsInspection {
                inspection.property = nil
                context.delete(inspection)
            }
            property.status = previousStatus
            throw error
        }
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
        try PropertyStore.commit(context)
    }
}

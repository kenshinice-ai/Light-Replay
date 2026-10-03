import CoreData
import Foundation
import SwiftData

extension PropertyStore {
    /// Creates every record type and field of the schema in the CloudKit **development** environment, so that the
    /// schema can be deployed to production complete.
    ///
    /// CloudKit adds a field the first time a record carries a value in it. After a week of real use the development
    /// schema still lacked `CD_originalText`, `CD_property`, `CD_mediaPath` and `CD_notes` (seen in the console,
    /// 2026-10-03); deployed like that, the first corrected transcript or standalone note in production would have been
    /// refused. Runs on a device signed into iCloud (DEBUG launch argument `-initializeCloudKitSchema`): uploads sample
    /// records into a throwaway store's zone and deletes them again; never touches the person's library.
    public static func initializeCloudKitSchema() throws -> String {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Property.self, Inspection.self, InspectionObservation.self, UserPreferences.self]) else {
            throw CocoaError(.coreData, userInfo: [NSLocalizedDescriptionKey: "the SwiftData schema has no Core Data model"])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-init-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        let container = NSPersistentCloudKitContainer(name: "SchemaInitialisation", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        defer {
            try? container.persistentStoreCoordinator.destroyPersistentStore(at: url, type: .sqlite)
            try? FileManager.default.removeItem(at: url)
        }
        try container.initializeCloudKitSchema(options: [])
        let entities = model.entities.compactMap(\.name).sorted().joined(separator: ", ")
        return "CloudKit development schema initialised for \(entities)"
    }
}

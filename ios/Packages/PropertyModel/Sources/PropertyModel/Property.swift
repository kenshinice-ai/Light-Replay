import CoreLocation
import Foundation
import SwiftData

/// Where a property sits in the buyer's process. Stored as a raw string so SwiftData stays simple.
public enum PropertyStatus: String, CaseIterable, Codable, Sendable {
    case toInspect
    case inspected
    case shortlisted
    case dropped

    public var displayName: String {
        switch self {
        case .toInspect: String(localized: "To inspect", bundle: .module)
        case .inspected: String(localized: "Inspected", bundle: .module)
        case .shortlisted: String(localized: "Shortlisted", bundle: .module)
        case .dropped: String(localized: "Dropped", bundle: .module)
        }
    }
}

/// How the property entered the app (ADR-0014 tier A: user-shared or manual).
public enum PropertySource: String, Codable, Sendable {
    case manual
    case shared
    case sample
}

/// The product object (ADR-0012). One home and everything the buyer records about it.
/// CloudKit mirroring (ADR-0017) requires every stored property to have a default and every relationship to be optional.
@Model
public final class Property {
    public var uuid: UUID = UUID()
    public var address: String = ""
    public var suburb: String?
    public var latitude: Double?
    public var longitude: Double?
    /// The address the coordinates were resolved for. When the address changes the pin is stale and not shown (R07).
    public var pinAddress: String?
    public var sourceRaw: String = PropertySource.manual.rawValue
    public var statusRaw: String = PropertyStatus.toInspect.rawValue
    public var createdAt: Date = Date()
    public var inspectionAt: Date?
    public var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \Inspection.property)
    public var inspections: [Inspection]? = []
    /// Notes written away from an inspection (from the property page or a Compare cell). Everything recorded on site
    /// hangs off an `Inspection` instead; a note from the desk is not a visit.
    @Relationship(deleteRule: .cascade, inverse: \InspectionObservation.property)
    public var standaloneNotes: [InspectionObservation]? = []

    public init(address: String, suburb: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
                source: PropertySource = .manual, status: PropertyStatus = .toInspect,
                inspectionAt: Date? = nil, createdAt: Date = Date()) {
        self.uuid = UUID()
        self.address = address
        self.suburb = suburb
        self.latitude = latitude
        self.longitude = longitude
        self.pinAddress = latitude != nil && longitude != nil ? address : nil
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.inspectionAt = inspectionAt
    }

    /// The inspection still in progress, if any.
    public var openInspection: Inspection? { (inspections ?? []).first { $0.isOpen && !$0.isDeleted } }

    public var allObservations: [InspectionObservation] {
        ((inspections ?? []).filter { !$0.isDeleted }.flatMap { $0.observations ?? [] } + (standaloneNotes ?? []))
            .filter { !$0.isDeleted }.sorted { $0.capturedAt > $1.capturedAt }
    }

    public var source: PropertySource {
        get { PropertySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var status: PropertyStatus {
        get { PropertyStatus(rawValue: statusRaw) ?? .toInspect }
        set { statusRaw = newValue.rawValue }
    }

    public var isSample: Bool { source == .sample }

    /// The pin, only while it still belongs to the current address. A stale pin is never used for the map or distance.
    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, !isPinStale else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// True when coordinates exist but were resolved for a different address.
    public var isPinStale: Bool {
        latitude != nil && longitude != nil && pinAddress != address
    }

    /// Stores a pin together with the address it was resolved for.
    public func setPin(latitude: Double, longitude: Double, suburb: String?, forAddress resolved: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.suburb = suburb
        self.pinAddress = resolved
    }

    /// First line of the address, for pins and rows.
    public var shortAddress: String {
        address.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? address
    }

    public func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let coordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: location)
    }
}

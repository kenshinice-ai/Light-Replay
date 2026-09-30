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
        case .toInspect: "To inspect"
        case .inspected: "Inspected"
        case .shortlisted: "Shortlisted"
        case .dropped: "Dropped"
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
@Model
public final class Property {
    public var uuid: UUID
    public var address: String
    public var suburb: String?
    public var latitude: Double?
    public var longitude: Double?
    public var sourceRaw: String
    public var statusRaw: String
    public var createdAt: Date
    public var inspectionAt: Date?
    public var notes: String?

    public init(address: String, suburb: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
                source: PropertySource = .manual, status: PropertyStatus = .toInspect,
                inspectionAt: Date? = nil, createdAt: Date = Date()) {
        self.uuid = UUID()
        self.address = address
        self.suburb = suburb
        self.latitude = latitude
        self.longitude = longitude
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.inspectionAt = inspectionAt
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

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// First line of the address, for pins and rows.
    public var shortAddress: String {
        address.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? address
    }

    public func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}

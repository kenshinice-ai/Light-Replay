import Foundation
import SwiftData

/// The dimensions a buyer can prioritise (Codex v2 §5 "Your Priorities"; docs/01 §8). Compare only shows these.
public enum PriorityDimension: String, CaseIterable, Codable, Sendable, Identifiable {
    case naturalLight
    case privacy
    case quiet
    case space
    case backyard
    case school
    case commute
    case renovationPotential
    case priceComfort

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .naturalLight: "Natural light"
        case .privacy: "Privacy"
        case .quiet: "Quiet"
        case .space: "Space"
        case .backyard: "Backyard"
        case .school: "School"
        case .commute: "Commute"
        case .renovationPotential: "Renovation potential"
        case .priceComfort: "Price comfort"
        }
    }

    public var systemImage: String {
        switch self {
        case .naturalLight: "sun.max"
        case .privacy: "eye.slash"
        case .quiet: "speaker.slash"
        case .space: "square.resize"
        case .backyard: "leaf"
        case .school: "graduationcap"
        case .commute: "tram"
        case .renovationPotential: "hammer"
        case .priceComfort: "dollarsign.circle"
        }
    }
}

/// One row per iCloud account (per install when sync is off). Everything here is the person's, editable and deletable (docs/11 §3, Moat 4 caveat).
@Model
public final class UserPreferences {
    public static let maximumPriorities = 5
    public static let defaultTargetHeightM = 1.15   // seated eye height, docs/04 §2

    public var displayName: String = ""
    /// Ordered, at most `maximumPriorities` entries of `PriorityDimension.rawValue`.
    public var priorityRaws: [String] = []
    public var targetHeightM: Double = UserPreferences.defaultTargetHeightM
    public var hapticsEnabled: Bool = true
    /// Viewpoint Lock tolerance in metres (docs/04 §4). Exposed under Advanced so the spike can test 0.10 / 0.15 / 0.25.
    public var viewpointToleranceM: Double = 0.15
    /// BCP 47 identifier for dictated notes, e.g. "en-AU" or "zh-Hans"; nil follows the phone's language.
    public var noteLanguage: String?
    /// The oldest row wins when two devices each created one before syncing (`PropertyStore.preferences`).
    public var createdAt: Date = Date()

    public init(displayName: String = "", priorities: [PriorityDimension] = [.naturalLight, .space, .privacy],
                targetHeightM: Double = UserPreferences.defaultTargetHeightM, hapticsEnabled: Bool = true,
                viewpointToleranceM: Double = 0.15) {
        self.displayName = displayName
        self.priorityRaws = priorities.map(\.rawValue)
        self.targetHeightM = targetHeightM
        self.hapticsEnabled = hapticsEnabled
        self.viewpointToleranceM = viewpointToleranceM
        self.noteLanguage = nil
        self.createdAt = Date()
    }

    /// The locale dictated notes are transcribed in.
    public var noteLocale: Locale {
        noteLanguage.map { Locale(identifier: $0) } ?? .current
    }

    public var priorities: [PriorityDimension] {
        get { priorityRaws.compactMap(PriorityDimension.init(rawValue:)) }
        set { priorityRaws = Array(newValue.prefix(Self.maximumPriorities)).map(\.rawValue) }
    }

    public func toggle(_ dimension: PriorityDimension) {
        var current = priorities
        if let index = current.firstIndex(of: dimension) {
            current.remove(at: index)
        } else if current.count < Self.maximumPriorities {
            current.append(dimension)
        }
        priorities = current
    }
}

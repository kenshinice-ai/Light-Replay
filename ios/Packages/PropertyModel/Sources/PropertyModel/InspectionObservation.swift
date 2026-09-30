import Foundation
import SwiftData

public enum ObservationKind: String, Codable, Sendable {
    case photo, voice, tag, light
}

/// Categories a note or photo can be about (docs/15 §2).
public enum ObservationCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case naturalLight, privacy, noise, space, condition, layout, outdoor, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .naturalLight: "Natural light"
        case .privacy: "Privacy"
        case .noise: "Noise"
        case .space: "Space"
        case .condition: "Condition"
        case .layout: "Layout"
        case .outdoor: "Outdoor"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .naturalLight: "sun.max"
        case .privacy: "eye.slash"
        case .noise: "speaker.wave.2"
        case .space: "square.resize"
        case .condition: "wrench.and.screwdriver"
        case .layout: "square.grid.2x2"
        case .outdoor: "leaf"
        case .other: "tag"
        }
    }
}

/// The three quick tags plus neutral (ADR-0015). `ask` also makes the observation a question.
public enum Sentiment: String, CaseIterable, Codable, Sendable, Identifiable {
    case like, concern, ask, neutral

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .like: "Like"
        case .concern: "Concern"
        case .ask: "Ask"
        case .neutral: "Note"
        }
    }

    public var systemImage: String {
        switch self {
        case .like: "hand.thumbsup"
        case .concern: "exclamationmark.triangle"
        case .ask: "questionmark.circle"
        case .neutral: "note.text"
        }
    }
}

/// External evidence levels (ADR-0013). Assigned by rules, never by a model.
public enum EvidenceLevel: String, Codable, Sendable {
    case verified, observedMeasured, observedNoted, strongIndication, indicative, unknown

    public var displayName: String {
        switch self {
        case .verified: "Verified"
        case .observedMeasured: "Observed · measured"
        case .observedNoted: "Observed · noted"
        case .strongIndication: "Strong indication"
        case .indicative: "Indicative"
        case .unknown: "Unknown"
        }
    }
}

public enum EvidenceSource: String, Codable, Sendable {
    case listing, userPhoto, userVoice, sensor, openData, model
}

/// A visit to a property. Observations hang off it; one open inspection per property at a time.
@Model
public final class Inspection {
    public var uuid: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var property: Property?
    @Relationship(deleteRule: .cascade, inverse: \InspectionObservation.inspection)
    public var observations: [InspectionObservation]

    public init(property: Property, startedAt: Date = Date()) {
        self.uuid = UUID()
        self.startedAt = startedAt
        self.property = property
        self.observations = []
    }

    public var isOpen: Bool { endedAt == nil }
}

/// One on-site record (docs/15 §2): a photo, a spoken note, a tag, or a light measurement. The concept is
/// "Observation"; the Swift name avoids clashing with the Observation module that  expands into.
@Model
public final class InspectionObservation {
    public var uuid: UUID
    public var kindRaw: String
    public var categoryRaw: String
    public var sentimentRaw: String
    public var levelRaw: String
    public var sourceRaw: String
    /// The buyer's words: transcript for voice, caption for photo.
    public var text: String?
    /// One-sentence model summary of a voice note (Indicative), kept apart from the transcript.
    public var summary: String?
    /// Relative path under the app's observation media folder.
    public var mediaPath: String?
    public var roomLabel: String?
    public var capturedAt: Date
    public var headingDeg: Double?
    public var headingAccuracyDeg: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var followUp: Bool
    /// True while category / sentiment / room came from the model and the buyer has not confirmed them.
    public var modelSuggested: Bool
    /// `scene_id` of the SceneRecord for `kind == .light`.
    public var sceneId: String?
    public var inspection: Inspection?

    public init(kind: ObservationKind, category: ObservationCategory = .other, sentiment: Sentiment = .neutral,
                source: EvidenceSource, text: String? = nil, roomLabel: String? = nil, capturedAt: Date = Date()) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue
        self.sentimentRaw = sentiment.rawValue
        self.levelRaw = InspectionObservation.level(for: kind, source: source).rawValue
        self.sourceRaw = source.rawValue
        self.text = text
        self.roomLabel = roomLabel
        self.capturedAt = capturedAt
        self.followUp = sentiment == .ask
        self.modelSuggested = false
    }

    /// Rule, not judgement (ADR-0013): what the buyer saw or said is Observed · noted; a passed measurement is
    /// Observed · measured; anything a model produced is Indicative.
    public static func level(for kind: ObservationKind, source: EvidenceSource) -> EvidenceLevel {
        switch (kind, source) {
        case (.light, .sensor): .observedMeasured
        case (_, .model): .indicative
        case (.photo, _), (.voice, _), (.tag, _): .observedNoted
        default: .unknown
        }
    }

    public var kind: ObservationKind { ObservationKind(rawValue: kindRaw) ?? .tag }
    public var category: ObservationCategory {
        get { ObservationCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    public var sentiment: Sentiment {
        get { Sentiment(rawValue: sentimentRaw) ?? .neutral }
        set { sentimentRaw = newValue.rawValue; if newValue == .ask { followUp = true } }
    }
    public var level: EvidenceLevel { EvidenceLevel(rawValue: levelRaw) ?? .unknown }
    public var source: EvidenceSource { EvidenceSource(rawValue: sourceRaw) ?? .userPhoto }

    /// What to show first: the buyer's own words, else the model summary, else the kind.
    public var headline: String {
        if let text, !text.isEmpty { return text }
        if let summary, !summary.isEmpty { return summary }
        switch kind {
        case .photo: return "Photo"
        case .voice: return "Voice note"
        case .tag: return sentiment.displayName
        case .light: return "Light measurement"
        }
    }
}

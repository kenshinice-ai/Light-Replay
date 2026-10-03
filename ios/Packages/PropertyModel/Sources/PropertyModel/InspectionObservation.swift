import Foundation
import SwiftData

public enum ObservationKind: String, Codable, Sendable {
    case photo, voice, tag, light
    /// Typed by the buyer, usually away from the home: a fact or a judgment the camera cannot catch (school zone,
    /// commute, how the price sits). Hangs off the property, not an inspection.
    case note
}

/// Categories a note or photo can be about (docs/15 §2).
public enum ObservationCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case naturalLight, privacy, noise, space, condition, layout, outdoor
    /// Things a buyer records about a home rather than at it (Lee, 2026-10-03): they give Compare's School,
    /// Commute and Price comfort rows a source.
    case school, commute, priceComfort
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .naturalLight: String(localized: "Natural light", bundle: .module)
        case .privacy: String(localized: "Privacy", bundle: .module)
        case .noise: String(localized: "Noise", bundle: .module)
        case .space: String(localized: "Space", bundle: .module)
        case .condition: String(localized: "Condition", bundle: .module)
        case .layout: String(localized: "Layout", bundle: .module)
        case .outdoor: String(localized: "Outdoor", bundle: .module)
        case .school: String(localized: "School", bundle: .module)
        case .commute: String(localized: "Commute", bundle: .module)
        case .priceComfort: String(localized: "Price comfort", bundle: .module)
        case .other: String(localized: "Other", bundle: .module)
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
        case .school: "graduationcap"
        case .commute: "tram"
        case .priceComfort: "dollarsign.circle"
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
        case .like: String(localized: "Like", bundle: .module)
        case .concern: String(localized: "Concern", bundle: .module)
        case .ask: String(localized: "Ask", bundle: .module)
        case .neutral: String(localized: "Note", bundle: .module)
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
        case .verified: String(localized: "Verified", bundle: .module)
        case .observedMeasured: String(localized: "Observed · measured", bundle: .module)
        case .observedNoted: String(localized: "Observed · noted", bundle: .module)
        case .strongIndication: String(localized: "Strong indication", bundle: .module)
        case .indicative: String(localized: "Indicative", bundle: .module)
        case .unknown: String(localized: "Unknown", bundle: .module)
        }
    }
}

public enum EvidenceSource: String, Codable, Sendable {
    case listing, userPhoto, userVoice, sensor, openData, model
    /// Typed by the buyer.
    case userText
}

/// A visit to a property. Observations hang off it; one open inspection per property at a time.
@Model
public final class Inspection {
    public var uuid: UUID = UUID()
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var property: Property?
    @Relationship(deleteRule: .cascade, inverse: \InspectionObservation.inspection)
    public var observations: [InspectionObservation]? = []

    /// Insert into a context before attaching to a property (`PropertyStore.openInspection`).
    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    public var isOpen: Bool { endedAt == nil }
}

/// One on-site record (docs/15 §2): a photo, a spoken note, a tag, or a light measurement. The concept is
/// "Observation"; the Swift name avoids clashing with the Observation module that  expands into.
@Model
public final class InspectionObservation {
    public var uuid: UUID = UUID()
    public var kindRaw: String = ObservationKind.tag.rawValue
    public var categoryRaw: String = ObservationCategory.other.rawValue
    public var sentimentRaw: String = Sentiment.neutral.rawValue
    public var levelRaw: String = EvidenceLevel.unknown.rawValue
    public var sourceRaw: String = EvidenceSource.userPhoto.rawValue
    /// The buyer's words: transcript for voice, caption for photo. The buyer may correct them.
    public var text: String?
    /// What `text` was before the buyer first corrected it (the raw transcript). Nil while `text` is untouched.
    public var originalText: String?
    /// One-sentence model summary of a voice note (Indicative), kept apart from the transcript.
    public var summary: String?
    /// The photo (JPEG). Kept by the store beside the row and mirrored to iCloud as an asset (ADR-0017), so a row and its
    /// photo are saved and deleted in one transaction.
    @Attribute(.externalStorage) public var photoData: Data?
    /// Legacy (before ADR-0017): relative path under Documents/observations. `LegacyFiles.migrate` moves it into `photoData`.
    public var mediaPath: String?
    public var roomLabel: String?
    public var capturedAt: Date = Date()
    public var headingDeg: Double?
    public var headingAccuracyDeg: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var followUp: Bool = false
    /// True while category / sentiment / room came from the model and the buyer has not confirmed them.
    public var modelSuggested: Bool = false
    /// `scene_id` of the SceneRecord for `kind == .light`.
    public var sceneId: String?
    /// The SceneRecord JSON for `kind == .light`, stored with the row (ADR-0017). Files on disk are export copies only.
    @Attribute(.externalStorage) public var sceneRecordData: Data?
    public var inspection: Inspection?
    /// The home a note written away from an inspection belongs to. Nil for everything recorded during one, which
    /// reaches its home through `inspection`.
    public var property: Property?

    public init(kind: ObservationKind, category: ObservationCategory = .other, sentiment: Sentiment = .neutral,
                source: EvidenceSource, text: String? = nil, roomLabel: String? = nil, capturedAt: Date = Date()) {
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
        case (.light, _): .unknown          // only the SceneRecord quality mapping can raise this (lightLevel below)
        case (_, .model): .indicative
        case (.photo, _), (.voice, _), (.tag, _), (.note, _): .observedNoted
        }
    }

    /// Rule for light measurements (ADR-0013, docs/15 §2): a passed R1/R2 record's stable-direct band is measured;
    /// its direction-sensitive band is indicative; anything else, including R0 or a blocked guard, stays unknown.
    /// Pass values only from a record `SceneRecordDocument` accepted: that is where the lights are worked out again
    /// from the evidence (QualityEvaluator), so a level written into a file is not taken at its word.
    public static func lightLevel(qualityLevel: String, falseValidGuard: String, bandState: String) -> EvidenceLevel {
        guard qualityLevel != "R0", falseValidGuard == "passed" else { return .unknown }
        switch bandState {
        case "direct": return .observedMeasured
        case "sensitive": return .indicative
        default: return .unknown
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

    /// Replaces the buyer's words, remembering the first version. Correcting a transcript does not change who said it,
    /// so source and level stay as they are (ADR-0013). Restoring the original clears the memory of the edit.
    public func correctText(to newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = text ?? ""
        guard trimmed != current else { return }
        if let original = originalText {
            if trimmed == original { originalText = nil }
        } else if !current.isEmpty {
            originalText = current
        }
        text = trimmed.isEmpty ? nil : trimmed
    }
    public var source: EvidenceSource { EvidenceSource(rawValue: sourceRaw) ?? .userPhoto }

    /// What to show first: the buyer's own words, else the model summary, else the kind.
    public var headline: String {
        if let text, !text.isEmpty { return text }
        if let summary, !summary.isEmpty { return summary }
        switch kind {
        case .photo: return String(localized: "Photo", bundle: .module)
        case .voice: return String(localized: "Voice note", bundle: .module)
        case .tag: return sentiment.displayName
        case .note: return String(localized: "Note", bundle: .module)
        case .light: return String(localized: "Light measurement", bundle: .module)
        }
    }

    /// The home this belongs to, whichever way it is attached.
    public var owner: Property? { inspection?.property ?? property }
}

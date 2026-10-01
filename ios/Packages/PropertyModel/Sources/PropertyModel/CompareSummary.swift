import Foundation

/// What the buyer's own records say about one priority at one property (UI/UX review U14). Counts and states only:
/// never a score, never a ranking (ADR-0005). Every "nothing" is named for what it is, because "not recorded",
/// "scanned but not calculated" and "the app cannot record this yet" are different things to do something about.
public struct CompareCell: Equatable, Sendable {
    public enum State: String, Sendable {
        /// The buyer recorded something about it on site.
        case noted
        /// Light only: a scan exists, sunlight has not been calculated.
        case scannedNotCalculated
        /// Light only: a measurement passed its quality checks.
        case measured
        /// It could have been recorded here and was not.
        case notRecorded
        /// Nothing in the app records this priority yet.
        case noSource
    }

    public let state: State
    public let likes: Int
    public let concerns: Int
    public let questions: Int
    public let notes: Int
    public let scans: Int

    /// The cell's one line.
    public var headline: String {
        switch state {
        case .noSource: "Not in the app yet"
        case .notRecorded: "Not recorded"
        case .measured: "Measured"
        case .scannedNotCalculated: "Scanned, sunlight not calculated"
        case .noted: tally ?? "Noted"
        }
    }

    /// The buyer's own tags, shown under a light state when there are any.
    public var detail: String? {
        switch state {
        case .measured, .scannedNotCalculated: tally
        default: nil
        }
    }

    /// "2 likes · 1 concern · 1 to confirm · 1 note", leaving out the zeros.
    public var tally: String? {
        var parts: [String] = []
        if likes > 0 { parts.append(likes == 1 ? "1 like" : "\(likes) likes") }
        if concerns > 0 { parts.append(concerns == 1 ? "1 concern" : "\(concerns) concerns") }
        if questions > 0 { parts.append("\(questions) to confirm") }
        if notes > 0 { parts.append(notes == 1 ? "1 note" : "\(notes) notes") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var hasEvidence: Bool { likes + concerns + questions + notes + scans > 0 }
}

public enum CompareSummary {
    /// The observation category that speaks to a priority; nil when no category does yet.
    public static func category(for dimension: PriorityDimension) -> ObservationCategory? {
        switch dimension {
        case .naturalLight: .naturalLight
        case .privacy: .privacy
        case .quiet: .noise
        case .space: .space
        case .backyard: .outdoor
        case .renovationPotential: .condition
        case .school, .commute, .priceComfort: nil
        }
    }

    /// The buyer's records behind a cell, newest first: tagged photos and notes, plus light scans for natural light.
    public static func observations(for dimension: PriorityDimension, at property: Property) -> [InspectionObservation] {
        guard let category = category(for: dimension) else { return [] }
        return property.allObservations.filter { observation in
            if observation.kind == .light { return dimension == .naturalLight }
            return observation.category == category
        }
    }

    public static func cell(for dimension: PriorityDimension, at property: Property) -> CompareCell {
        guard category(for: dimension) != nil else {
            return CompareCell(state: .noSource, likes: 0, concerns: 0, questions: 0, notes: 0, scans: 0)
        }
        let all = observations(for: dimension, at: property)
        let scans = all.filter { $0.kind == .light }
        let tagged = all.filter { $0.kind != .light }
        let likes = tagged.filter { $0.sentiment == .like }.count
        let concerns = tagged.filter { $0.sentiment == .concern }.count
        let questions = tagged.filter { $0.sentiment == .ask }.count
        let notes = tagged.count - likes - concerns - questions
        let state: CompareCell.State
        if scans.contains(where: { $0.level == .observedMeasured }) {
            state = .measured
        } else if !scans.isEmpty {
            state = .scannedNotCalculated
        } else if tagged.isEmpty {
            state = .notRecorded
        } else {
            state = .noted
        }
        return CompareCell(state: state, likes: likes, concerns: concerns, questions: questions, notes: notes, scans: scans.count)
    }
}

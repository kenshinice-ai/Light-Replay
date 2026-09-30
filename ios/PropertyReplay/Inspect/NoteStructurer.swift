import Foundation
import FoundationModels
import PropertyModel

/// Turns a transcript into a structured suggestion with the on-device model (ADR-0010: structure only, never
/// numbers, never facts the buyer did not say). Returns nil when the model is unavailable; the UI then asks.
enum NoteStructurer {
    @Generable(description: "A home buyer's spoken note during a property inspection, organised without adding facts.")
    struct Extraction {
        @Guide(description: "Which room the note is about, chosen only from the rooms listed in the prompt; null if unclear")
        var room: String?
        @Guide(description: "The topic of the note")
        var category: Category
        @Guide(description: "like if the buyer is positive, concern if worried, ask if they want to check or ask someone, neutral otherwise")
        var sentiment: Tone
        @Guide(description: "The note restated in one short sentence using only what the buyer said; no new facts, no numbers the buyer did not say")
        var summary: String
    }

    @Generable enum Category: String {
        case naturalLight, privacy, noise, space, condition, layout, outdoor, other
    }

    @Generable enum Tone: String {
        case like, concern, ask, neutral
    }

    struct Suggestion: Sendable {
        var room: String?
        var category: ObservationCategory
        var sentiment: Sentiment
        var summary: String
    }

    static var availabilityNote: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason): return "On-device model unavailable (\(reason)). Pick the category yourself."
        }
    }

    static func structure(transcript: String, rooms: [String]) async -> Suggestion? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You organise a home buyer's spoken notes taken while walking through a property for sale.
            Only restate what the buyer said. Never add facts, measurements, numbers, or advice.
            Rooms that exist at this property: \(rooms.joined(separator: ", ")).
            """)
        do {
            let response = try await session.respond(to: Prompt(transcript), generating: Extraction.self)
            let e = response.content
            return Suggestion(room: e.room.flatMap { rooms.contains($0) ? $0 : nil },
                              category: ObservationCategory(rawValue: e.category.rawValue) ?? .other,
                              sentiment: Sentiment(rawValue: e.sentiment.rawValue) ?? .neutral,
                              summary: e.summary)
        } catch {
            return nil
        }
    }
}

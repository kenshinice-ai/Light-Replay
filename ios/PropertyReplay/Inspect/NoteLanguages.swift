import Foundation
import Speech

/// The transcription languages this phone actually supports (English and Chinese variants), as SpeechTranscriber
/// reports them. Preferences store the exact identifier from this list; nothing is guessed from a prefix.
enum NoteLanguages {
    struct Option: Identifiable, Sendable, Equatable {
        let id: String        // exact Locale.identifier from SpeechTranscriber.supportedLocales
        let name: String
    }

    static func available() async -> [Option] {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = supported.filter { ["en", "zh"].contains($0.language.languageCode?.identifier ?? "") }
        let options = wanted.map { locale in
            Option(id: locale.identifier, name: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
        }
        // en-AU first, then the rest of English, then Chinese, each alphabetical.
        return options.sorted { a, b in
            let rank = { (o: Option) -> Int in o.id.hasPrefix("en_AU") || o.id.hasPrefix("en-AU") ? 0 : (o.id.hasPrefix("en") ? 1 : 2) }
            return rank(a) != rank(b) ? rank(a) < rank(b) : a.name < b.name
        }
    }

    /// The supported Locale object to hand to SpeechTranscriber for a stored identifier (or the phone's language).
    static func resolve(_ identifier: String?) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let target = identifier.map { Locale(identifier: $0) } ?? Locale.current
        if let exact = supported.first(where: { $0.identifier == target.identifier }) { return exact }
        let language = target.language.languageCode?.identifier
        let script = target.language.script?.identifier
        let region = target.region?.identifier
        let sameLanguage = supported.filter { $0.language.languageCode?.identifier == language }
        if let byScript = sameLanguage.first(where: { script != nil && $0.language.script?.identifier == script }) { return byScript }
        if let byRegion = sameLanguage.first(where: { region != nil && $0.region?.identifier == region }) { return byRegion }
        return sameLanguage.first
    }
}

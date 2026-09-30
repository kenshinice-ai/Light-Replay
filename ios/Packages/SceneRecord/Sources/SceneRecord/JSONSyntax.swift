import Foundation

// A lexical preflight prevents duplicate object keys (including escaped aliases)
// and excessive nesting. JSONDecoder performs the actual value decoding.
internal struct JSONSyntax {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func check() throws {
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw invalid("trailing JSON content") }
    }

    private func invalid(_ reason: String) -> SceneRecordValidationError {
        SceneRecordValidationError("$@\(index)", reason)
    }

    private mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count && bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func string() throws -> String {
        whitespace()
        let start = index
        guard consume(34) else { throw invalid("expected JSON string") }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            }
            if byte == 92 {
                guard index < bytes.count else { throw invalid("unterminated escape") }
                index += 1
            }
        }
        throw invalid("unterminated string")
    }

    private mutating func value(depth: Int) throws {
        guard depth <= 128 else { throw invalid("JSON nesting exceeds 128") }
        whitespace()
        guard index < bytes.count else { throw invalid("missing JSON value") }
        if bytes[index] == 123 {
            index += 1
            if consume(125) { return }
            var keys = Set<String>()
            repeat {
                let key = try string()
                guard keys.insert(key).inserted else { throw invalid("duplicate JSON key \(key)") }
                guard consume(58) else { throw invalid("expected colon") }
                try value(depth: depth + 1)
                if consume(125) { return }
                guard consume(44) else { throw invalid("expected comma") }
            } while true
        } else if bytes[index] == 91 {
            index += 1
            if consume(93) { return }
            repeat {
                try value(depth: depth + 1)
                if consume(93) { return }
                guard consume(44) else { throw invalid("expected comma") }
            } while true
        } else if bytes[index] == 34 {
            _ = try string()
        } else {
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard start != index else { throw invalid("missing JSON value") }
        }
    }
}

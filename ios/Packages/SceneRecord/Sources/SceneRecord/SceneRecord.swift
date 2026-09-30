import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSON numbers must be finite")
            }
            self = .number(value)
        } else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "JSON numbers must be finite"))
            }
            try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct SceneRecordValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let path: String
    public let reason: String
    public var description: String { "\(path): \(reason)" }

    internal init(_ path: String, _ reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct SceneRecordDocument: Sendable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) throws {
        try SceneValidator.validate(fields)
        self.fields = fields
    }

    public init(data: Data) throws {
        // JSONDecoder alone accepts duplicate keys; reject ambiguous guard/source data first.
        var syntax = JSONSyntax(data: data)
        try syntax.check()
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let fields) = value else {
            throw SceneRecordValidationError("$", "expected object")
        }
        try self.init(fields: fields)
    }

    public func encoded(prettyPrinted: Bool = true) throws -> Data {
        try SceneValidator.validate(fields)
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(fields))
    }
}

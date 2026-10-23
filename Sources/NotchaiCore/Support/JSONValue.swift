import Foundation

/// Beliebiges JSON. Werkzeug-Eingaben der Agenten haben kein festes Schema und werden so unverändert
/// durchgereicht (etwa die Fragen von `AskUserQuestion` zurück an Claude Code).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Wert unter `key`, falls dies ein Objekt ist.
    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    public var stringValue: String? {
        if case .string(let s) = self { s } else { nil }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { b } else { nil }
    }

    public var numberValue: Double? {
        if case .number(let n) = self { n } else { nil }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { a } else { nil }
    }

    /// Einzeiliger JSON-Text ohne `\/`; die Agenten lesen ihn als ein Dokument.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

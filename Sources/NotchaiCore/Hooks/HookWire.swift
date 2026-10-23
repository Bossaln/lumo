import Foundation

/// Zeilenformat zwischen `notchai-hook` und App: ein JSON-Dokument pro Zeile, Datum als ISO-8601.
/// JSON maskiert Zeilenumbrüche in Texten, deshalb ist `\n` immer das Zeilenende.
public enum HookWire {
    public static func encodeLine<T: Encodable>(_ v: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(v)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decodeLine<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var line = data
        while line.last == UInt8(ascii: "\n") || line.last == UInt8(ascii: "\r") { line.removeLast() }
        return try decoder.decode(T.self, from: line)
    }
}

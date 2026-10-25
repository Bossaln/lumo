import Foundation

/// Farbe mit Kanälen von 0 bis 1.
public struct RGB: Equatable, Sendable {
    public let r, g, b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum ColorHex {
    /// Liest "#RRGGBB" oder "RRGGBB" (Groß-/Kleinschreibung egal).
    public static func parse(_ hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isASCII), let value = UInt32(s, radix: 16) else { return nil }
        return RGB(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    /// Gibt "#RRGGBB" in Großbuchstaben aus.
    public static func format(_ rgb: RGB) -> String {
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.r), byte(rgb.g), byte(rgb.b))
    }
}

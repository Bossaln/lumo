import Foundation

/// Leuchtfarbe aus den Pixeln eines (kleinen) Covers, z. B. einer 24×24-Bitmap.
public enum ArtworkColor {
    /// Mindestanteil kräftiger Farbe im Bild; darunter gilt das Cover als grau.
    static let minimumVividness = 0.01
    /// Auf diese Helligkeit wird ein dunkles Ergebnis angehoben, damit das Leuchten sichtbar bleibt.
    static let minimumBrightness = 0.9

    /// Gewichteter Mittelwert: Kräftige Farben zählen viel, graue, fast schwarze und durchsichtige Pixel nicht.
    /// `rgba` hat je Pixel vier Bytes. `nil`, wenn das Bild leer oder (fast) farblos ist.
    public static func glow(rgba: [UInt8], width: Int, height: Int) -> RGB? {
        let pixels = width * height
        guard pixels > 0, rgba.count == pixels * 4 else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            guard rgba[i + 3] >= 128 else { continue }
            let pr = Double(rgba[i]) / 255, pg = Double(rgba[i + 1]) / 255, pb = Double(rgba[i + 2]) / 255
            let value = max(pr, pg, pb)
            guard value >= 0.12 else { continue }
            let saturation = (value - min(pr, pg, pb)) / value
            guard saturation >= 0.15 else { continue }
            let weight = saturation * saturation * value
            r += pr * weight
            g += pg * weight
            b += pb * weight
            total += weight
        }
        guard total / Double(pixels) >= minimumVividness else { return nil }
        let average = (r / total, g / total, b / total)
        let scale = max(1, minimumBrightness / max(average.0, average.1, average.2))
        return RGB(r: min(1, average.0 * scale), g: min(1, average.1 * scale), b: min(1, average.2 * scale))
    }
}

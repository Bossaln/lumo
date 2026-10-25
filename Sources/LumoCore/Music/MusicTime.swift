import Foundation

/// Spielzeiten wie im Player: „1:05“, ab einer Stunde „1:02:05“.
public enum MusicTime {
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Restzeit mit echtem Minuszeichen, z. B. „−2:10“.
    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        "\u{2212}" + format(duration - position)
    }
}

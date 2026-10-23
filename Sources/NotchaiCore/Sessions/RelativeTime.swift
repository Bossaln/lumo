import Foundation

/// Kurze Zeitangabe rechts in der Session-Zeile.
public enum RelativeTime {
    public static func short(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "jetzt"
        case ..<3600: return "vor \(seconds / 60) min"
        case ..<86400: return "vor \(seconds / 3600) h"
        default: return "vor \(seconds / 86400) T"
        }
    }
}

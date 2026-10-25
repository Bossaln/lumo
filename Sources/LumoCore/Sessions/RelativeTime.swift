import Foundation

/// Kurze Zeitangabe rechts in der Session-Zeile.
public enum RelativeTime {
    public static func short(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return L("jetzt")
        case ..<3600: return L("vor {0} min", seconds / 60)
        case ..<86400: return L("vor {0} h", seconds / 3600)
        default: return L("vor {0} T", seconds / 86400)
        }
    }
}

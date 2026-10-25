import Foundation

/// Ein Zeitfenster des Abo-Limits: wie viel davon verbraucht ist und wann es sich zurücksetzt.
public struct UsageWindow: Equatable, Sendable {
    /// 0…100
    public var usedPercent: Double
    /// Länge des Fensters (Codex: 300 = fünf Stunden, 10 080 = eine Woche).
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

/// Nutzungslimits des Abos, wie Codex sie in `token_count` mitschreibt (`rate_limits`). Claude Code gibt sie nur an
/// seine Statuszeile weiter, nicht an Hooks oder Transkripte (`docs/hooks.md`).
public struct UsageLimits: Equatable, Sendable {
    /// Das kürzere Fenster (meist fünf Stunden).
    public var primary: UsageWindow?
    /// Das längere Fenster (meist eine Woche).
    public var secondary: UsageWindow?
    /// `plus`, `pro` …
    public var plan: String?

    public init(primary: UsageWindow? = nil, secondary: UsageWindow? = nil, plan: String? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.plan = plan
    }

    /// Kennung der allgemeinen Codex-Limits; andere (`limit_id` je Modell) gehören nicht zur Session.
    static let codexLimitId = "codex"

    /// Liest `rate_limits` eines Codex-Rollouts. Neuere Versionen schreiben `resets_at` (Unix-Sekunden), ältere
    /// `resets_in_seconds` ab dem Zeitstempel der Zeile. Ohne Fenster: `nil`.
    init?(codex value: JSONValue?, at date: Date?) {
        guard let value, value.objectValue != nil else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let w = value[key], let used = w["used_percent"]?.numberValue else { return nil }
            let resets: Date? = if let at = w["resets_at"]?.numberValue {
                Date(timeIntervalSince1970: at)
            } else if let seconds = w["resets_in_seconds"]?.numberValue, let date {
                date.addingTimeInterval(seconds)
            } else {
                nil
            }
            return UsageWindow(usedPercent: used, windowMinutes: w["window_minutes"]?.intValue, resetsAt: resets)
        }
        let primary = window("primary"), secondary = window("secondary")
        guard primary != nil || secondary != nil else { return nil }
        self.init(primary: primary, secondary: secondary, plan: value["plan_type"]?.stringValue)
    }
}

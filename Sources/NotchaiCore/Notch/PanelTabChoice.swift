/// Welcher Reiter beim Aufklappen erscheint (Einstellungen › Notch).
public enum PanelOpenBehavior: String, Codable, Equatable, Sendable, CaseIterable {
    /// Wo gerade etwas passiert: Anfrage eines Agenten, sonst laufende Musik, sonst arbeitende Sessions.
    case activity
    /// Der zuletzt angeklickte Reiter.
    case lastUsed
}

/// Was gerade los ist, aus Sicht der Notch.
public struct NotchActivity: Equatable, Sendable {
    /// Claude Code oder Codex wartet auf eine Freigabe oder Antwort.
    public var ownerAwaited: Bool
    public var musicPlaying: Bool
    public var sessionsRunning: Bool

    public init(ownerAwaited: Bool, musicPlaying: Bool, sessionsRunning: Bool) {
        self.ownerAwaited = ownerAwaited
        self.musicPlaying = musicPlaying
        self.sessionsRunning = sessionsRunning
    }
}

public enum PanelTabChoice {
    /// Eine Anfrage geht vor, dann Musik (auch vor arbeitenden Agenten), dann Sessions, sonst der letzte Reiter.
    public static func tab(behavior: PanelOpenBehavior, lastTab: PanelTab, activity: NotchActivity) -> PanelTab {
        guard behavior == .activity else { return lastTab }
        if activity.ownerAwaited { return .sessions }
        if activity.musicPlaying { return .music }
        if activity.sessionsRunning { return .sessions }
        return lastTab
    }
}

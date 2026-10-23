import NotchaiCore

/// Beispiel-Inhalte für die Test-Signale (Einstellungen › Entwickler, „In der Notch ausprobieren“). Jeder Aufruf ist ein neues Signal mit eigener ID.
enum SignalDemo {
    /// Vorschau der gewählten Signalform aus Einrichtung und Einstellungen.
    static var preview: SignalContent {
        SignalContent(agent: .claude, title: L("notchai · Vorschau"), subtitle: L("So meldet sich Claude Code:"),
                      detail: "npm test", kind: .permission)
    }

    static var permission: SignalContent {
        SignalContent(agent: .claude, title: "notchai · Claude", subtitle: L("Möchte ausführen:"),
                      detail: "npm install", kind: .permission)
    }

    static var question: SignalContent {
        SignalContent(agent: .codex, title: "notchai · Codex", subtitle: L("Welche Farbe soll der Knopf bekommen?"),
                      kind: .question(options: [L("Rot"), L("Blau"), L("Grün")]))
    }

    static var done: SignalContent {
        SignalContent(agent: .claude, title: "notchai · Claude", subtitle: L("Fertig: alle Tests sind grün"),
                      kind: .done)
    }

    static var error: SignalContent {
        SignalContent(agent: .codex, title: "notchai · Codex", subtitle: L("Build fehlgeschlagen:"),
                      detail: "cannot find 'foo' in scope", kind: .error)
    }
}

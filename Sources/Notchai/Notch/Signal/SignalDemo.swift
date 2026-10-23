import NotchaiCore

/// Beispiel-Inhalte für die Test-Signale im Entwickler-Menü. Jeder Aufruf ist ein neues Signal mit eigener ID.
enum SignalDemo {
    static var permission: SignalContent {
        SignalContent(agent: .claude, title: "notchai · Claude", subtitle: "Möchte ausführen:",
                      detail: "npm install", kind: .permission)
    }

    static var question: SignalContent {
        SignalContent(agent: .codex, title: "notchai · Codex", subtitle: "Welche Farbe soll der Knopf bekommen?",
                      kind: .question(options: ["Rot", "Blau", "Grün"]))
    }

    static var done: SignalContent {
        SignalContent(agent: .claude, title: "notchai · Claude", subtitle: "Fertig: alle Tests sind grün",
                      kind: .done)
    }

    static var error: SignalContent {
        SignalContent(agent: .codex, title: "notchai · Codex", subtitle: "Build fehlgeschlagen:",
                      detail: "cannot find 'foo' in scope", kind: .error)
    }
}

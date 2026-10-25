import Foundation

/// Welcher Agent ein Signal auslöst. Auch der Agent einer Session (`AgentKind`).
public enum SignalAgent: String, CaseIterable, Codable, Equatable, Sendable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

/// Anlass eines Signals.
public enum SignalKind: Equatable, Sendable {
    case permission
    case question(options: [String])
    case done
    case error

    /// „Fertig“ verschwindet von selbst, alles andere bleibt bis zur Entscheidung.
    public var autoDismissDelay: Duration? {
        self == .done ? .seconds(4) : nil
    }

    /// Wartet der Agent auf den Besitzer? Nur dann leuchtet der Menüleisten-Punkt.
    public var isAwaitingOwner: Bool {
        switch self {
        case .permission, .question: true
        case .done, .error: false
        }
    }

    /// Nur bei Fragen gibt es ein Antwortfeld.
    public var acceptsText: Bool {
        if case .question = self { true } else { false }
    }

    /// Höchstens vier Auswahl-Knöpfe passen in Banner und Kasten.
    public var visibleOptions: [String] {
        if case .question(let options) = self { Array(options.prefix(4)) } else { [] }
    }

    /// Kurzer Hinweis rechts in der Island.
    public var islandPrompt: String {
        switch self {
        case .permission: L("Erlauben?")
        case .question: L("Frage")
        case .done: L("Fertig")
        case .error: L("Fehler")
        }
    }

    /// Passt die Entscheidung zum Anlass? Schließen geht immer, sonst nur Erlauben/Ablehnen bei Freigaben
    /// und Antworten bei Fragen.
    public func permits(_ action: SignalAction) -> Bool {
        switch (self, action) {
        case (_, .dismiss), (.permission, .allow), (.permission, .deny), (.question, .answer): true
        default: false
        }
    }
}

/// Inhalt eines Notch-Signals: eine echte Anfrage oder ein Test-Signal von der Entwickler-Seite der Einstellungen.
public struct SignalContent: Equatable, Sendable, Identifiable {
    /// Wem eine Entscheidung gilt. Bei Anfragen die ID der Hook-Anfrage; sonst ist jedes Signal ein neues.
    public var id: UUID
    public var agent: SignalAgent
    public var title: String
    public var subtitle: String
    public var detail: String?
    public var kind: SignalKind
    /// Bei mehreren Fragen: „1/2“. Steht für sich und wird nie gekürzt.
    public var progress: String?
    /// Frage mit Mehrfachauswahl: Optionen schalten um, „Senden“ schickt die Auswahl.
    public var multiSelect = false
    /// Die Kurzfassung (`detail`) zeigt nicht alles: der ganze Befehl und ein Hinweis darauf („+1 Zeile“).
    public var fullDetail: String?
    public var detailNote: String?

    public init(id: UUID = UUID(), agent: SignalAgent, title: String, subtitle: String, detail: String? = nil,
                kind: SignalKind, progress: String? = nil, multiSelect: Bool = false, fullDetail: String? = nil,
                detailNote: String? = nil) {
        self.id = id
        self.agent = agent
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.kind = kind
        self.progress = progress
        self.multiSelect = multiSelect
        self.fullDetail = fullDetail
        self.detailNote = detailNote
    }

    /// Antwort einer Mehrfachauswahl: die gewählten Optionen in ihrer Reihenfolge, dahinter getippter Text.
    public func multiSelectAnswer(selected: Set<String>, typed: String) -> SignalAction? {
        let options = kind.visibleOptions.filter(selected.contains)
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = options + (text.isEmpty ? [] : [text])
        return parts.isEmpty ? nil : .answer(parts.joined(separator: ", "))
    }
}

/// Was der Besitzer im Signal entschieden hat.
public enum SignalAction: Equatable, Sendable {
    case allow, deny, answer(String), dismiss

    /// Getippte Antwort ohne Leerraum am Rand; leere Eingaben zählen nicht.
    public static func typedAnswer(_ text: String) -> SignalAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : .answer(trimmed)
    }
}

extension AppSettings {
    /// Eingestellte Farbe des Agenten als "#RRGGBB".
    public func colorHex(for agent: SignalAgent) -> String {
        switch agent {
        case .claude: claudeColorHex
        case .codex: codexColorHex
        }
    }
}

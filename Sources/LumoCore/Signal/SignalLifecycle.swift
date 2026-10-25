import Foundation

/// Das gerade angezeigte Signal mit seiner Frist und dem Entwurf einer getippten Antwort.
public struct ActiveSignal: Equatable, Sendable {
    public let content: SignalContent
    /// Ab hier schließt sich das Signal selbst („Fertig“); `nil` heißt: bleibt bis zur Entscheidung.
    public let dismissAt: ContinuousClock.Instant?
    /// Getippte, noch nicht abgeschickte Antwort.
    public fileprivate(set) var draft = ""
    /// Gewählte Optionen einer Mehrfachauswahl.
    public fileprivate(set) var selection: Set<String> = []

    public var id: UUID { content.id }
}

/// Lebenszyklus des einen Signals in der Notch: zeigen, ersetzen, schließen, von selbst schließen.
/// Alles, was von außen ein Signal meint (Klick, Timer, Entwurf), nennt dessen ID. Passt sie nicht mehr
/// zum angezeigten Signal, passiert nichts – so landet eine Entscheidung nie beim falschen Signal.
public struct SignalLifecycle: Equatable, Sendable {
    public private(set) var active: ActiveSignal?

    public init() {}

    /// Zeigt `content` und gibt das dadurch ersetzte Signal zurück. Kommt dieselbe ID erneut (dieselbe
    /// Anfrage), gelten Inhalt und Frist neu, Entwurf und Auswahl bleiben – außer die Anfrage ist bei der
    /// nächsten ihrer Fragen (`progress`).
    @discardableResult
    public mutating func raise(_ content: SignalContent, now: ContinuousClock.Instant) -> ActiveSignal? {
        let previous = active
        let sameSignal = previous?.id == content.id
        var next = ActiveSignal(content: content, dismissAt: content.kind.autoDismissDelay.map { now + $0 })
        if sameSignal, let previous, previous.content.progress == content.progress {
            next.draft = previous.draft
            next.selection = previous.selection
        }
        active = next
        return sameSignal ? nil : previous
    }

    /// Schließt das Signal `id`, falls es noch angezeigt wird, und gibt es zurück.
    @discardableResult
    public mutating func clear(_ id: UUID) -> ActiveSignal? {
        guard active?.id == id else { return nil }
        return clearActive()
    }

    /// Schließt, was gerade angezeigt wird (Einstellungen › Entwickler › „Signal schließen“).
    @discardableResult
    public mutating func clearActive() -> ActiveSignal? {
        defer { active = nil }
        return active
    }

    /// Schließt das angezeigte Signal, wenn seine Frist bis `now` abgelaufen ist.
    @discardableResult
    public mutating func expire(now: ContinuousClock.Instant) -> ActiveSignal? {
        guard let deadline = active?.dismissAt, now >= deadline else { return nil }
        return clearActive()
    }

    /// Darf `action` an das Signal `id` gehen? Nur, solange es angezeigt wird und die Aktion zum Anlass passt.
    public func accepts(_ action: SignalAction, for id: UUID) -> Bool {
        guard let active, active.id == id else { return false }
        return active.content.kind.permits(action)
    }

    /// Entwurf des Signals `id`; leer, wenn es nicht (mehr) angezeigt wird.
    public func draft(for id: UUID) -> String {
        active?.id == id ? active?.draft ?? "" : ""
    }

    /// Gewählte Optionen des Signals `id`; leer, wenn es nicht (mehr) angezeigt wird.
    public func selection(for id: UUID) -> Set<String> {
        active?.id == id ? active?.selection ?? [] : []
    }

    /// Wählt eine Option einer Mehrfachauswahl an oder ab.
    public mutating func toggle(_ option: String, for id: UUID) {
        guard active?.id == id, active?.content.multiSelect == true else { return }
        if active?.selection.contains(option) == true { active?.selection.remove(option) } else { active?.selection.insert(option) }
    }

    /// Merkt sich den Entwurf; für ein nicht (mehr) angezeigtes Signal passiert nichts.
    public mutating func setDraft(_ text: String, for id: UUID) {
        guard active?.id == id else { return }
        active?.draft = text
    }
}

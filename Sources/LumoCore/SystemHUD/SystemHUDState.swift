import Foundation

/// Welche Systemanzeige die Notch gerade zeigt. Kurze Anzeigen (Lautstärke, Fokus …) stehen für ein paar Sekunden
/// und ersetzen einander; eine bleibende Anzeige (laufender Timer, klingelnder Wecker) kommt danach wieder zum
/// Vorschein und bleibt, bis sie ausdrücklich endet.
public struct SystemHUDState: Equatable, Sendable {
    public private(set) var transient: SystemIndicator?
    /// Ab hier verschwindet die kurze Anzeige.
    public private(set) var hideAt: ContinuousClock.Instant?
    /// Bleibende Anzeigen nach Art; zeigt die wichtigste (Wecker vor Timer).
    public private(set) var sticky: [SystemIndicatorKind: SystemIndicator] = [:]

    public init() {}

    /// Was zu sehen ist: die kurze Anzeige vor der bleibenden.
    public var visible: SystemIndicator? {
        transient ?? stickyIndicator
    }

    public var stickyIndicator: SystemIndicator? {
        sticky[.alarm] ?? sticky[.timer] ?? sticky.values.first
    }

    /// Zeigt `indicator`; kurze Anzeigen bleiben `hold` lang stehen (bei jeder Änderung von vorn).
    public mutating func show(_ indicator: SystemIndicator, now: ContinuousClock.Instant, hold: Duration) {
        if indicator.sticky {
            sticky[indicator.kind] = indicator
            // Dieselbe Art kurz und bleibend zugleich gibt es nicht: Der laufende Timer löst den kurzen Hinweis ab.
            if transient?.kind == indicator.kind { transient = nil; hideAt = nil }
        } else {
            transient = indicator
            hideAt = now + hold
        }
    }

    /// Beendet eine bleibende Anzeige (Timer gestoppt, Wecker aus).
    public mutating func endSticky(_ kind: SystemIndicatorKind) {
        sticky[kind] = nil
    }

    /// Beendet die kurze Anzeige (Zeiger kommt, Signal kommt).
    public mutating func endTransient() {
        transient = nil
        hideAt = nil
    }

    /// Lässt die kurze Anzeige verschwinden, wenn ihre Zeit um ist; `true`, wenn sich etwas geändert hat.
    @discardableResult
    public mutating func expire(now: ContinuousClock.Instant) -> Bool {
        guard let hideAt, now >= hideAt else { return false }
        endTransient()
        return true
    }
}

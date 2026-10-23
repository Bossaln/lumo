/// Reiter des aufgeklappten Panels. Die Einstellungen öffnen sich über die Menüleiste.
public enum PanelTab: String, CaseIterable, Sendable {
    case music, sessions, office, shelf

    public var title: String {
        switch self {
        case .music: L("Musik")
        case .sessions: L("Sessions")
        case .office: L("Büro")
        case .shelf: L("Ablage")
        }
    }
}

public enum NotchMode: Equatable, Sendable {
    case idle
    case signal(SignalStyle)
    case panel(PanelTab)
}

public enum NotchEvent: Equatable, Sendable {
    case hoverBegan, hoverEnded, signalRaised, signalCleared, islandClicked
    case tabSelected(PanelTab)
    /// Das Antwortfeld im Signal hat die Tastatur bekommen bzw. wieder abgegeben
    /// (Absenden, Escape, Klick in eine andere App, Ende des Signals).
    case editingBegan, editingEnded
    /// Dateien werden über die Notch gezogen bzw. losgelassen (abgelegt oder abgebrochen).
    case fileDragEntered, fileDragEnded
}

/// Reiner Zustandsautomat der Notch. Nicht genannte Kombinationen lassen den Modus unverändert.
public struct NotchState: Equatable, Sendable {
    public var mode: NotchMode = .idle
    public var hasPendingSignal = false
    public var lastTab: PanelTab = .sessions
    /// Reiter für das nächste Aufklappen (`PanelTabChoice`); ohne ihn öffnet `lastTab`. Gilt einmal.
    public var openTab: PanelTab?
    /// Wird im Signal gerade eine Antwort getippt? Dann klappt es beim Verlassen nicht zu.
    public private(set) var isEditing = false
    /// Gerade werden Dateien über die Notch gezogen: Die Ablage zeigt ihre Ziele (AirDrop, Ablage).
    public private(set) var isReceivingFiles = false
    /// Der Zeiger ging, während getippt wurde; zugeklappt wird, sobald das Tippen endet.
    private var collapseAfterEditing = false

    public init() {}

    public mutating func apply(_ event: NotchEvent, style: SignalStyle) {
        switch event {
        case .hoverBegan:
            collapseAfterEditing = false
            switch mode {
            case .idle:
                mode = .panel(openTab ?? lastTab)
                openTab = nil
            case .signal(.island): mode = .signal(.banner)
            case .signal, .panel: break
            }
        case .hoverEnded:
            switch mode {
            case .panel:
                mode = hasPendingSignal ? .signal(style) : .idle
                isReceivingFiles = false
            // Sonst ginge die halb getippte Antwort verloren und die Tastatur an die vordere App.
            case .signal where isEditing: collapseAfterEditing = true
            case .signal: mode = .signal(style)
            case .idle: break
            }
        case .signalRaised:
            endEditing(style: style)
            hasPendingSignal = true
            if mode == .idle { mode = .signal(style) }
        case .signalCleared:
            endEditing(style: style)
            hasPendingSignal = false
            if case .signal = mode { mode = .idle }
        case .islandClicked:
            if mode == .signal(.island) { mode = .signal(.banner) }
        case .tabSelected(let tab):
            if case .panel = mode {
                mode = .panel(tab)
                lastTab = tab
            }
        case .editingBegan:
            if case .signal = mode { isEditing = true }
        case .editingEnded:
            endEditing(style: style)
        case .fileDragEntered:
            // Eine halb getippte Antwort geht vor; die Ablage öffnet sich nicht darüber.
            guard !isEditing else { break }
            collapseAfterEditing = false
            mode = .panel(.shelf)
            isReceivingFiles = true
        case .fileDragEnded:
            // Offen bleibt die Ablage, bis der Zeiger sie verlässt (`hoverEnded`).
            isReceivingFiles = false
        }
    }

    /// Beendet das Tippen und holt ein dabei aufgeschobenes Zuklappen nach.
    private mutating func endEditing(style: SignalStyle) {
        if collapseAfterEditing, case .signal = mode { mode = .signal(style) }
        isEditing = false
        collapseAfterEditing = false
    }
}

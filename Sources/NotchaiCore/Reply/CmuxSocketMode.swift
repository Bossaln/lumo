import Foundation

/// Wen cmux an seinen Steuer-Socket lässt (cmux › Einstellungen › Automatisierung). notchai läuft nicht in cmux:
/// Mit „Nur cmux-Prozesse“ (Standard) weist cmux `cmux paste` und `cmux select-workspace` von notchai ab.
/// `cmux socket-status --json` verrät den Modus, ohne sich mit dem Socket zu verbinden.
public enum CmuxSocketMode: String, Equatable, Sendable {
    case cmuxOnly, automation, password, allowAll, off

    /// Modus aus der Ausgabe von `cmux socket-status --json` (`effective_mode`); `nil`, wenn unlesbar.
    public static func parse(statusJSON: String) -> CmuxSocketMode? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(statusJSON.utf8)),
              let mode = value["effective_mode"]?.stringValue ?? value["configured_mode"]?.stringValue else { return nil }
        return CmuxSocketMode(rawValue: mode)
    }

    /// Darf ein Programm außerhalb von cmux Befehle schicken? Im Passwortmodus liest `cmux` das gespeicherte
    /// Passwort selbst.
    public var allowsExternalClients: Bool {
        switch self {
        case .automation, .password, .allowAll: true
        case .cmuxOnly, .off: false
        }
    }

    /// Meldungen von cmux, wenn es einen Prozess von außen abweist („Broken pipe“ bei `paste`).
    public static func isAccessDenied(_ output: String) -> Bool {
        ["Access denied", "Zugriff verweigert", "only processes started", "Broken pipe", "errno 32"]
            .contains { output.localizedCaseInsensitiveContains($0) }
    }
}

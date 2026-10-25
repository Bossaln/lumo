/// Feder für die Formwechsel der Notch. Beim Aufklappen schwingt sie mit etwas „Gummi“ wie die Dynamic Island
/// minimal über ihr Ziel hinaus; `bounce` kommt aus den Einstellungen (0 = ruhig). Beim Zuklappen läuft sie
/// ohne Überschwingen weich aus, sonst rutschte die Form kurz unter die Hardware-Notch.
public struct NotchSpring: Equatable, Sendable {
    /// Dauer eines Schwingers in Sekunden (SwiftUI `spring(response:)`).
    public let response: Double
    /// 1 = kein Überschwingen; je kleiner, desto mehr Gummi.
    public let dampingFraction: Double
    /// Zuklappen: kritisch gedämpft, langer weicher Auslauf.
    public let collapseResponse: Double = 0.42
    public let collapseDampingFraction: Double = 1

    public init(bounce: Double) {
        let b = min(max(bounce, 0), 1)
        response = 0.36 + 0.06 * b
        dampingFraction = 0.86 - 0.3 * b
    }
}

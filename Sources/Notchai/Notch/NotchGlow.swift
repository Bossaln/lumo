import NotchaiCore
import SwiftUI

/// Pulsierendes Leuchten rund um die Notch-Form: in Agentenfarbe für Signale (2,2 s je Zyklus), in Coverfarbe
/// für Musik (4,4 s). Liegt als eigene Ebene hinter der Notch, damit der Takt nur diese kleine Ebene neu
/// zeichnet und nicht den ganzen Inhalt. Ohne Leuchten steht die Zeitleiste still.
struct NotchGlow: View {
    let shape: NotchShape
    let color: Color
    /// 0…1; der Standard 0,6 entspricht den Werten aus dem Entwurf.
    let intensity: Double
    let enabled: Bool
    let cycle: TimeInterval

    var body: some View {
        let k = GlowPulse.strength(intensity: intensity, enabled: true)
        // Das ruhige Musik-Leuchten braucht weniger Bilder pro Sekunde; es läuft oft stundenlang.
        let fps: Double = cycle > GlowPulse.cycle ? 30 : 60
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !enabled)) { timeline in
            let level = GlowPulse.level(at: timeline.date.timeIntervalSinceReferenceDate, cycle: cycle)
            // Die Füllung liegt genau unter der Notch und ist unsichtbar; zu sehen ist nur ihr Schatten.
            shape
                .fill(Color.black)
                .shadow(color: color.opacity(min(1, (0.35 + 0.30 * level) * k)), radius: 7 + 7 * level)
                .shadow(color: color.opacity(min(1, (0.18 + 0.17 * level) * k)), radius: 2 + 2 * level)
        }
        // Ein- und Ausblenden weich statt schlagartig.
        .opacity(enabled ? 1 : 0)
        .animation(.easeInOut(duration: 0.45), value: enabled)
    }
}

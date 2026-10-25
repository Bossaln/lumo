import Foundation

/// Takt und Stärke des pulsierenden Leuchtens rund um ein Signal.
public enum GlowPulse {
    /// Ein Zyklus hell–dunkel–hell dauert 2,2 s wie im Entwurf.
    public static let cycle: TimeInterval = 2.2
    /// Das Cover-Leuchten der Musik atmet ruhiger als ein Signal.
    public static let musicCycle: TimeInterval = 4.4

    /// 0 (schwach) … 1 (hell), weich hin und her; bei 0 s schwach, nach halbem Zyklus hell.
    public static func level(at time: TimeInterval, cycle: TimeInterval = GlowPulse.cycle) -> Double {
        0.5 - 0.5 * cos(2 * Double.pi * time / cycle)
    }

    /// Faktor für die Deckkraft des Schattens; die Standardstärke 0,6 ergibt die Werte aus dem Entwurf.
    public static func strength(intensity: Double, enabled: Bool) -> Double {
        enabled ? min(max(intensity, 0), 1) / 0.6 : 0
    }
}

import CoreGraphics
import Foundation

/// Play/Pause als fließende Verwandlung: Das Play-Dreieck ist in zwei Vierecke geteilt, die zu den
/// Pause-Balken werden. Koordinaten im Einheitsquadrat (0…1, y nach unten).
public enum PlayPauseGeometry {
    private static let play: [[CGPoint]] = [
        [CGPoint(x: 0.08, y: 0), CGPoint(x: 0.53, y: 0.25), CGPoint(x: 0.53, y: 0.75), CGPoint(x: 0.08, y: 1)],
        [CGPoint(x: 0.53, y: 0.25), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.53, y: 0.75)],
    ]
    private static let pause: [[CGPoint]] = [
        [CGPoint(x: 0.1, y: 0), CGPoint(x: 0.38, y: 0), CGPoint(x: 0.38, y: 1), CGPoint(x: 0.1, y: 1)],
        [CGPoint(x: 0.62, y: 0), CGPoint(x: 0.9, y: 0), CGPoint(x: 0.9, y: 1), CGPoint(x: 0.62, y: 1)],
    ]

    /// `progress` 0 = Play, 1 = Pause, dazwischen fließend.
    public static func polygons(progress: Double) -> [[CGPoint]] {
        let t = CGFloat(min(max(progress, 0), 1))
        return zip(play, pause).map { from, to in
            zip(from, to).map { a, b in CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        }
    }
}

/// In welche Richtung das Cover beim Titelwechsel umklappt.
public enum SkipDirection: Equatable, Sendable {
    case forward, backward

    /// Wie lange nach einem Klick auf Zurück/Weiter ein Titelwechsel als dessen Folge gilt.
    public static let commandWindow: TimeInterval = 6

    /// Zurück nur direkt nach „Zurück“; sonst (Weiter, Titel zu Ende) vorwärts.
    public static func forTrackChange(lastCommand: MusicCommand?, sentAt: Date?, now: Date) -> SkipDirection {
        guard lastCommand == .previous, let sentAt, now.timeIntervalSince(sentAt) <= commandWindow else { return .forward }
        return .backward
    }
}

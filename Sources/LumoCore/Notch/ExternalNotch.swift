import CoreGraphics
import Foundation

/// Was die simulierte Notch auf externen Bildschirmen in der Mitte zeigt, wo bei der echten die Kamera sitzt.
public enum ExternalNotchCenter: String, Codable, CaseIterable, Equatable, Sendable {
    /// Alle paar Sekunden das Nächste; wartet ein Agent, bleibt der Status stehen.
    case rotating
    /// Ein Punkt je Session in der Agentenfarbe, dazu wie viele warten.
    case agents
    /// Was der zuletzt aktive Agent gerade tut.
    case lastStep
    /// Titel und Interpret der laufenden Musik.
    case music
}

/// Eine Anzeige in der Mitte.
public enum ExternalCenterItem: Hashable, Sendable {
    case agents, lastStep, music
}

public enum ExternalNotch {
    /// So lange steht eine Anzeige, bevor die nächste kommt (`rotating`).
    public static let rotationPeriod: TimeInterval = 6

    /// Welche Anzeige gerade dran ist; `nil`, wenn es nichts zu zeigen gibt (dann bleibt die Mitte leer).
    /// Wartet ein Agent auf den Besitzer, steht immer der Status da, egal was eingestellt ist.
    public static func item(for setting: ExternalNotchCenter, at date: Date, hasSessions: Bool, hasWaiting: Bool,
                            hasStep: Bool, musicPlaying: Bool) -> ExternalCenterItem? {
        if hasWaiting { return .agents }
        switch setting {
        case .agents: return hasSessions ? .agents : nil
        case .lastStep: return hasStep ? .lastStep : nil
        case .music: return musicPlaying ? .music : nil
        case .rotating:
            let available = [hasSessions ? ExternalCenterItem.agents : nil, hasStep ? .lastStep : nil,
                             musicPlaying ? .music : nil].compactMap { $0 }
            guard !available.isEmpty else { return nil }
            let slot = Int((date.timeIntervalSinceReferenceDate / rotationPeriod).rounded(.down))
            return available[((slot % available.count) + available.count) % available.count]
        }
    }

    /// Bildschirmwerte für einen externen Bildschirm: eine gedachte Notch oben mittig, so hoch wie die Menüleiste.
    /// Ist die Menüleiste ausgeblendet, gilt die übliche Höhe.
    public static func virtualScreen(frame: CGRect, menuBarHeight: CGFloat) -> ScreenInfo {
        let height = menuBarHeight >= 18 ? menuBarHeight : NotchGeometry.virtualNotchHeight
        let side = max(0, (frame.width - NotchGeometry.virtualNotchWidth) / 2)
        return ScreenInfo(frame: frame, topInset: height, leftAuxWidth: side, rightAuxWidth: side, isVirtual: true)
    }
}

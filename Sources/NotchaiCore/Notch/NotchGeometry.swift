import CoreGraphics

/// Bildschirmwerte, aus `NSScreen` befüllt (frame, safeAreaInsets.top, Aux-Bereiche).
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect
    public var topInset: CGFloat
    public var leftAuxWidth: CGFloat?
    public var rightAuxWidth: CGFloat?

    public init(frame: CGRect, topInset: CGFloat, leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?) {
        self.frame = frame
        self.topInset = topInset
        self.leftAuxWidth = leftAuxWidth
        self.rightAuxWidth = rightAuxWidth
    }
}

public enum NotchPresentation: Equatable, Sendable {
    case idle, island, banner, vertical
    /// Musik eingeklappt: links Cover, rechts Balken.
    case compact
    /// Neuer Titel, seitlich ausgefahren: links das Cover, rechts Titel und Interpret (`TrackChangeStyle.island`).
    case trackSides
    /// Neuer Titel, unter der Kamera ausgefahren (`TrackChangeStyle.banner`).
    case trackBanner
    case panel(height: CGFloat)
}

public enum NotchGeometry {
    public static let bannerMaxWidth: CGFloat = 640
    public static let bannerExtraHeight: CGFloat = 52
    public static let verticalWidth: CGFloat = 360
    public static let verticalExtraHeight: CGFloat = 150
    /// Wölbung je Seite oben am aufgeklappten Panel, die in den Bildschirmrand übergeht.
    public static let panelEar: CGFloat = 7
    /// Körper 512 pt breit plus die beiden Wölbungen.
    public static let panelWidth: CGFloat = 512 + 2 * panelEar
    public static let panelMaxHeight: CGFloat = 420
    public static let screenMargin: CGFloat = 20
    /// Breite je Seite der eingeklappten Musikanzeige.
    public static let compactSideWidth: CGFloat = 46
    /// Neuer Titel, seitlich: Breite je Seite (links Cover und gut 15 Zeichen Titel, rechts der Visualizer).
    public static let trackSideWidth: CGFloat = 170
    /// Neuer Titel, ausgefahren: Breite und Höhe unter der Kamera.
    public static let trackBannerWidth: CGFloat = 400
    public static let trackBannerExtraHeight: CGFloat = 72

    /// Hardware-Notch in Bildschirmkoordinaten; `nil` ohne Notch.
    public static func notchRect(_ s: ScreenInfo) -> CGRect? {
        guard s.topInset > 0, let left = s.leftAuxWidth, let right = s.rightAuxWidth else { return nil }
        let width = s.frame.width - left - right
        guard width > 0 else { return nil }
        return CGRect(x: s.frame.minX + left, y: s.frame.maxY - s.topInset,
                      width: width, height: s.topInset)
    }

    /// Bereich, in dem gezogene Dateien die Ablage öffnen: die sichtbare Form, seitlich und nach unten erweitert,
    /// damit man die Notch nicht genau treffen muss.
    public static func dropZone(around frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - 60, y: frame.minY - 50, width: frame.width + 120, height: frame.height + 50)
    }

    /// Rahmen der Darstellung: mittig zur Notch, oben bündig mit dem Bildschirmrand.
    public static func frame(for p: NotchPresentation, screen s: ScreenInfo, islandSideWidth: CGFloat) -> CGRect? {
        guard let notch = notchRect(s) else { return nil }
        let maxWidth = s.frame.width - 2 * screenMargin
        let size: CGSize
        switch p {
        case .idle:
            return notch
        case .island:
            size = CGSize(width: notch.width + 2 * islandSideWidth, height: notch.height)
        case .compact:
            size = CGSize(width: notch.width + 2 * compactSideWidth, height: notch.height)
        case .trackSides:
            size = CGSize(width: notch.width + 2 * trackSideWidth, height: notch.height)
        case .trackBanner:
            size = CGSize(width: max(trackBannerWidth, notch.width + 2 * compactSideWidth),
                          height: notch.height + trackBannerExtraHeight)
        case .banner:
            // Nie schmaler als die Island, aus der das Banner aufklappt.
            size = CGSize(width: max(bannerMaxWidth, notch.width + 2 * islandSideWidth),
                          height: notch.height + bannerExtraHeight)
        case .vertical:
            size = CGSize(width: verticalWidth, height: notch.height + verticalExtraHeight)
        case .panel(let height):
            size = CGSize(width: panelWidth, height: min(height, panelMaxHeight))
        }
        let width = min(size.width, maxWidth)
        return CGRect(x: notch.midX - width / 2, y: s.frame.maxY - size.height,
                      width: width, height: size.height)
    }
}

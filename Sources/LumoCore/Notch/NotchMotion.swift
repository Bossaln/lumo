import CoreGraphics

/// Richtung eines Formwechsels: Aufklappen federt, Zuklappen läuft ruhig aus (`NotchSpring`).
public enum NotchMotion: Equatable, Sendable {
    case expand, collapse

    /// Zuklappen, wenn die Form in keiner Richtung wächst und in mindestens einer schrumpft.
    public static func between(_ from: CGSize, _ to: CGSize) -> NotchMotion {
        let grows = to.width > from.width || to.height > from.height
        return grows || to == from ? .expand : .collapse
    }

    /// Nie kleiner als die Hardware-Notch, auch nicht mitten in einer Animation.
    public static func clamped(_ size: CGSize, notch: CGSize?) -> CGSize {
        guard let notch else { return size }
        return CGSize(width: max(size.width, notch.width), height: max(size.height, notch.height))
    }
}

import CoreGraphics

/// Größe und Lage des großen Büro-Fensters: 4,25 pt je Pixel mal `officeScale`, auf den
/// Bildschirm unter der Notch begrenzt. Die Pixelgröße wird auf ganze Geräte-Pixel abgerundet, damit jeder
/// Pixel der Halle gleich groß und scharf bleibt.
public enum OfficeWindowGeometry {
    /// So groß ist ein Pixel der Halle bei `officeScale` 1.
    public static let basePixelScale = 4.25
    /// Abstand zur Notch und zu den Bildschirmrändern.
    public static let gap: CGFloat = 8

    /// Rahmen in Bildschirmkoordinaten (Ursprung unten links) und Punkte je Pixel der Halle.
    public static func frame(screen: CGRect, topInset: CGFloat, centerX: CGFloat, officeScale: Double,
                             backingScale: CGFloat) -> (frame: CGRect, pixelScale: CGFloat) {
        let width = CGFloat(OfficeLayout.width), height = CGFloat(OfficeLayout.height)
        let fitWidth = (screen.width - 2 * gap) / width
        let fitHeight = (screen.height - topInset - 2 * gap) / height
        let wanted = min(CGFloat(basePixelScale * officeScale), fitWidth, fitHeight)
        let step = 1 / max(1, backingScale)
        let scale = max(step, (wanted / step).rounded(.down) * step)
        let size = CGSize(width: width * scale, height: height * scale)
        let x = min(max(centerX - size.width / 2, screen.minX + gap), screen.maxX - gap - size.width)
        let top = screen.maxY - topInset - gap
        return (CGRect(x: x, y: top - size.height, width: size.width, height: size.height), scale)
    }
}

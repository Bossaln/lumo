import Foundation

/// Rechteck in Pixeln der Szene.
public struct PixelRect: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var maxX: Int { x + w }
    public var maxY: Int { y + h }

    public func contains(_ px: Double, _ py: Double) -> Bool {
        px >= Double(x) && px < Double(maxX) && py >= Double(y) && py < Double(maxY)
    }

    public func intersects(_ other: PixelRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    public func insetBy(_ d: Int) -> PixelRect { PixelRect(x: x - d, y: y - d, w: w + 2 * d, h: h + 2 * d) }
}

/// Punkt in Pixeln der Szene (Fußpunkt einer Figur).
public struct PixelPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: PixelPoint) -> Double { hypot(other.x - x, other.y - y) }
}

/// Wohin eine Figur schaut.
public enum Facing: Equatable, Sendable { case down, up, left, right }

/// Lichtquelle für das weiche Licht-Overlay der App.
public struct OfficeLight: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case lamp, ledStrip, fridge, projection, neon, monitor(seat: Int), underglow, window }

    public var kind: Kind
    public var center: PixelPoint
    public var radius: Double
    public var color: RGBA
    public var intensity: Double
}

/// Ein Arbeitsplatz am seitlichen Tischblock.
public struct OfficeSeat: Equatable, Sendable {
    public var index: Int
    /// Fußpunkt der sitzenden Figur.
    public var sit: PixelPoint
    /// Hier steht die Figur, wenn sie auf den Besitzer wartet.
    public var stand: PixelPoint
    /// Blickrichtung beim Sitzen (zum Monitor).
    public var facing: Facing
    /// Bildschirm (für Inhalt und Licht).
    public var screen: PixelRect
}

/// Die Lagerhalle (352 × 254 Pixel).
/// - Hinten: Galerie über die ganze Breite, Treppe hinauf, darunter Ziegelwand mit Rolltor, Kühlschrank
///   und Projektionsfläche.
/// - Links die Autos, in der Mitte die Lounge, rechts der Tischblock (seitlich, aneinander) und das Bett.
public enum OfficeLayout {
    public static let width = 352
    public static let height = 254

    // Wände und Ebenen
    public static let wallLeft = 6
    public static let wallRight = 346
    /// Laufsteg der Galerie (Draufsicht) von hier …
    public static let galleryTop = 18
    /// … bis zur Vorderkante mit Geländer.
    public static let galleryFront = 31
    /// Unterkante der Ziegelwand; ab hier beginnt der Boden der Halle.
    public static let floorTop = 66

    // Feste Teile
    public static let stairs = PixelRect(x: 122, y: 30, w: 22, h: 44)
    public static let rollerDoor = PixelRect(x: 14, y: 38, w: 84, h: 28)
    public static let fridge = PixelRect(x: 168, y: 34, w: 18, h: 36)
    public static let neon = PixelRect(x: 204, y: 40, w: 12, h: 18)
    public static let projection = PixelRect(x: 288, y: 38, w: 52, h: 24)
    public static let gtr = PixelRect(x: 12, y: 84, w: 94, h: 30)
    public static let porsche = PixelRect(x: 14, y: 150, w: 88, h: 28)
    public static let deskBlock = PixelRect(x: 241, y: 86, w: 26, h: 86)
    public static let rug = PixelRect(x: 138, y: 124, w: 82, h: 60)
    public static let couch = PixelRect(x: 150, y: 128, w: 58, h: 24)
    public static let table = PixelRect(x: 162, y: 160, w: 34, h: 12)
    public static let floorLamp = PixelRect(x: 196, y: 104, w: 24, h: 50)
    public static let bed = PixelRect(x: 292, y: 178, w: 54, h: 44)
    public static let projector = PixelRect(x: 312, y: 160, w: 12, h: 10)
    public static let tires = PixelRect(x: 104, y: 112, w: 14, h: 18)
    public static let plant = PixelRect(x: 228, y: 204, w: 16, h: 26)
    public static let poolTable = PixelRect(x: 122, y: 200, w: 60, h: 36)

    /// Arbeitsplätze: drei Reihen, je eine Seite links (schaut nach rechts) und rechts (schaut nach links).
    public static let seats: [OfficeSeat] = (0..<6).map { i in
        let row = i / 2
        let left = i % 2 == 0
        let top = 92 + row * 28
        return OfficeSeat(
            index: i,
            sit: PixelPoint(left ? 232 : 276, Double(top + 20)),
            stand: PixelPoint(left ? 222 : 287, Double(top + 22)),
            facing: left ? .right : .left,
            screen: PixelRect(x: left ? 245 : 257, y: top, w: 6, h: 13)
        )
    }

    /// Sitzplätze auf der Couch (Fußpunkte).
    public static let couchSeats = [PixelPoint(166, 150), PixelPoint(179, 150), PixelPoint(192, 150)]
    /// Vor dem Kühlschrank.
    public static let fridgeSpot = PixelPoint(177, 80)
    /// Im Bett (Kopf am Kissen rechts), zwei Plätze.
    public static let bedSpots = [PixelPoint(326, 193), PixelPoint(326, 211)]
    /// Neue Figuren kommen oben auf der Galerie herein und steigen die Treppe hinab.
    public static let spawn = PixelPoint(133, 28)

    /// Bereiche, die Figuren nicht betreten.
    public static let obstacles: [PixelRect] = [
        gtr, porsche, tires, deskBlock, couch.insetBy(-2), table, bed, fridge, plant, poolTable,
        PixelRect(x: 196, y: 140, w: 24, h: 14),  // Fuß der Stehlampe
    ]

    /// Begehbar: Boden der Halle, Galerie und die Treppe dazwischen.
    public static func isWalkable(_ x: Double, _ y: Double) -> Bool {
        guard x >= Double(wallLeft + 2), x < Double(wallRight - 2), y < Double(height - 2) else { return false }
        let onFloor = y >= Double(floorTop + 4)
        let onGallery = y >= Double(galleryTop + 6) && y < Double(galleryFront)
        let onStairs = x >= Double(stairs.x + 4) && x < Double(stairs.maxX - 4) && y >= Double(stairs.y) && y < Double(stairs.maxY + 4)
        guard onFloor || onGallery || onStairs else { return false }
        return !obstacles.contains { $0.contains(x, y) }
    }

    /// Lichtquellen der Szene.
    public static let lights: [OfficeLight] = {
        var lights: [OfficeLight] = [
            OfficeLight(kind: .lamp, center: PixelPoint(200, 112), radius: 78, color: RGBA(hex: 0xFFC27A), intensity: 1),
            OfficeLight(kind: .fridge, center: PixelPoint(177, 54), radius: 46, color: RGBA(hex: 0xBFD8FF), intensity: 0.8),
            OfficeLight(kind: .projection, center: PixelPoint(314, 52), radius: 64, color: RGBA(hex: 0xFF5FA8), intensity: 0.7),
            // Streulicht des Beamers fällt aufs Bett.
            OfficeLight(kind: .projection, center: PixelPoint(318, 184), radius: 48, color: RGBA(hex: 0xFF9AD0), intensity: 0.45),
            OfficeLight(kind: .neon, center: PixelPoint(210, 48), radius: 44, color: RGBA(hex: 0xFF3D9A), intensity: 0.6),
            OfficeLight(kind: .underglow, center: PixelPoint(58, 112), radius: 60, color: RGBA(hex: 0xFF4FA3), intensity: 0.55),
            OfficeLight(kind: .underglow, center: PixelPoint(58, 176), radius: 58, color: RGBA(hex: 0xB6FF2E), intensity: 0.5),
            OfficeLight(kind: .window, center: PixelPoint(176, 8), radius: 160, color: RGBA(hex: 0xDDEBFF), intensity: 0.0),
        ]
        for x in stride(from: 20, through: 330, by: 52) {
            lights.append(OfficeLight(kind: .ledStrip, center: PixelPoint(Double(x), 36), radius: 30,
                                      color: RGBA(hex: 0xFFB36B), intensity: 0.45))
        }
        for seat in seats {
            lights.append(OfficeLight(kind: .monitor(seat: seat.index),
                                      center: PixelPoint(Double(seat.screen.x + 3), Double(seat.screen.y + 7)),
                                      radius: 30, color: RGBA(hex: 0x9CC8FF), intensity: 0.7))
        }
        return lights
    }()
}

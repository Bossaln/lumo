import Foundation
import Testing
@testable import NotchaiCore

@Test func sceneHasFixedDimensions() {
    // 352 × 254 Pixel.
    let bg = OfficeArt.background(daylight: 0)
    #expect(bg.width == 352 && bg.height == 254)
}

@Test func floorIsDarkMarbleWithVeins() {
    var dark = 0, veins = 0, total = 0
    for y in stride(from: OfficeLayout.floorTop, to: OfficeLayout.height, by: 2) {
        for x in stride(from: 0, to: OfficeLayout.width, by: 2) {
            let p = OfficeArt.marble(x, y)
            total += 1
            if Int(p.r) + Int(p.g) + Int(p.b) < 3 * 40 { dark += 1 }
            if p == OfficeArt.marbleVein || p == OfficeArt.marbleVeinLight { veins += 1 }
        }
    }
    #expect(Double(dark) / Double(total) > 0.8)   // überwiegend dunkel
    #expect(veins > total / 100)                  // mit sichtbaren Adern
    #expect(OfficeArt.marble(100, 100) == OfficeArt.marble(100, 100))  // immer gleich
}

@Test func carsHaveTheirColors() {
    let props = OfficeArt.props()
    let gtr = try! #require(props.first { $0.name == "gtr" })
    let porsche = try! #require(props.first { $0.name == "911" })
    #expect(gtr.canvas.pixels.contains(RGBA(hex: 0xFF4FA3)))    // pink
    #expect(porsche.canvas.pixels.contains(RGBA(hex: 0xA8E61D)))  // limettengrün
    // Der GT-R steht oben, der 911 darunter.
    #expect(gtr.y < porsche.y)
}

@Test func nameIsHiddenOnTheRollerDoor() {
    // „BØSSA“ steht dezent (grau) auf dem Rolltor, nicht in grellem Weiß.
    let bg = OfficeArt.background(daylight: 0)
    let door = OfficeLayout.rollerDoor
    var name = PixelCanvas(width: door.w, height: door.h)
    name.text("BØSSA", at: 6, 5, color: RGBA(255, 255, 255))
    let stencil = RGBA(hex: 0x6E7582)
    var matches = 0
    for y in 0..<door.h { for x in 0..<door.w where name[x, y].a > 0 && bg[door.x + x, door.y + y] == stencil { matches += 1 } }
    #expect(matches > 25)
}

@Test func seatsAndSpotsAreReachable() {
    for seat in OfficeLayout.seats {
        #expect(OfficeLayout.isWalkable(seat.stand.x, seat.stand.y))
        #expect(OfficeLayout.isWalkable(seat.sit.x, seat.sit.y))
    }
    #expect(OfficeLayout.isWalkable(OfficeLayout.fridgeSpot.x, OfficeLayout.fridgeSpot.y))
    #expect(OfficeLayout.isWalkable(OfficeLayout.spawn.x, OfficeLayout.spawn.y))
    #expect(!OfficeLayout.isWalkable(Double(OfficeLayout.gtr.x + 30), Double(OfficeLayout.gtr.y + 20)))
}

@Test func fridgeCouchBedAndDesksExist() {
    let names = Set(OfficeArt.props().map(\.name))
    #expect(names.isSuperset(of: ["fridge", "couch", "bed", "projector", "desks", "gtr", "911"]))
    #expect(OfficeLayout.seats.count == 6)
    // Seitlich: links schauen alle nach rechts, rechts nach links.
    #expect(OfficeLayout.seats.filter { $0.facing == .right }.count == 3)
}

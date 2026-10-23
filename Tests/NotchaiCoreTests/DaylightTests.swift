import Foundation
import Testing
@testable import NotchaiCore

private func utc(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: text)!
}

@Test func noonIsBrightMidnightIsDark() {
    // Berlin am längsten Tag: mittags hoch, um Mitternacht unter dem Horizont.
    let noon = Daylight.sunElevation(date: utc("2026-06-21T11:00:00Z"), latitude: 52.52, longitude: 13.405)
    let midnight = Daylight.sunElevation(date: utc("2026-06-20T23:00:00Z"), latitude: 52.52, longitude: 13.405)
    #expect(noon > 58 && noon < 63)
    #expect(midnight < -10 && midnight > -17)
    #expect(Daylight.level(elevation: noon) == 1)
    #expect(Daylight.level(elevation: midnight) == 0)
}

@Test func twilightIsBetween() {
    let dusk = Daylight.level(elevation: -2)
    #expect(dusk > 0 && dusk < 1)
    #expect(Daylight.level(elevation: 2) > dusk)
}

@Test func fixedModesIgnoreTheSun() {
    var settings = AppSettings.default
    let night = utc("2026-06-20T23:00:00Z")
    settings.officeLighting = .fixedDay
    #expect(Daylight.level(settings: settings, date: night, timeZone: .gmt) == 1)
    settings.officeLighting = .fixedNight
    #expect(Daylight.level(settings: settings, date: utc("2026-06-21T11:00:00Z"), timeZone: .gmt) == 0)
}

@Test func locationFallsBackToTimeZone() {
    // Ohne Ort: Länge aus der Zeitzone (15° je Stunde), Breite 50°.
    let zone = TimeZone(secondsFromGMT: 2 * 3600)!
    let guess = Daylight.location(latitude: nil, longitude: nil, timeZone: zone, date: utc("2026-06-21T11:00:00Z"))
    #expect(guess.latitude == 50 && guess.longitude == 30)
    let set = Daylight.location(latitude: 52.5, longitude: 13.4, timeZone: zone, date: .now)
    #expect(set.latitude == 52.5 && set.longitude == 13.4)
}

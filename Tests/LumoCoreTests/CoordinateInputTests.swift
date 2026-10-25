import Testing
@testable import LumoCore

@Test func coordinateAcceptsCommaAndPoint() {
    #expect(CoordinateInput.latitude.parse("52,52") == .value(52.52))
    #expect(CoordinateInput.latitude.parse(" 52.52 ") == .value(52.52))
    #expect(CoordinateInput.longitude.parse("-13,4") == .value(-13.4))
    #expect(CoordinateInput.longitude.parse("13") == .value(13))
}

@Test func emptyCoordinateClearsValue() {
    #expect(CoordinateInput.latitude.parse("") == .empty)
    #expect(CoordinateInput.longitude.parse("   ") == .empty)
}

@Test func coordinateOutsideRangeOrGarbageIsInvalid() {
    #expect(CoordinateInput.latitude.parse("90") == .value(90))
    #expect(CoordinateInput.latitude.parse("90,5") == .invalid)
    #expect(CoordinateInput.latitude.parse("-91") == .invalid)
    #expect(CoordinateInput.longitude.parse("180") == .value(180))
    #expect(CoordinateInput.longitude.parse("180,1") == .invalid)
    #expect(CoordinateInput.longitude.parse("abc") == .invalid)
    #expect(CoordinateInput.longitude.parse("1,2,3") == .invalid)
    #expect(CoordinateInput.longitude.parse("nan") == .invalid)
    #expect(CoordinateInput.longitude.parse("inf") == .invalid)
}

@Test func coordinateIsShownWithGermanComma() {
    #expect(CoordinateInput.format(52.52) == "52,52")
    #expect(CoordinateInput.format(13.4) == "13,4")
    #expect(CoordinateInput.format(-0.000001) == "-0,000001")
    #expect(CoordinateInput.format(10) == "10")
    #expect(CoordinateInput.format(nil) == "")
}

@Test func coordinateRangesAndHint() {
    #expect(CoordinateInput.latitude.range == -90...90)
    #expect(CoordinateInput.longitude.range == -180...180)
    #expect(CoordinateInput.latitude.invalidHint == "Breitengrad: Zahl von −90 bis 90, z. B. 52,52")
    #expect(CoordinateInput.longitude.invalidHint == "Längengrad: Zahl von −180 bis 180, z. B. 13,40")
}

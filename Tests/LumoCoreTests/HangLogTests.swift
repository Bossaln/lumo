import Foundation
import Testing
@testable import LumoCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Test func shortDelaysAreNotHangs() {
    var log = HangLog()
    let recorded = log.record(delay: 0.04, at: start, context: "Ruhe")
    #expect(!recorded)
    #expect(log.count == 0)
    #expect(log.summary == "Keine Hänger gemessen")
}

@Test func hangsAreCountedWithTheLongest() {
    var log = HangLog()
    log.record(delay: 0.18, at: start, context: "Musik spielt")
    log.record(delay: 0.64, at: start + 5, context: "Panel offen (Musik)")
    #expect(log.count == 2)
    #expect(log.longestMilliseconds == 640)
    #expect(log.summary == "2 Hänger, längster 640 ms")
    #expect(log.entries.first?.context == "Panel offen (Musik)")
}

@Test func onlyTheNewestHangsAreKept() {
    var log = HangLog()
    for index in 0..<(HangLog.keep + 5) {
        log.record(delay: 0.2, at: start + Double(index), context: "\(index)")
    }
    #expect(log.entries.count == HangLog.keep)
    #expect(log.count == HangLog.keep + 5)
    #expect(log.entries.first?.context == "\(HangLog.keep + 4)")
}

@Test func reportListsEveryHangWithTimeAndContext() {
    var log = HangLog()
    log.record(delay: 0.25, at: start, context: "Musik spielt")
    let report = log.report(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    #expect(report.contains("1 Hänger, längster 250 ms"))
    #expect(report.contains("250 ms"))
    #expect(report.contains("Musik spielt"))
    #expect(report.contains(":00"))
}

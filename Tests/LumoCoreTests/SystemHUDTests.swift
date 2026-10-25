import Foundation
import Testing
@testable import LumoCore

// MARK: - Anzeigen

@Test func volumeSymbolFollowsTheLevel() {
    #expect(SystemIndicator.volume(level: 0, muted: false).symbol == "speaker.slash.fill")
    #expect(SystemIndicator.volume(level: 0.2, muted: false).symbol == "speaker.wave.1.fill")
    #expect(SystemIndicator.volume(level: 0.5, muted: false).symbol == "speaker.wave.2.fill")
    #expect(SystemIndicator.volume(level: 0.9, muted: false).symbol == "speaker.wave.3.fill")
    // Stumm: kein Balken, auch wenn die Lautstärke hoch steht.
    let muted = SystemIndicator.volume(level: 0.9, muted: true)
    #expect(muted.symbol == "speaker.slash.fill" && muted.value == .level(0))
    #expect(SystemIndicator.volume(level: 1.7, muted: false).value == .level(1))
}

@Test func batterySymbolFollowsTheLevel() {
    #expect(SystemIndicator.power(charging: true, level: 0.3).symbol == "battery.100percent.bolt")
    #expect(SystemIndicator.power(charging: true, level: 0.3).tint == SystemTint.green)
    #expect(SystemIndicator.power(charging: false, level: 0.3).symbol == "battery.25percent")
    #expect(SystemIndicator.power(charging: false, level: 0.95).symbol == "battery.100percent")
    #expect(SystemIndicator.lowBattery(level: 0.08).symbol == "battery.0percent")
    #expect(SystemIndicator.lowBattery(level: 0.08).tint == SystemTint.red)
    // Beide haben die Art „Strom“, aber verschiedene IDs: Der Hinweis auf die leere Batterie ersetzt den Ladehinweis.
    #expect(SystemIndicator.lowBattery(level: 0.1).id != SystemIndicator.power(charging: false, level: 0.1).id)
}

@Test func focusIndicatorUsesTheModesSymbolAndColor() {
    let mode = FocusMode(identifier: "work", name: "Arbeiten", symbol: "briefcase.fill", tint: FocusTint.rgb(named: "teal"))
    let on = SystemIndicator.focus(mode)
    #expect(on.symbol == "briefcase.fill" && on.tint == FocusTint.rgb(named: "teal") && on.value == .text("Arbeiten"))
    let off = SystemIndicator.focusOff(mode)
    #expect(off.tint == SystemTint.gray && off.value == .text("Arbeiten aus") && off.id == on.id)
    #expect(SystemIndicator.focusOff(nil).value == .text("Fokus aus"))
}

@Test func timerIndicatorsStayAndTheFiredOneBlinks() {
    let running = SystemIndicator.timerRunning(until: Date(timeIntervalSinceNow: 60))
    #expect(running.sticky && !running.pulses && running.tint == SystemTint.orange)
    #expect(SystemIndicator.timerPaused(remaining: 30).value == .remaining(30))
    let fired = SystemIndicator.timerFired()
    #expect(fired.sticky && fired.pulses && fired.value == .remaining(0))
    #expect(SystemIndicator.alarmRinging(title: "").value == .text("Wecker"))
    #expect(SystemIndicator.alarmRinging(title: "Aufstehen").value == .text("Aufstehen"))
}

@Test func countdownIsFormattedLikeTheClockApp() {
    #expect(SystemIndicatorFormat.countdown(0) == "0:00")
    #expect(SystemIndicatorFormat.countdown(7) == "0:07")
    #expect(SystemIndicatorFormat.countdown(754) == "12:34")
    #expect(SystemIndicatorFormat.countdown(3723) == "1:02:03")
    // Angebrochene Sekunden zählen noch, negative Zeit nie.
    #expect(SystemIndicatorFormat.countdown(59.2) == "1:00")
    #expect(SystemIndicatorFormat.countdown(-5) == "0:00")
    #expect(SystemIndicatorFormat.percent(0.567) == "57 %")
}

@Test func textValuesNeedMoreRoomThanBars() {
    #expect(!SystemIndicatorValue.level(0.5).isText)
    #expect(SystemIndicatorValue.text("AirPods").isText)
    #expect(SystemIndicatorValue.countdown(until: .now).isText)
    #expect(NotchGeometry.hudSideWidth(forText: true) > NotchGeometry.hudSideWidth(forText: false))
}

@Test func hudPresentationIsAsHighAsTheNotch() {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, leftAuxWidth: 656, rightAuxWidth: 656)
    let frame = NotchGeometry.frame(for: .hud(sideWidth: 92), screen: screen, islandSideWidth: 120)
    #expect(frame?.height == 32)
    #expect(frame?.width == 384)
    #expect(frame?.midX == 756)
}

// MARK: - Ablauf

@Test func transientIndicatorsReplaceEachOtherAndExpire() {
    var state = SystemHUDState()
    let start = ContinuousClock.now
    state.show(.volume(level: 0.5, muted: false), now: start, hold: .seconds(2))
    #expect(state.visible?.kind == .volume)
    state.show(.brightness(level: 0.5), now: start + .seconds(1), hold: .seconds(2))
    #expect(state.visible?.kind == .brightness)
    // Die zweite Anzeige hat ihre eigene Frist.
    let early = state.expire(now: start + .seconds(2.5))
    #expect(!early)
    #expect(state.visible?.kind == .brightness)
    let late = state.expire(now: start + .seconds(3))
    #expect(late)
    #expect(state.visible == nil)
}

@Test func stickyIndicatorReturnsAfterATransientOne() {
    var state = SystemHUDState()
    let start = ContinuousClock.now
    let timer = SystemIndicator.timerRunning(until: Date(timeIntervalSinceNow: 300))
    state.show(timer, now: start, hold: .seconds(2))
    state.show(.volume(level: 0.3, muted: false), now: start, hold: .seconds(2))
    #expect(state.visible?.kind == .volume)
    state.expire(now: start + .seconds(2))
    #expect(state.visible == timer)
    // Der Wecker geht vor dem Timer; endet er, ist der Timer wieder da.
    state.show(.alarmRinging(title: nil), now: start, hold: .seconds(2))
    #expect(state.visible?.kind == .alarm)
    state.endSticky(.alarm)
    #expect(state.visible == timer)
    state.endSticky(.timer)
    #expect(state.visible == nil)
}

@Test func hoverEndsOnlyTheTransientIndicator() {
    var state = SystemHUDState()
    let timer = SystemIndicator.timerRunning(until: Date(timeIntervalSinceNow: 300))
    state.show(timer, now: .now, hold: .seconds(2))
    state.show(.capsLock(on: true), now: .now, hold: .seconds(2))
    state.endTransient()
    #expect(state.visible == timer)
    #expect(state.hideAt == nil)
}

@Test func aStickyTimerReplacesItsOwnShortHint() {
    var state = SystemHUDState()
    var hint = SystemIndicator.timerRunning(until: Date(timeIntervalSinceNow: 300))
    hint.sticky = false
    state.show(hint, now: .now, hold: .seconds(2))
    state.show(.timerFired(), now: .now, hold: .seconds(2))
    #expect(state.transient == nil && state.visible?.pulses == true)
}

// MARK: - Sondertasten

@Test func mediaKeyEventsAreDecoded() {
    // Lauter, gedrückt, keine Wiederholung: Taste 0 oben, 0x0A00 darunter.
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0000_0A00) == MediaKeyPress(key: .soundUp, down: true, isRepeat: false))
    // Leiser, losgelassen.
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0001_0B00) == MediaKeyPress(key: .soundDown, down: false, isRepeat: false))
    // Helligkeit hoch, gehalten (Wiederholung).
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0002_0A01) == MediaKeyPress(key: .brightnessUp, down: true, isRepeat: true))
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0017_0A00)?.key == .illuminationToggle)
    // Anderer Untertyp oder unbekannte Taste: nichts.
    #expect(MediaKeys.decode(subtype: 7, data1: 0x0000_0A00) == nil)
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0099_0A00) == nil)
    #expect(MediaKeys.decode(subtype: 8, data1: 0x0000_0C00) == nil)
}

@Test func playbackKeysStayWithMacOS() {
    #expect(!MediaKey.play.isHandledByLumo && !MediaKey.next.isHandledByLumo)
    #expect(MediaKey.mute.isHandledByLumo && MediaKey.brightnessDown.isHandledByLumo)
}

@Test func levelsMoveInSixteenthsAndSnapToTheGrid() {
    #expect(MediaKeys.adjusted(0.5, up: true, fine: false) == 0.5625)
    #expect(MediaKeys.adjusted(0.5, up: false, fine: false) == 0.4375)
    #expect(MediaKeys.adjusted(0.5, up: true, fine: true) == 0.5 + 1.0 / 64)
    // Zwischenwerte (etwa vom Schieberegler) landen auf der nächsten Stufe.
    #expect(MediaKeys.adjusted(0.51, up: true, fine: false) == 0.5625)
    #expect(MediaKeys.adjusted(0.98, up: true, fine: false) == 1)
    #expect(MediaKeys.adjusted(0.02, up: false, fine: false) == 0)
}

// MARK: - Fokus

private let configurationsJSON = """
{"data":[{"modeConfigurations":{
  "com.apple.donotdisturb.mode.default":{"mode":{"modeIdentifier":"com.apple.donotdisturb.mode.default","name":"","symbolImageName":"moon.fill","tintColorName":"indigo","semanticType":1}},
  "com.apple.focus.work":{"mode":{"modeIdentifier":"com.apple.focus.work","name":"Arbeit","symbolImageName":"briefcase.fill","tintColorName":"teal","semanticType":4}}
}}]}
"""

private let assertionsJSON = """
{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work","assertionDetailsIdentifier":"x"},"assertionSource":{"assertionSourceClientIdentifier":"com.apple.controlcenter"}}]}]}
"""

@Test func focusFilesNameTheActiveModeWithSymbolAndColor() throws {
    let state = try #require(FocusModes.parse(configurations: Data(configurationsJSON.utf8), assertions: Data(assertionsJSON.utf8)))
    #expect(state.activeIdentifier == "com.apple.focus.work")
    let active = try #require(state.activeMode)
    #expect(active.name == "Arbeit" && active.symbol == "briefcase.fill" && active.tint == FocusTint.rgb(named: "teal"))
    // „Nicht stören“ hat in der Datei keinen Namen.
    #expect(state.modes["com.apple.donotdisturb.mode.default"]?.name == "Nicht stören")
}

@Test func activeModeIsFoundEvenUnderAnotherKey() throws {
    // macOS benennt die Schlüssel um; ein Text, der einen bekannten Fokus nennt, reicht.
    let assertions = Data("{\"data\":[{\"records\":[{\"details\":{\"mode\":\"com.apple.focus.work\"},\"time\":1}]}]}".utf8)
    let state = try #require(FocusModes.parse(configurations: Data(configurationsJSON.utf8), assertions: assertions))
    #expect(state.activeIdentifier == "com.apple.focus.work")
    // Unbekannte Kennungen zählen nur über den bekannten Schlüssel.
    let unknown = Data("{\"data\":[{\"storeAssertionRecords\":[{\"assertionDetails\":{\"assertionDetailsModeIdentifier\":\"com.apple.focus.custom\"}}]}]}".utf8)
    #expect(FocusModes.parse(configurations: Data(configurationsJSON.utf8), assertions: unknown)?.activeIdentifier == "com.apple.focus.custom")
}

@Test func noAssertionMeansNoFocus() throws {
    let state = try #require(FocusModes.parse(configurations: Data(configurationsJSON.utf8), assertions: Data("{\"data\":[{\"storeAssertionRecords\":[]}]}".utf8)))
    #expect(state.activeIdentifier == nil && state.activeMode == nil)
    #expect(FocusModes.parse(configurations: Data(configurationsJSON.utf8), assertions: nil)?.activeIdentifier == nil)
    #expect(FocusModes.parse(configurations: Data("kaputt".utf8), assertions: nil) == nil)
}

@Test func unknownFocusStillGetsAName() {
    let state = FocusModes(modes: [:], activeIdentifier: "com.apple.focus.custom")
    #expect(state.activeMode?.name == "Fokus" && state.activeMode?.symbol == "moon.fill")
}

@Test func focusColorsMatchApple() {
    #expect(FocusTint.rgb(named: "Orange") == SystemTint.orange)
    #expect(FocusTint.rgb(named: "purple") != FocusTint.rgb(named: "indigo"))
    // Unbekannt und fehlend: Indigo wie „Nicht stören“.
    #expect(FocusTint.rgb(named: nil) == FocusTint.rgb(named: "indigo"))
    #expect(FocusTint.rgb(named: "chartreuse") == FocusTint.rgb(named: "indigo"))
}

// MARK: - Uhr-App

private func archive(_ object: Any) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
}

private func fireDateArchive(_ date: Date) -> Data {
    archive(["$version": 100_000, "$archiver": "NSKeyedArchiver", "$top": ["root": 1],
             "$objects": ["$null", ["$class": 2, "NS.time": date.timeIntervalSinceReferenceDate], ["$classname": "NSDate", "$classes": ["NSDate", "NSObject"]]]])
}

private func intervalArchive(_ seconds: Double) -> Data {
    archive(["$version": 100_000, "$archiver": "NSKeyedArchiver", "$top": ["root": 1],
             "$objects": ["$null", ["$class": 2, "MTTimerTimeInterval": seconds], ["$classname": "MTTimerTimeInterval", "$classes": ["MTTimerTimeInterval", "NSObject"]]]])
}

@Test func archivedFireTimeIsADateOrAnInterval() {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(ArchivedFireTime.decode(fireDateArchive(date)) == .date(date))
    #expect(ArchivedFireTime.decode(intervalArchive(900)) == .interval(900))
    #expect(ArchivedFireTime.decode(Data("nix".utf8)) == nil)
}

@Test func runningTimerCountsDownToItsFireDate() {
    let now = Date()
    let fire = now.addingTimeInterval(120)
    let rows = [TimerRow(state: TimerRow.running, duration: 300, fireTime: fireDateArchive(fire)),
                TimerRow(state: TimerRow.stopped, duration: 900)]
    #expect(ClockState.timer(rows: rows, now: now) == .running(fireDate: fire))
}

@Test func pausedTimerKeepsItsRemainingTime() {
    let rows = [TimerRow(state: TimerRow.paused, duration: 300, fireTime: intervalArchive(42))]
    #expect(ClockState.timer(rows: rows, now: .now) == .paused(remaining: 42))
}

@Test func firedTimerRingsUntilDismissed() {
    let now = Date()
    let firedAt = now.addingTimeInterval(-30)
    let ringing = [TimerRow(state: TimerRow.stopped, duration: 60, firedDate: firedAt)]
    #expect(ClockState.timer(rows: ringing, now: now) == .fired)
    let dismissed = [TimerRow(state: TimerRow.stopped, duration: 60, firedDate: firedAt, dismissedDate: now.addingTimeInterval(-10))]
    #expect(ClockState.timer(rows: dismissed, now: now) == nil)
    // Ein uralter Zündzeitpunkt zählt nicht mehr.
    let stale = [TimerRow(state: TimerRow.stopped, duration: 60, firedDate: now.addingTimeInterval(-3600))]
    #expect(ClockState.timer(rows: stale, now: now) == nil)
    // Läuft laut Zustand, aber der Zündzeitpunkt ist vorbei: abgelaufen.
    let overdue = [TimerRow(state: TimerRow.running, duration: 60, fireTime: fireDateArchive(firedAt))]
    #expect(ClockState.timer(rows: overdue, now: now) == .fired)
}

@Test func aRunningTimerBeatsAPausedOne() {
    let now = Date()
    let fire = now.addingTimeInterval(50)
    let rows = [TimerRow(state: TimerRow.paused, duration: 300, fireTime: intervalArchive(42)),
                TimerRow(state: TimerRow.running, duration: 300, fireTime: fireDateArchive(fire))]
    #expect(ClockState.timer(rows: rows, now: now) == .running(fireDate: fire))
    #expect(ClockState.timer(rows: [], now: now) == nil)
}

@Test func alarmsRingOrSnooze() {
    let now = Date()
    let ringing = AlarmRow(enabled: true, hour: 7, minute: 0, title: "Aufstehen", firedDate: now.addingTimeInterval(-20))
    #expect(ClockState.alarm(rows: [ringing], now: now) == .ringing(title: "Aufstehen"))
    let snoozed = AlarmRow(enabled: true, hour: 7, minute: 0, firedDate: now.addingTimeInterval(-60),
                           dismissedDate: now.addingTimeInterval(-50), snoozeFireDate: now.addingTimeInterval(500))
    #expect(ClockState.alarm(rows: [snoozed], now: now) == .snoozed(until: now.addingTimeInterval(500)))
    let quiet = AlarmRow(enabled: true, hour: 7, minute: 0, firedDate: now.addingTimeInterval(-60), dismissedDate: now.addingTimeInterval(-50))
    #expect(ClockState.alarm(rows: [quiet], now: now) == nil)
    // Beides: Das Klingeln geht vor.
    #expect(ClockState.alarm(rows: [snoozed, ringing], now: now) == .ringing(title: "Aufstehen"))
}

// MARK: - Strom

@Test func powerTrackerReportsPlugAndLowBattery() {
    var tracker = PowerTracker()
    // Der erste Stand ist nur der Start.
    #expect(tracker.update(PowerState(external: true, level: 0.9)) == nil)
    #expect(tracker.update(PowerState(external: true, level: 0.91)) == nil)
    let unplugged = tracker.update(PowerState(external: false, level: 0.91))
    #expect(unplugged?.kind == .power && unplugged?.symbol == "battery.100percent")
    #expect(tracker.update(PowerState(external: false, level: 0.5)) == nil)
    #expect(tracker.update(PowerState(external: false, level: 0.2))?.tint == SystemTint.red)
    // Dieselbe Schwelle nur einmal, die nächste bei 10 %.
    #expect(tracker.update(PowerState(external: false, level: 0.19)) == nil)
    #expect(tracker.update(PowerState(external: false, level: 0.1))?.id == "power.low")
    #expect(tracker.update(PowerState(external: false, level: 0.05)) == nil)
    // Laden setzt die Warnungen zurück.
    #expect(tracker.update(PowerState(external: true, level: 0.05))?.symbol == "battery.100percent.bolt")
    #expect(tracker.update(PowerState(external: false, level: 0.06))?.tint == SystemTint.white)
    #expect(tracker.update(PowerState(external: false, level: 0.05))?.tint == SystemTint.red)
}

// MARK: - Audioausgabe

@Test func audioOutputSymbolComesFromNameOrTransport() {
    #expect(AudioOutputKind.symbol(name: "Lucas AirPods Pro", transport: "blue") == "airpodspro")
    #expect(AudioOutputKind.symbol(name: "AirPods Max", transport: "blue") == "airpodsmax")
    #expect(AudioOutputKind.symbol(name: "WH-1000XM5", transport: "blue") == "headphones")
    #expect(AudioOutputKind.symbol(name: "MacBook Air-Lautsprecher", transport: "bltn") == "laptopcomputer")
    #expect(AudioOutputKind.symbol(name: "LG HDR 4K", transport: "dprt") == "display")
    #expect(AudioOutputKind.symbol(name: "Wohnzimmer", transport: "airp") == "airplayaudio")
    #expect(AudioOutputKind.symbol(name: "Scarlett", transport: nil) == "speaker.wave.2.fill")
    #expect(AudioOutputKind.transportCode(0x626C_7565) == "blue")
}

// MARK: - Einstellungen

@Test func hiddenKindsAreNotShown() {
    var settings = AppSettings()
    #expect(settings.shows(.volume) && settings.shows(.timer))
    settings.hudHidden = [.timer]
    #expect(settings.shows(.volume) && !settings.shows(.timer))
    settings.systemHUD = false
    #expect(!settings.shows(.volume))
}

@Test func unknownHiddenKindsAreSkippedWhenLoading() throws {
    let json = Data("{\"hudHidden\":[\"volume\",\"hologram\"],\"systemHUDSeconds\":40}".utf8)
    let settings = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(settings.hudHidden == [.volume])
    #expect(settings.systemHUDSeconds == AppSettings.systemHUDSecondsRange.upperBound)
}

import CoreGraphics
import Foundation
import Testing
@testable import NotchaiCore

private let t0 = Date(timeIntervalSinceReferenceDate: 600)

@Test func waitingAgentAlwaysWins() {
    for setting in ExternalNotchCenter.allCases {
        #expect(ExternalNotch.item(for: setting, at: t0, hasSessions: true, hasWaiting: true, hasStep: true, musicPlaying: true) == .agents)
    }
}

@Test func rotatingSkipsWhatIsMissing() {
    let items = (0..<6).map { slot in
        ExternalNotch.item(for: .rotating, at: t0.addingTimeInterval(Double(slot) * ExternalNotch.rotationPeriod),
                           hasSessions: true, hasWaiting: false, hasStep: false, musicPlaying: true)
    }
    #expect(Set(items.compactMap { $0 }) == [.agents, .music])
    #expect(items[0] != items[1])
    #expect(ExternalNotch.item(for: .rotating, at: t0, hasSessions: false, hasWaiting: false, hasStep: false, musicPlaying: false) == nil)
}

@Test func fixedChoiceStaysOrIsEmpty() {
    #expect(ExternalNotch.item(for: .music, at: t0, hasSessions: true, hasWaiting: false, hasStep: true, musicPlaying: false) == nil)
    #expect(ExternalNotch.item(for: .lastStep, at: t0, hasSessions: true, hasWaiting: false, hasStep: true, musicPlaying: true) == .lastStep)
}

@Test func virtualScreenHasACenteredNotch() throws {
    let frame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    let screen = ExternalNotch.virtualScreen(frame: frame, menuBarHeight: 25)
    #expect(screen.isVirtual)
    let notch = try #require(NotchGeometry.notchRect(screen))
    #expect(notch.width == NotchGeometry.virtualNotchWidth)
    #expect(notch.height == 25)
    #expect(notch.midX == frame.midX)
    #expect(notch.maxY == frame.maxY)
    let idle = try #require(NotchGeometry.frame(for: .externalIdle, screen: screen, islandSideWidth: 120))
    #expect(idle.width == notch.width + 2 * NotchGeometry.externalIdleSideWidth)
    #expect(idle.height == 25)
    // Ausgeblendete Menüleiste: übliche Höhe.
    #expect(NotchGeometry.notchRect(ExternalNotch.virtualScreen(frame: frame, menuBarHeight: 0))?.height == NotchGeometry.virtualNotchHeight)
}

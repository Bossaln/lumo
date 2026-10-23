import AppKit
import NotchaiCore
import Observation
import SwiftUI

/// Begrüßung beim ersten Start: Der ganze Bildschirmrand leuchtet in den Farben von notchai auf, das Leuchten zieht
/// sich in die Notch zusammen, und dort leuchtet die Notch weiter, bis die Einrichtung fertig ist.
@MainActor
final class IntroGlowController {
    private var window: NSWindow?
    private let state = IntroGlowState()

    /// Spielt die Begrüßung ab; `arrived` kommt, sobald das Leuchten in der Notch angekommen ist.
    func play(screen: ScreenInfo?, colors: [Color], arrived: @escaping () -> Void) {
        guard window == nil, let screen, let nsScreen = Self.nsScreen(matching: screen) else {
            arrived()
            return
        }
        let frame = screen.frame
        // Ziel in Fensterkoordinaten (Ursprung oben links): die Notch, ohne Notch oben mittig.
        let notch = NotchGeometry.notchRect(screen)
            ?? CGRect(x: frame.midX - 100, y: frame.maxY - 32, width: 200, height: 32)
        let target = CGRect(x: notch.minX - frame.minX, y: frame.maxY - notch.maxY, width: notch.width, height: notch.height)

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: nsScreen)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IntroGlowView(state: state, size: frame.size, target: target, colors: colors))
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window

        state.phase = .hidden
        Task { @MainActor [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.8)) { self.state.phase = .screen }
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.spring(response: 1.1, dampingFraction: 0.88)) { self.state.phase = .notch }
            try? await Task.sleep(for: .milliseconds(1150))
            arrived()
            withAnimation(.easeIn(duration: 0.6)) { self.state.phase = .gone }
            try? await Task.sleep(for: .milliseconds(700))
            self.window?.orderOut(nil)
            self.window = nil
        }
    }

    private static func nsScreen(matching info: ScreenInfo) -> NSScreen? {
        NSScreen.screens.first { $0.frame == info.frame } ?? NSScreen.main
    }
}

@MainActor @Observable
final class IntroGlowState {
    enum Phase { case hidden, screen, notch, gone }
    var phase: Phase = .hidden
}

/// Leuchtender Rahmen, der vom Bildschirmrand zur Notch wandert. Der Farbverlauf dreht sich dabei langsam.
struct IntroGlowView: View {
    let state: IntroGlowState
    let size: CGSize
    let target: CGRect
    let colors: [Color]

    var body: some View {
        let inNotch = state.phase == .notch || state.phase == .gone
        let rect = inNotch ? target : CGRect(origin: .zero, size: size)
        let radius: CGFloat = inNotch ? 10 : 14
        let line: CGFloat = inNotch ? 3 : 9
        TimelineView(.animation) { timeline in
            let turn = (timeline.date.timeIntervalSinceReferenceDate * 90).truncatingRemainder(dividingBy: 360)
            let gradient = AngularGradient(colors: colors + colors.prefix(1), center: .center, angle: .degrees(turn))
            let frame = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                frame.strokeBorder(gradient, lineWidth: line * 3).blur(radius: inNotch ? 10 : 34)
                frame.strokeBorder(gradient, lineWidth: line).blur(radius: inNotch ? 3 : 8)
                frame.strokeBorder(Color.white.opacity(0.5), lineWidth: 1).blur(radius: 0.5)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
        .opacity(state.phase == .screen || state.phase == .notch ? 1 : 0)
        .frame(width: size.width, height: size.height)
    }
}

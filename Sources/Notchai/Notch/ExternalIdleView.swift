import AppKit
import NotchaiCore
import SwiftUI

/// Ruhezustand der simulierten Notch auf einem externen Bildschirm. Dort ist keine Kamera, also bekommt auch die
/// Mitte etwas: links die Uhrzeit, in der Mitte die gewählte Info (`ExternalNotchCenter`), rechts die Musik oder
/// wie viele Sessions laufen.
struct ExternalIdleView: View {
    let model: AppModel
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat

    private static let waitingColor = Color(.sRGB, red: 0.88, green: 0.46, blue: 0.29)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let item = centerItem(at: context.date)
            HStack(spacing: 0) {
                clock(context.date)
                    .frame(width: sideWidth, alignment: .leading)
                ZStack {
                    if let item {
                        center(item)
                            .id(item)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                                    removal: .opacity.combined(with: .offset(y: -6))))
                    }
                }
                .frame(width: notchWidth)
                .clipped()
                .animation(.easeInOut(duration: 0.45), value: item)
                trailing
                    .frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: height)
        }
    }

    private var settings: AppSettings { model.settingsStore.settings }

    private func centerItem(at date: Date) -> ExternalCenterItem? {
        let sessions = model.sessions
        return ExternalNotch.item(for: settings.externalNotchCenter, at: date, hasSessions: !sessions.isEmpty,
                                  hasWaiting: sessions.contains { $0.status.isWaiting },
                                  hasStep: latestStep != nil, musicPlaying: model.displayedMusicPlaying && model.nowPlaying != nil)
    }

    /// Jüngste Session mit einem Schritt.
    private var latestStep: (session: AgentSession, step: String)? {
        model.sessions.filter { $0.lastStep != nil }.max { $0.lastActivity < $1.lastActivity }.map { ($0, $0.lastStep ?? "") }
    }

    // MARK: - Teile

    private func clock(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.leading, 18)
    }

    @ViewBuilder
    private var trailing: some View {
        if model.displayedMusicPlaying, model.nowPlaying != nil {
            DancingBars(color: Color(glow: model.artworkGlow), playing: true, maxHeight: max(8, height * 0.45))
                .padding(.trailing, 18)
        } else if !model.sessions.isEmpty {
            Text(model.sessions.count == 1 ? L("1 Session") : L("{0} Sessions", model.sessions.count))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.trailing, 18)
        }
    }

    @ViewBuilder
    private func center(_ item: ExternalCenterItem) -> some View {
        switch item {
        case .agents: agents
        case .lastStep: step
        case .music: music
        }
    }

    /// Ein Punkt je Session (höchstens sechs): pulsierend, wenn sie arbeitet, orange, wenn sie wartet.
    private var agents: some View {
        let sessions = Array(model.sessions.prefix(6))
        let waiting = model.sessions.filter { $0.status.isWaiting }.count
        let working = model.sessions.filter { $0.status == .working }.count
        return HStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(sessions) { session in
                    dot(for: session)
                }
            }
            Text(waiting > 0 ? (waiting == 1 ? L("1 wartet") : L("{0} warten", waiting))
                 : working > 0 ? (working == 1 ? L("1 arbeitet") : L("{0} arbeiten", working)) : L("Alles ruhig"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(waiting > 0 ? Self.waitingColor : Color.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func dot(for session: AgentSession) -> some View {
        let color = SessionPalette.agentColor(session.agent, settings: settings)
        if session.status.isWaiting {
            Circle().fill(Self.waitingColor).frame(width: 7, height: 7).shadow(color: Self.waitingColor, radius: 4)
        } else if session.status == .working {
            PulseDot(color: color).scaleEffect(0.85)
        } else {
            Circle().fill(color.opacity(0.4)).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var step: some View {
        if let latest = latestStep {
            HStack(spacing: 6) {
                Circle().fill(SessionPalette.agentColor(latest.session.agent, settings: settings)).frame(width: 6, height: 6)
                Text(latest.session.agent.displayName + " · " + latest.step)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private var music: some View {
        if let playing = model.nowPlaying {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(glow: model.artworkGlow))
                Text([playing.title, playing.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
        }
    }
}

/// Ruhende Kopie der Notch auf einem Bildschirm, auf dem gerade nicht gearbeitet wird. Nimmt keine Klicks an:
/// Kommt der Zeiger dorthin, wandert die eigentliche Notch auf diesen Bildschirm. Auf einem externen Bildschirm zeigt
/// sie Uhrzeit und Info (`ExternalIdleView`), am MacBook die eingeklappte Musik neben der Kamera, falls sie läuft.
final class ExternalNotchMirror: NSPanel {
    let screenInfo: ScreenInfo

    init(model: AppModel, screen: ScreenInfo) {
        screenInfo = screen
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: NotchMirrorView(model: model, screen: screen))
        let presentation: NotchPresentation = screen.isVirtual ? .externalIdle : .compact
        if let frame = NotchGeometry.frame(for: presentation, screen: screen, islandSideWidth: 0) {
            setFrame(frame, display: false)
        }
    }
}

private struct NotchMirrorView: View {
    let model: AppModel
    let screen: ScreenInfo

    var body: some View {
        let presentation: NotchPresentation = screen.isVirtual ? .externalIdle : .compact
        let notch = NotchGeometry.notchRect(screen) ?? .zero
        let frame = NotchGeometry.frame(for: presentation, screen: screen, islandSideWidth: 0) ?? .zero
        let radii = NotchRootView.radii(for: presentation)
        let shape = NotchShape(bottomRadius: radii.bottom, topCornerRadius: radii.top)
        let sideWidth = max(0, (frame.width - notch.width) / 2)
        Group {
            if screen.isVirtual {
                shape
                    .fill(Color(hex: model.settingsStore.settings.backgroundHex()))
                    .overlay { ExternalIdleView(model: model, notchWidth: notch.width, sideWidth: sideWidth, height: frame.height) }
                    .clipShape(shape)
            } else if model.showsCompactMusic {
                shape
                    .fill(Color(hex: model.settingsStore.settings.backgroundHex()))
                    .overlay { MusicCompactView(model: model, notchWidth: notch.width, sideWidth: sideWidth, ear: radii.top) }
                    .clipShape(shape)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .environment(\.colorScheme, .dark)
    }
}

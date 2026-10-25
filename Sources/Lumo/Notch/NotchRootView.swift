import LumoCore
import SwiftUI

/// Zeichnet die Notch-Form oben mittig im Panel und darin den Inhalt des aktuellen Modus.
struct NotchRootView: View {
    let model: AppModel

    var body: some View {
        let presentation = model.currentPresentation()
        let frame = model.visibleFrame()
        let size = frame?.size ?? .zero
        // Die Form sitzt mittig zur Kamera; eine Systemanzeige ist links schmaler als rechts und rückt so weit,
        // dass ihre Lücke genau unter der Kamera liegt.
        let shift = frame.flatMap { frame in model.screen.flatMap(NotchGeometry.notchRect).map { frame.midX - $0.midX } } ?? 0
        let radii = Self.radii(for: presentation)
        let shape = NotchShape(bottomRadius: radii.bottom, topCornerRadius: radii.top)
        let settings = model.settingsStore.settings
        let signal = model.activeSignal
        let isSignal = if case .signal = model.notch.mode { signal != nil } else { false }
        // Ohne Signal leuchtet sichtbare, laufende Musik in der Coverfarbe, ruhiger als ein Signal.
        let announcement = model.trackAnnouncement
        let musicGlows = !isSignal && settings.musicCoverGlow
            && (model.nowPlaying?.isPlaying == true || announcement != nil)
            && (presentation == .compact || presentation == .trackSides || presentation == .trackBanner
                || model.musicTabOpen)
        // Eine Systemanzeige leuchtet ruhig in ihrer Farbe (Fokus, Timer, Laden …).
        let indicator = model.notch.mode == .idle ? model.systemIndicator : nil
        let hudGlows = indicator != nil && settings.glowEnabled
        let glowColor = isSignal
            ? signal.map { SignalTheme(agentHex: settings.colorHex(for: $0.agent)).agentColor } ?? .clear
            : indicator.map { Color($0.tint) } ?? Color(glow: announcement?.glow ?? model.artworkGlow)
        let spring = NotchSpring(bounce: settings.notchBounce)
        // Aufklappen mit Gummi, Zuklappen ohne Überschwingen (sonst rutschte die Form unter die Hardware-Notch).
        let animation: Animation = model.motion(toward: presentation) == .collapse
            ? .spring(response: spring.collapseResponse, dampingFraction: spring.collapseDampingFraction)
            : .spring(response: spring.response, dampingFraction: spring.dampingFraction)

        // Im Ruhezustand zeichnet die ruhende Kopie darunter; die Form bleibt fast durchsichtig da, damit Hover und
        // Klicks weiter ankommen.
        let mirrored = model.mirrorsDrawIdle && model.notch.mode == .idle && model.idleSettled && announcement == nil && indicator == nil
        shape
            .fill(backgroundColor.opacity(mirrored ? 0.004 : 1))
            .modifier(ClampedFrame(width: size.width, height: size.height, minimum: model.notchSize))
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    musicBackdrop(size: size)
                    if !mirrored { content(width: size.width, height: size.height) }
                }
                .animation(.easeInOut(duration: 0.28), value: MusicBackdrop.isShown(for: model))
            }
            .overlay(alignment: .top) { privacyDots(width: size.width) }
            .clipShape(shape)
            .background {
                // Während der Einrichtung leuchtet die Notch in wechselnden Farben, bis sie fertig ist.
                let setupGlows = model.setupGlow && !isSignal
                NotchGlow(shape: shape, color: glowColor, intensity: setupGlows ? 0.8 : settings.glowIntensity,
                          enabled: (settings.glowEnabled && isSignal) || musicGlows || setupGlows || hudGlows,
                          cycle: isSignal || setupGlows ? GlowPulse.cycle : GlowPulse.musicCycle,
                          rainbow: setupGlows && !musicGlows)
            }
            .offset(x: shift)
            .animation(animation, value: presentation)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            // Neue Sprache: alles neu aufbauen, damit jeder Text sie zeigt.
            .id(settings.language)
    }

    /// Im Reiter „Musik“: das Cover verschwommen als Hintergrund (Einstellung `musicArtworkBackground`).
    @ViewBuilder
    private func musicBackdrop(size: CGSize) -> some View {
        if MusicBackdrop.isShown(for: model), let artwork = model.artwork {
            MusicBackdrop(image: artwork, track: model.artworkTrack, bandHeight: model.screen?.topInset ?? 32)
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        }
    }

    /// Mikrofon und Kamera in Benutzung: Punkte am rechten Rand der Kamera-Aussparung, solange die Notch zu ist.
    @ViewBuilder
    private func privacyDots(width: CGFloat) -> some View {
        if model.notch.mode == .idle, model.microphoneInUse || model.cameraInUse,
           let notch = model.screen.flatMap(NotchGeometry.notchRect) {
            PrivacyDots(microphone: model.microphoneInUse, camera: model.cameraInUse)
                .frame(width: notch.width, height: notch.height, alignment: .trailing)
                .padding(.trailing, 9)
                .frame(width: width, alignment: .center)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: model.microphoneInUse)
                .animation(.easeInOut(duration: 0.3), value: model.cameraInUse)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        switch model.notch.mode {
        case .panel(let tab):
            panelContent(tab: tab, width: width)
        case .signal(let style):
            if let signal = model.activeSignal {
                signalContent(signal, style: style, width: width)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            }
        case .idle:
            let notch = model.screen.flatMap(NotchGeometry.notchRect)
            let notchWidth = notch?.width ?? 0
            let presentation = model.currentPresentation()
            if let indicator = model.systemIndicator, case .hud(let left, let right) = presentation {
                SystemIndicatorView(indicator: indicator, notchWidth: notchWidth, leftWidth: left, rightWidth: right,
                                    height: height, ear: Self.radii(for: presentation).top)
                    .id(indicator.id)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            } else if let announcement = model.trackAnnouncement, presentation == .trackSides {
                TrackChangeSidesView(model: model, announcement: announcement, notchWidth: notchWidth,
                                     sideWidth: max(0, (width - notchWidth) / 2), height: height,
                                     ear: Self.radii(for: .trackSides).top)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            } else if let announcement = model.trackAnnouncement, presentation == .trackBanner {
                TrackChangeBannerView(model: model, announcement: announcement, bandHeight: notch?.height ?? 0)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            } else if presentation == .externalIdle {
                ExternalIdleView(model: model, notchWidth: notchWidth, sideWidth: max(0, (width - notchWidth) / 2),
                                 height: height)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            } else if presentation == .compact {
                MusicCompactView(model: model, notchWidth: notchWidth, sideWidth: max(0, (width - notchWidth) / 2),
                                 ear: Self.radii(for: .compact).top)
                    .frame(width: width, height: height)
                    .transition(.notchContent)
            }
        }
    }

    @ViewBuilder
    private func signalContent(_ signal: SignalContent, style: SignalStyle, width: CGFloat) -> some View {
        let theme = SignalTheme(agentHex: model.settingsStore.settings.colorHex(for: signal.agent))
        // Knöpfe und Antwortfeld meinen genau dieses Signal; ist es inzwischen ersetzt, verfällt der Klick.
        let id = signal.id
        let act: (SignalAction) -> Void = { model.performSignalAction($0, for: id) }
        let draft = Binding(get: { model.draft(for: id) }, set: { model.setDraft($0, for: id) })
        let choices = SignalChoices(selection: model.selection(for: id), toggle: { model.toggleOption($0, for: id) },
                                    submit: { model.submitSelection(for: id) })
        let notch = model.screen.flatMap(NotchGeometry.notchRect)
        let notchWidth = notch?.width ?? 0
        switch style {
        case .island:
            SignalIslandView(content: signal, theme: theme, notchWidth: notchWidth,
                             sideWidth: max(0, (width - notchWidth) / 2),
                             act: act, expand: { model.send(.islandClicked) },
                             reportButtonArea: { model.islandButtonArea = $0 })
        case .banner:
            SignalBannerView(content: signal, theme: theme, notchWidth: notchWidth,
                             bandHeight: notch?.height ?? 0, draft: draft, choices: choices,
                             showFull: { model.showFullRequest() }, act: act)
        case .vertical:
            SignalVerticalView(content: signal, theme: theme, notchHeight: notch?.height ?? 32, draft: draft,
                               choices: choices, showFull: { model.showFullRequest() }, act: act)
        }
    }

    private func panelContent(tab: PanelTab, width: CGFloat) -> some View {
        // Im Reiter „Musik“ steht oben rechts der Player (Symbol und Name), sonst der Name des Reiters.
        let player = tab == .music ? model.nowPlaying?.source.name : nil
        return VStack(spacing: 0) {
            PanelTabBar(selection: Binding(get: { tab }, set: { model.send(.tabSelected($0)) }),
                        label: player, icon: player == nil ? nil : model.musicAppIcon)
                // Die Reiter sitzen im Band neben der Kamera, der Inhalt beginnt darunter.
                .frame(height: max(model.screen?.topInset ?? 0, 34))
                .padding(.horizontal, 10)
            // Im ZStack überblenden alter und neuer Reiter an derselben Stelle.
            ZStack(alignment: .top) {
                switch tab {
                case .music:
                    // Ränder regelt der Reiter selbst.
                    MusicPanelView(model: model)
                case .sessions:
                    SessionListView(model: model)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                case .office:
                    OfficeTabView(model: model)
                case .shelf:
                    ShelfTabView(model: model)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                case .notes:
                    NotesTabView(model: model)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                }
            }
            .id(tab)
            .transition(.blurFade)
        }
        // Alle Ränder zählen ab dem Körper, ohne die oberen Wölbungen.
        .padding(.horizontal, NotchGeometry.panelEar)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.setPanelContentHeight($0, for: tab) }
        .animation(.easeInOut(duration: 0.25), value: tab)
        .transition(.notchContent)
    }

    private var backgroundColor: Color {
        Color(hex: model.settingsStore.settings.backgroundHex())
    }

    /// Im Ruhezustand ohne Wölbung, damit nichts über die Hardware-Notch hinausragt.
    static func radii(for presentation: NotchPresentation) -> (top: CGFloat, bottom: CGFloat) {
        switch presentation {
        case .idle: (0, 10)
        case .externalIdle: (5, 11)
        case .island: (6, 14)
        case .compact: (6, 12)
        case .trackSides: (6, 14)
        case .hud: (NotchGeometry.hudEar, 14)
        case .trackBanner: (10, 26)
        case .banner: (10, 30)
        case .vertical, .verticalCompact: (10, 24)
        // Oben je Seite eine kleine Wölbung in den Bildschirmrand, unten 22 pt rund.
        case .panel: (NotchGeometry.panelEar, 22)
        }
    }
}

import AppKit
import LumoCore
import SwiftUI

/// Reiter „Musik“: alles in einer Zeile. Links das Cover (76 pt),
/// daneben Titel mit kleinen Balken, Interpret, Fortschritt zum Spulen und die Zeiten, rechts Zurück,
/// Play/Pause und Weiter. Den Namen des Players zeigt die Reiterleiste oben rechts.
struct MusicPanelView: View {
    let model: AppModel

    /// Maße aus dem Video (pt).
    static let artworkSize: CGFloat = 76
    static let artworkRadius: CGFloat = 13

    var body: some View {
        if let item = model.nowPlaying {
            player(item)
        } else {
            nothingPlaying
        }
    }

    private func player(_ item: NowPlaying) -> some View {
        let playing = model.displayedMusicPlaying
        return HStack(alignment: .center, spacing: 0) {
            TrackArtwork(model: model, size: Self.artworkSize)
            VStack(alignment: .leading, spacing: 0) {
                // Im ZStack gleiten alter und neuer Titel an derselben Stelle ineinander.
                ZStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 7) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .layoutPriority(1)
                            DancingBars(color: Color.white, playing: playing, count: 4, barWidth: 2.4, spacing: 1.8,
                                        maxHeight: 11, minHeight: 3, levels: model.musicLevels)
                                .opacity(playing ? 1 : 0)
                                .animation(.easeInOut(duration: 0.3), value: playing)
                        }
                        if let artist = item.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                    .lineLimit(1)
                    .id(item.title)
                    .transition(.trackText(model.skipDirection))
                }
                .animation(.easeInOut(duration: 0.35), value: item.title)
                Spacer(minLength: 0)
                if item.elapsed != nil || item.duration != nil {
                    ScrubBar(model: model, item: item)
                }
            }
            .frame(height: Self.artworkSize)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.trailing, 13)
            HStack(spacing: 0) {
                SkipButton(direction: .backward) { model.sendMusicCommand(.previous) }
                PlayPauseButton(playing: playing) { model.sendMusicCommand(.playPause) }
                SkipButton(direction: .forward) { model.sendMusicCommand(.next) }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 23)
    }

    private var nothingPlaying: some View {
        let settings = model.settingsStore.settings
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: Self.artworkRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(PanelTabBar.gray.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Gerade läuft nichts"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(settings.musicEnabled ? settings.musicSourceMode.label : L("Musikanzeige ist aus"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 23)
    }
}

/// Cover; wechselt beim Titelwechsel weich oder klappt in Skip-Richtung um (Einstellung).
private struct TrackArtwork: View {
    let model: AppModel
    let size: CGFloat

    var body: some View {
        let flips = model.settingsStore.settings.musicCoverTransition == .flip
        let radius = MusicPanelView.artworkRadius
        ZStack {
            MusicArtwork(image: model.artwork, appIcon: model.musicAppIcon, size: size, cornerRadius: radius)
                // Feiner heller Rand.
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                )
                .id(model.artworkTrack ?? "")
                .transition(flips ? .coverFlip(model.skipDirection) : .coverBlur)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.4), value: model.artworkTrack)
    }
}

/// Fortschritt: dünner Balken, darunter verstrichene Zeit und Restzeit. Mit der Maus lässt sich
/// spulen; unter dem Zeiger wird der Balken dicker, beim Ziehen laufen die Zeiten mit.
private struct ScrubBar: View {
    let model: AppModel
    let item: NowPlaying

    @ViewState private var dragFraction: Double? = nil
    @ViewState private var hovering = false

    /// Höhe der Fläche, die auf die Maus reagiert; der Balken selbst ist schmaler.
    private static let hitHeight: CGFloat = 14

    var body: some View {
        let duration = item.duration ?? 0
        let canSeek = duration > 0
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !item.isPlaying && dragFraction == nil)) { timeline in
            let position = dragFraction.map { MusicScrub.position(fraction: $0, duration: duration) }
                ?? model.displayedPosition(of: item, at: timeline.date) ?? 0
            let fraction = canSeek ? min(max(position / duration, 0), 1) : 0
            VStack(spacing: 3) {
                GeometryReader { geometry in
                    let thickness = self.thickness
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(isActive ? 0.28 : 0.2))
                        Capsule()
                            .fill(Color.white.opacity(isActive ? 0.95 : 0.82))
                            .frame(width: max(thickness, geometry.size.width * CGFloat(fraction)))
                    }
                    .frame(height: thickness)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek, geometry.size.width > 0 else { return }
                            if dragFraction == nil { model.isScrubbing = true }
                            dragFraction = Double(value.location.x / geometry.size.width)
                        }
                        .onEnded { value in
                            defer {
                                dragFraction = nil
                                model.isScrubbing = false
                            }
                            guard canSeek, geometry.size.width > 0 else { return }
                            let target = Double(value.location.x / geometry.size.width)
                            model.seekMusic(to: MusicScrub.position(fraction: target, duration: duration))
                        })
                    .onHover { inside in hovering = inside && canSeek }
                }
                .frame(height: Self.hitHeight)
                HStack {
                    Text(MusicTime.format(position))
                    Spacer(minLength: 8)
                    if canSeek { Text(MusicTime.remaining(position: position, duration: duration)) }
                }
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.42))
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: thickness)
        }
    }

    private var isActive: Bool { hovering || dragFraction != nil }

    private var thickness: CGFloat {
        if dragFraction != nil { return 6 }
        return hovering ? 5 : 3
    }
}

/// Hintergrund des Reiters „Musik“: das Cover stark verschwommen und deutlich abgedunkelt, zu den
/// Rändern hin dunkler. Oben läuft es zur Kamera hin ins Schwarz aus.
struct MusicBackdrop: View {
    let image: NSImage
    let track: String?
    /// Höhe des Bands neben der Kamera.
    let bandHeight: CGFloat

    static func isShown(for model: AppModel) -> Bool {
        model.musicTabOpen && model.settingsStore.settings.musicArtworkBackground
            && model.nowPlaying != nil && model.artwork != nil
    }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.6)
                .blur(radius: 50, opaque: true)
                .saturation(1.1)
                .overlay(Color.black.opacity(0.4))
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.05), Color.black.opacity(0.35)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .id(track ?? "")
                .transition(.opacity)
        }
        .clipped()
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.35), Color.black], startPoint: .top, endPoint: .bottom)
                    .frame(height: bandHeight + 12)
                Color.black
            }
        }
        .animation(.easeInOut(duration: 0.6), value: track)
    }
}

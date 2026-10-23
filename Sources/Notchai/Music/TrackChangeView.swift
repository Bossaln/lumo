import AppKit
import NotchaiCore
import SwiftUI

/// Ein neuer Titel, den die Notch kurz zeigt. Hält Cover und Texte selbst fest, damit die Anzeige stehen bleibt,
/// auch wenn währenddessen schon die nächste Meldung kommt.
struct TrackAnnouncement {
    let style: TrackChangeStyle
    let title: String
    let artist: String?
    let artwork: NSImage?
    let appIcon: NSImage?
    let glow: RGB?
}

/// Neuer Titel, seitlich: links neben der Kamera das Cover und die Balken, rechts Titel und Interpret.
struct TrackChangeSidesView: View {
    let model: AppModel
    let announcement: TrackAnnouncement
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat
    /// Breite der oberen Wölbung je Seite.
    let ear: CGFloat

    var body: some View {
        let inner = max(0, sideWidth - ear)
        let cover = min(24, max(16, height - 10))
        HStack(spacing: 0) {
            Color.clear.frame(width: ear)
            HStack(spacing: 0) {
                MusicArtwork(image: announcement.artwork, appIcon: announcement.appIcon, size: cover, cornerRadius: 6)
                Spacer(minLength: 8)
                DancingBars(color: Color(glow: announcement.glow), playing: model.displayedMusicPlaying,
                            levels: model.musicLevels)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(width: inner)
            Color.clear.frame(width: notchWidth)
            VStack(alignment: .leading, spacing: 0) {
                Text(announcement.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                if let artist = announcement.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(PanelTabBar.gray)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(width: inner, alignment: .leading)
            Color.clear.frame(width: ear)
        }
    }
}

/// Neuer Titel, ausgefahren: unter der Kamera ein großes Cover, Titel, Interpret und rechts die Balken.
struct TrackChangeBannerView: View {
    let model: AppModel
    let announcement: TrackAnnouncement
    let bandHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: bandHeight)
            HStack(spacing: 12) {
                MusicArtwork(image: announcement.artwork, appIcon: announcement.appIcon, size: 50, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Neuer Titel"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelTabBar.gray)
                    Text(announcement.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                    if let artist = announcement.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                DancingBars(color: Color(glow: announcement.glow), playing: model.displayedMusicPlaying, count: 4,
                            levels: model.musicLevels)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }
}

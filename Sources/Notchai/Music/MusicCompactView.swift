import NotchaiCore
import SwiftUI

/// Musik eingeklappt wie auf dem iPhone: links neben der Kamera das Cover, rechts die tanzenden Balken.
/// Beide sitzen mittig in ihrer Seite, gemessen ab dem Körper der Form (ohne die oberen Wölbungen).
struct MusicCompactView: View {
    let model: AppModel
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    /// Breite der oberen Wölbung je Seite (`topCornerRadius` der eingeklappten Form).
    let ear: CGFloat

    var body: some View {
        let inner = max(0, sideWidth - ear)
        HStack(spacing: 0) {
            Color.clear.frame(width: ear)
            ZStack {
                MusicArtwork(image: model.artwork, appIcon: model.musicAppIcon, size: 22, cornerRadius: 6)
                    .id(model.artworkTrack ?? "")
                    .transition(.opacity)
            }
            .frame(width: inner)
            .animation(.easeInOut(duration: 0.3), value: model.artworkTrack)
            Color.clear.frame(width: notchWidth)
            DancingBars(color: Color(glow: model.artworkGlow), playing: model.displayedMusicPlaying)
                .frame(width: inner)
            Color.clear.frame(width: ear)
        }
    }
}

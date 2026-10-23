import AppKit
import NotchaiCore
import SwiftUI

/// Tanzende Balken wie auf dem iPhone: drei in der eingeklappten Notch, vier kleine neben dem Titel.
/// Mit `levels` folgen sie dem echten Ton (`MusicVisualizer`); ohne echten Ton tanzen sie von selbst.
/// Ist der Titel pausiert, stehen sie still (und es wird nichts neu gezeichnet).
struct DancingBars: View {
    let color: Color
    let playing: Bool
    var count = 3
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5
    var maxHeight: CGFloat = 14
    var minHeight: CGFloat = 3
    /// Höhen aus dem echten Ton für `count` Balken zur Zeit des Bildes; `nil` = keine.
    var levels: ((Int, TimeInterval) -> [Double]?)? = nil

    private static let speeds: [Double] = [7.1, 9.3, 5.7, 8.2]
    private static let phases: [Double] = [0, 1.9, 3.7, 5.3]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let real = playing ? levels?(count, time) : nil
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: real.map { height(level: $0[index]) } ?? height(index, at: time))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(level: Double) -> CGFloat {
        minHeight + (maxHeight - minHeight) * CGFloat(min(max(level, 0), 1))
    }

    /// Zwei überlagerte Schwingungen je Balken, damit es nicht nach Gleichtakt aussieht.
    private func height(_ index: Int, at time: TimeInterval) -> CGFloat {
        guard playing else { return minHeight + 1 }
        let speed = Self.speeds[index % Self.speeds.count], phase = Self.phases[index % Self.phases.count]
        let a = sin(time * speed + phase)
        let b = sin(time * speed * 0.53 + phase * 2)
        let level = 0.5 + 0.3 * a + 0.2 * b
        return minHeight + (maxHeight - minHeight) * CGFloat(level)
    }
}

/// Cover mit abgerundeten Ecken; ohne Cover das Symbol der App, sonst eine Note.
struct MusicArtwork: View {
    let image: NSImage?
    let appIcon: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(PanelTabBar.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension Color {
    /// Leuchtfarbe des Covers; ohne Farbe ein ruhiges Weiß.
    init(glow: RGB?) {
        if let glow {
            self.init(.sRGB, red: glow.r, green: glow.g, blue: glow.b)
        } else {
            self = .white
        }
    }
}

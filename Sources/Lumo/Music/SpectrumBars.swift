import LumoCore
import SwiftUI

/// Visualizer mit vielen schmalen Balken, die von unten wachsen, tief links, hoch rechts. Über jedem Balken schwebt
/// seine Spitze und sinkt langsam nach. Mit `spectrum` folgt er dem echten Ton (`MusicVisualizer`, gemeinsam
/// eingepegelt); ohne echten Ton wogt er von selbst. Pausiert steht er still.
struct SpectrumBars: View {
    let color: Color
    let playing: Bool
    var count = 24
    var spacing: CGFloat = 1.6
    /// Höhen und Spitzen aus dem echten Ton für `count` Balken zur Zeit des Bildes; `nil` = keine.
    var spectrum: ((Int, TimeInterval) -> MusicVisualizer.Spectrum?)? = nil

    /// Abstand der Spitze über dem Balken und ihre Höhe.
    private static let capGap: CGFloat = 1.5
    private static let capHeight: CGFloat = 1.5
    private static let minLevel = 0.06

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let barWidth = max(1, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let real = playing ? spectrum?(count, time) : nil
                Canvas { context, canvasSize in
                    let room = canvasSize.height - Self.capGap - Self.capHeight
                    for index in 0..<count {
                        let level = real.map { $0.levels[index] } ?? Self.wave(index, of: count, at: time, playing: playing)
                        let height = room * CGFloat(max(level, Self.minLevel))
                        let x = CGFloat(index) * (barWidth + spacing)
                        let bar = CGRect(x: x, y: canvasSize.height - height, width: barWidth, height: height)
                        // Höhere Balken leuchten kräftiger.
                        context.fill(Path(roundedRect: bar, cornerRadius: min(barWidth / 2, 1.2)),
                                     with: .color(color.opacity(0.55 + 0.45 * level)))
                        if let peak = real?.peaks[index], peak > level + 0.02 {
                            let y = canvasSize.height - room * CGFloat(peak) - Self.capGap - Self.capHeight
                            let cap = CGRect(x: x, y: y, width: barWidth, height: Self.capHeight)
                            context.fill(Path(roundedRect: cap, cornerRadius: 0.6), with: .color(Color.white.opacity(0.85)))
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    /// Ohne echten Ton: ruhige Wellen, links (Bass) höher als rechts, jeder Balken in seinem eigenen Takt.
    private static func wave(_ index: Int, of count: Int, at time: TimeInterval, playing: Bool) -> Double {
        guard playing else { return minLevel }
        let position = Double(index) / Double(max(count - 1, 1))
        let speed = 3.1 + Double((index * 7) % 11) * 0.45
        let phase = Double(index) * 1.7
        let wave = 0.5 + 0.3 * sin(time * speed + phase) + 0.2 * sin(time * speed * 0.47 + phase * 2.3)
        return min(max(wave * (1 - 0.45 * position), 0), 1)
    }
}

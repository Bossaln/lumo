import LumoCore
import SwiftUI

/// Knopfstil der Musiksteuerung: Beim Drücken schrumpft das Symbol, dahinter erscheint ein heller Kreis.
struct NotchControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0)))
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Dezenter Kreis unter dem Zeiger, wie bei den Knöpfen im Kontrollzentrum.
private struct HoverCircle: ViewModifier {
    @ViewState private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
            }
    }
}

/// Zurück bzw. Weiter wie in Apple Music: Das vordere Dreieck gleitet hinaus und verblasst, das hintere
/// rückt nach, und hinten wächst ein neues heran.
struct SkipButton: View {
    let direction: SkipDirection
    let action: () -> Void

    @ViewState private var phase: CGFloat = 0

    var body: some View {
        Button {
            action()
            play()
        } label: {
            SkipGlyph(phase: phase)
                .scaleEffect(x: direction == .forward ? 1 : -1, y: 1)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .modifier(HoverCircle())
        }
        .buttonStyle(NotchControlButtonStyle())
        .frame(width: 40, height: 40)
        .accessibilityLabel(direction == .forward ? L("Nächster Titel") : L("Vorheriger Titel"))
    }

    private func play() {
        // Ende und Anfang sehen gleich aus; deshalb springt der Zähler danach unbemerkt zurück.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { phase = 0 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            phase = 1
        } completion: {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { phase = 0 }
        }
    }
}

/// Zwei aneinanderstoßende Dreiecke; `phase` 0…1 schiebt sie um eine Dreiecksbreite nach vorn.
private struct SkipGlyph: View {
    var phase: CGFloat

    /// Zusammen 19 × 11 pt.
    private static let width: CGFloat = 9.5
    private static let height: CGFloat = 11

    var body: some View {
        let w = Self.width
        ZStack(alignment: .leading) {
            // Neues Dreieck wächst hinten heran.
            triangle
                .scaleEffect(max(phase, 0.001))
                .opacity(Double(phase))
            // Hinteres rückt nach vorn.
            triangle
                .offset(x: w * phase)
            // Vorderes gleitet hinaus und verschwindet.
            triangle
                .scaleEffect(max(1 - phase, 0.001))
                .opacity(Double(1 - phase))
                .offset(x: w + w * 0.7 * phase)
        }
        .frame(width: 2 * w, height: Self.height, alignment: .leading)
    }

    private var triangle: some View {
        let shape = Triangle()
        return shape
            .fill(Color.white)
            .overlay(shape.stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
            .frame(width: Self.width, height: Self.height)
    }
}

/// Nach rechts zeigendes Dreieck.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Play/Pause: Das Dreieck teilt sich und wird fließend zu zwei Balken (und zurück).
struct PlayPauseButton: View {
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let shape = PlayPauseShape(progress: playing ? 1 : 0)
            shape
                .fill(Color.white)
                .overlay(shape.stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
                // Pause 14 × 17 pt.
                .frame(width: 14, height: 17)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .modifier(HoverCircle())
        }
        .buttonStyle(NotchControlButtonStyle())
        .frame(width: 40, height: 40)
        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: playing)
        .accessibilityLabel(playing ? L("Pause") : L("Abspielen"))
    }
}

private struct PlayPauseShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for polygon in PlayPauseGeometry.polygons(progress: progress) {
            p.addLines(polygon.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
            p.closeSubpath()
        }
        return p
    }
}

import LumoCore
import SwiftUI

/// Weich, unscharf und leicht verkleinert: so blendet die Dynamic Island Inhalte ein und aus.
private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

/// Klappt das Cover um die senkrechte Achse; hinter 90° ist es unsichtbar (Rückseite).
private struct CoverFlip: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(abs(angle) < 89.5 ? 1 : 0)
    }
}

/// Weich, unscharf und seitlich verschoben: Titel und Interpret beim Titelwechsel.
private struct SlideBlur: ViewModifier {
    let offset: CGFloat
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: radius)
            .opacity(opacity)
    }
}

/// Rahmen der Notch-Form, der nie kleiner als die Hardware-Notch wird – auch nicht, wenn die Feder mitten in
/// der Animation unter ihr Ziel schwingt. Sonst rutschte die Form kurz unter die echte Notch.
struct ClampedFrame: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat
    let minimum: CGSize?

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let size = NotchMotion.clamped(CGSize(width: width, height: height), notch: minimum)
        content.frame(width: size.width, height: size.height)
    }
}

extension AnyTransition {
    /// Inhalt der Notch (Panel, eingeklappte Musik, Signale): Beim Aufklappen erscheint er
    /// unscharf, wenn die Form schon fast offen ist; beim Zuklappen ist er sofort weg, bevor die Form schrumpft.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(radius: 10, opacity: 0, scale: 0.96),
                                 identity: BlurFade(radius: 0, opacity: 1, scale: 1))
                .animation(.easeOut(duration: 0.3).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.08))
        )
    }

    /// Cover beim Titelwechsel: altes verschwimmt, neues wird scharf.
    static var coverBlur: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(radius: 12, opacity: 0, scale: 1.04),
                                 identity: BlurFade(radius: 0, opacity: 1, scale: 1))
                .animation(.easeOut(duration: 0.32).delay(0.06)),
            removal: .modifier(active: BlurFade(radius: 12, opacity: 0, scale: 0.97),
                               identity: BlurFade(radius: 0, opacity: 1, scale: 1))
                .animation(.easeIn(duration: 0.18))
        )
    }

    /// Titel und Interpret beim Titelwechsel: gleiten unscharf in Skip-Richtung.
    static func trackText(_ direction: SkipDirection) -> AnyTransition {
        let sign: CGFloat = direction == .forward ? 1 : -1
        return .asymmetric(
            insertion: .modifier(active: SlideBlur(offset: 10 * sign, radius: 6, opacity: 0),
                                 identity: SlideBlur(offset: 0, radius: 0, opacity: 1))
                .animation(.easeOut(duration: 0.34).delay(0.05)),
            removal: .modifier(active: SlideBlur(offset: -10 * sign, radius: 6, opacity: 0),
                               identity: SlideBlur(offset: 0, radius: 0, opacity: 1))
                .animation(.easeIn(duration: 0.18))
        )
    }

    /// Texte, die beim Titelwechsel weich überblenden.
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(radius: 5, opacity: 0, scale: 1),
                  identity: BlurFade(radius: 0, opacity: 1, scale: 1))
    }

    /// Das alte Cover klappt in Skip-Richtung weg, danach klappt das neue herein.
    static func coverFlip(_ direction: SkipDirection) -> AnyTransition {
        let sign: Double = direction == .forward ? -1 : 1
        return .asymmetric(
            insertion: .modifier(active: CoverFlip(angle: -90 * sign), identity: CoverFlip(angle: 0))
                .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(0.2)),
            removal: .modifier(active: CoverFlip(angle: 90 * sign), identity: CoverFlip(angle: 0))
                .animation(.easeIn(duration: 0.2))
        )
    }
}

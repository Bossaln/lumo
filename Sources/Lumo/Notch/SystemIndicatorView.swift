import AppKit
import LumoCore
import SwiftUI

/// Systemanzeige im Stil der Dynamic Island: links neben der Kamera das Symbol in seiner Farbe, rechts ein Balken
/// (Lautstärke, Helligkeit, Batterie), ein Text (Fokus, Gerät) oder die Restzeit (Timer).
struct SystemIndicatorView: View {
    let indicator: SystemIndicator
    let notchWidth: CGFloat
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let height: CGFloat
    /// Breite der oberen Wölbung je Seite.
    let ear: CGFloat
    @ViewState private var dimmed = false

    private static let symbolFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let textFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)

    /// Breite des Inhalts rechts, damit die Insel genau so breit wird wie nötig.
    static func contentWidth(of indicator: SystemIndicator) -> CGFloat {
        switch indicator.value {
        case .level: NotchGeometry.hudBarWidth
        case .text(let text): ceil(measure(text, font: textFont))
        case .countdown(let until): ceil(measure(SystemIndicatorFormat.countdown(max(until.timeIntervalSinceNow, 0)), font: digitFont))
        case .remaining(let seconds): ceil(measure(SystemIndicatorFormat.countdown(seconds), font: digitFont))
        }
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        let tint = Color(indicator.tint)
        let leftInner = max(0, leftWidth - ear), rightInner = max(0, rightWidth - ear)
        HStack(spacing: 0) {
            Color.clear.frame(width: ear)
            // Symbol mittig zwischen Außenkante und Kamera; rechts der Inhalt ebenso, mit demselben Rand.
            Image(systemName: indicator.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: leftInner)
            Color.clear.frame(width: notchWidth)
            trailing(tint: tint)
                .frame(width: max(0, rightInner - 2 * NotchGeometry.hudPadding))
                .frame(width: rightInner)
            Color.clear.frame(width: ear)
        }
        .frame(height: height)
        .opacity(indicator.pulses && dimmed ? 0.35 : 1)
        .onAppear { startPulse() }
        .onChange(of: indicator.pulses) { startPulse() }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func trailing(tint: Color) -> some View {
        switch indicator.value {
        case .level(let level):
            LevelBar(level: level, tint: tint)
        case .text(let text):
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
        case .countdown(let until):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(SystemIndicatorFormat.countdown(until.timeIntervalSince(context.date)))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
        case .remaining(let seconds):
            Text(SystemIndicatorFormat.countdown(seconds))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func startPulse() {
        dimmed = false
        guard indicator.pulses else { return }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dimmed = true }
    }

    /// Timer und Wecker öffnen die Uhr-App, wo sie sich beenden lassen.
    private func open() {
        guard indicator.kind == .timer || indicator.kind == .alarm,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private var accessibilityText: String {
        switch indicator.value {
        case .level(let level): "\(indicator.kind.title) \(SystemIndicatorFormat.percent(level))"
        case .text(let text): "\(indicator.kind.title): \(text)"
        case .countdown(let until): "\(indicator.kind.title) \(SystemIndicatorFormat.countdown(until.timeIntervalSinceNow))"
        case .remaining(let seconds): "\(indicator.kind.title) \(SystemIndicatorFormat.countdown(seconds))"
        }
    }
}

/// Balken 0…1: dunkle Spur, Füllung in der Farbe der Anzeige, weich zum neuen Wert.
struct LevelBar: View {
    let level: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(0, proxy.size.width * min(max(level, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
    }
}

/// Mikrofon und Kamera in Benutzung: wie auf dem iPhone ein oranger bzw. grüner Punkt am rechten Rand der Notch.
struct PrivacyDots: View {
    let microphone: Bool
    let camera: Bool

    var body: some View {
        HStack(spacing: 4) {
            if microphone { dot(Color(SystemTint.orange)) }
            if camera { dot(Color(SystemTint.green)) }
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: 3)
            .transition(.opacity.combined(with: .scale))
    }
}

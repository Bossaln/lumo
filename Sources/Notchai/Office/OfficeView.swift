import AppKit
import NotchaiCore
import SwiftUI

/// Die Lagerhalle: Pixelbild (scharf vergrößert), weiches Licht, Namensschilder und Sprechblasen
/// als scharfe SwiftUI-Elemente. Hover zeigt eine Karte zur Session, ein Klick holt ihr Fenster nach vorn.
struct OfficeView: View {
    let director: OfficeDirector
    /// Kleine Ansicht im Reiter „Büro“: kleinere Schilder, keine Karte.
    var compact = false
    /// Klick auf eine freie Stelle (im Reiter: großes Büro öffnen).
    var onBackgroundTap: (() -> Void)? = nil

    @ViewState private var hoveredID: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(OfficeLayout.width), geometry.size.height / CGFloat(OfficeLayout.height))
            let size = CGSize(width: CGFloat(OfficeLayout.width) * scale, height: CGFloat(OfficeLayout.height) * scale)
            ZStack(alignment: .topLeading) {
                if let frame = director.frame {
                    Image(decorative: frame, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
                OfficeLightOverlay(director: director, scale: scale)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                ForEach(director.agents.filter { $0.activity != .leaving }) { agent in
                    label(for: agent, scale: scale)
                }
                if director.frame != nil, director.agents.isEmpty {
                    Text("Noch ist niemand da. Starte Claude Code oder Codex.")
                        .font(.system(size: compact ? 9 : 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, compact ? 7 : 11)
                        .padding(.vertical, compact ? 3 : 5)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .position(x: size.width / 2, y: size.height * 0.62)
                        .allowsHitTesting(false)
                }
                if !compact, let id = hoveredID, let agent = director.agents.first(where: { $0.id == id }) {
                    OfficeHoverCard(agent: agent, color: color(for: agent.agent))
                        .position(x: min(max(agent.position.x * scale, 120), size.width - 120),
                                  y: max(agent.headTop(now: director.now) * scale - 64, 54))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .compositingGroup()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredID = agent(at: location, scale: scale)?.id
                case .ended: hoveredID = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if let agent = agent(at: value.location, scale: scale) {
                    director.focus(agent)
                } else {
                    onBackgroundTap?()
                }
            })
            .animation(.easeInOut(duration: 0.15), value: hoveredID)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .onAppear { director.attach() }
        .onDisappear { director.detach() }
    }

    private func color(for agent: AgentKind) -> Color {
        Color(hex: director.settings.colorHex(for: agent))
    }

    /// Figur unter dem Zeiger (Fläche vom Kopf bis zu den Füßen).
    private func agent(at location: CGPoint, scale: CGFloat) -> OfficeAgent? {
        let x = location.x / scale, y = location.y / scale
        return director.agents.last { agent in
            agent.activity != .leaving && abs(agent.position.x - x) <= 7
                && y >= agent.headTop(now: director.now) - 2 && y <= agent.position.y + 1
        }
    }

    /// Namensschild über dem Kopf, darüber eine Sprechblase (wartet, Fehler, schläft, Spruch).
    private func label(for agent: OfficeAgent, scale: CGFloat) -> some View {
        let top = agent.headTop(now: director.now) * scale
        return VStack(spacing: 3) {
            if let bubble = bubbleText(agent) {
                OfficeSpeechBubble(text: bubble.text, tint: bubble.tint, compact: compact)
            }
            HStack(spacing: 3) {
                AgentBadge(agent: agent.agent, color: color(for: agent.agent))
                    .scaleEffect(compact ? 0.7 : 0.85)
                    .frame(width: compact ? 9 : 11, height: compact ? 7 : 9)
                Text(agent.session.projectName)
                    .font(.system(size: compact ? 7.5 : 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1.5 : 2.5)
            .background(Capsule().fill(Color.black.opacity(0.62)))
        }
        .fixedSize()
        .position(x: agent.position.x * scale, y: top - (compact ? 9 : 14) - (bubbleText(agent) == nil ? 0 : (compact ? 8 : 12)))
        .allowsHitTesting(false)
    }

    private func bubbleText(_ agent: OfficeAgent) -> (text: String, tint: Color)? {
        switch agent.bubble {
        case .waiting: return ("Braucht dich!", Color(hex: "#FFC53D"))
        case .error: return ("Fehler!", Color(hex: "#FF4D5E"))
        case .sleeping: return ("Zzz", Color.white)
        case nil:
            return OfficeChatter.line(for: agent, now: director.now).map { ($0, Color.white) }
        }
    }
}

/// Sprechblase: weiß (oder in Signalfarbe) mit dunkler Schrift.
private struct OfficeSpeechBubble: View {
    let text: String
    let tint: Color
    let compact: Bool

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 7.5 : 10.5, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, compact ? 4 : 7)
            .padding(.vertical, compact ? 1.5 : 3)
            .background(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous).fill(tint))
            .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
    }
}

/// Karte beim Darüberfahren: Agent, Status, Titel, letzter Schritt.
private struct OfficeHoverCard: View {
    let agent: OfficeAgent
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                AgentBadge(agent: agent.agent, color: color)
                Text("\(agent.agent.displayName) · \(status)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            Text(agent.session.title)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(2)
            if let step = agent.session.lastStep {
                Text(step)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Text("Klicken: Fenster nach vorn holen")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(9)
        .frame(width: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var status: String {
        switch agent.activity {
        case .working: "arbeitet"
        case .waiting: "wartet auf dich"
        case .failed: "Fehler"
        case .fetchingDrink: "holt sich ein Red Bull"
        case .chilling: "chillt"
        case .sleeping: "schläft"
        case .wandering: "schaut sich um"
        case .leaving: "geht"
        }
    }
}

/// Licht: Nachts liegt Dunkelheit über der Halle, die Lampen schneiden weiche Lichtkegel hinein
/// und färben sie leicht (Kühlschrank kalt, Stehlampe warm, Neon pink, Unterbodenlicht in Wagenfarbe).
private struct OfficeLightOverlay: View {
    let director: OfficeDirector
    let scale: CGFloat

    var body: some View {
        let night = 1 - director.daylight
        // Alles vorab berechnen; die Zeichen-Closures brauchen dann nur diese Werte.
        let glows = OfficeLayout.lights.compactMap { light -> Glow? in
            let strength = intensity(of: light, night: night)
            guard strength > 0.01 else { return nil }
            let radius = light.radius * scale
            let rect = CGRect(x: light.center.x * scale - radius, y: light.center.y * scale - radius,
                              width: radius * 2, height: radius * 2)
            let color = Color(.sRGB, red: Double(light.color.r) / 255, green: Double(light.color.g) / 255,
                              blue: Double(light.color.b) / 255)
            return Glow(rect: rect, color: color, strength: strength)
        }
        ZStack {
            // Dunkelheit mit ausgeschnittenen Lichtkegeln.
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.66 * night)))
                context.blendMode = .destinationOut
                for glow in glows {
                    context.fill(Path(ellipseIn: glow.rect),
                                 with: .radialGradient(Gradient(colors: [Color.black.opacity(min(1, 0.9 * glow.strength)), Color.black.opacity(0)]),
                                                       center: glow.center, startRadius: 0, endRadius: glow.radius))
                }
            }
            // Farbiger Schein der Lichter.
            Canvas { context, _ in
                for glow in glows {
                    context.fill(Path(ellipseIn: glow.rect),
                                 with: .radialGradient(Gradient(colors: [glow.color.opacity(0.32 * glow.strength), glow.color.opacity(0)]),
                                                       center: glow.center, startRadius: 0, endRadius: glow.radius))
                }
            }
            .blendMode(.screen)
        }
    }

    private struct Glow {
        let rect: CGRect
        let color: Color
        let strength: Double
        var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
        var radius: CGFloat { rect.width / 2 }
    }

    private func intensity(of light: OfficeLight, night: Double) -> Double {
        switch light.kind {
        case .window: return director.daylight * 0.6
        case .monitor(let seat):
            let busy = director.agents.contains { agent in
                guard agent.seat == seat, agent.isArrived else { return false }
                if case .working = agent.activity { return true }
                return false
            }
            return busy ? light.intensity * (0.3 + 0.7 * night) : 0
        case .underglow: return light.intensity * night
        default: return light.intensity * (0.35 + 0.65 * night)
        }
    }
}

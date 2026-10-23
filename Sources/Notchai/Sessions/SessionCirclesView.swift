import NotchaiCore
import SwiftUI

/// Eine Session als kleiner Kreis mit dem Anfangsbuchstaben des Projekts: leuchtend in Agentenfarbe,
/// wenn sie wartet, blau, wenn sie arbeitet, grün, wenn sie fertig oder bereit ist.
struct SessionCircle: View {
    let session: AgentSession
    let settings: AppSettings
    var size: CGFloat = 22
    var selected = false

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: "#1C1C1E")))
            .overlay(Circle().strokeBorder(ringColor, lineWidth: selected ? 2.5 : 2))
            .shadow(color: session.status.isWaiting ? ringColor : Color.clear, radius: session.status.isWaiting ? 5 : 0)
            .help("\(session.projectName) · \(SessionPalette.agentName(session.agent))")
    }

    private var initial: String {
        String(session.projectName.prefix(1)).uppercased()
    }

    private var ringColor: Color {
        switch session.status {
        case .waitingApproval, .waitingAnswer: SessionPalette.agentColor(session.agent, settings: settings)
        case .working: SessionPalette.working
        case .error: SignalTheme.red
        case .done, .ready: SessionPalette.finished
        }
    }
}

/// Ruhezustand mit Kreisen: links und rechts der Kamera je bis zu vier Sessions, in der Island-Form.
/// Hover öffnet das Panel mit der Detailkarte (siehe `SessionCirclesPanel`).
struct SessionCirclesIsland: View {
    let model: AppModel
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    var body: some View {
        let shown = Array(model.sessions.prefix(8))
        let leftCount = min(4, (shown.count + 1) / 2)
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(shown.prefix(leftCount)) { session in
                    SessionCircle(session: session, settings: model.settingsStore.settings)
                }
            }
            .padding(.trailing, 6)
            .frame(width: sideWidth, alignment: .trailing)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 4) {
                ForEach(shown.dropFirst(leftCount)) { session in
                    SessionCircle(session: session, settings: model.settingsStore.settings)
                }
            }
            .padding(.leading, 6)
            .frame(width: sideWidth, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Reiter „Sessions“ in der Kreise-Ansicht: alle Kreise in einer Reihe, darunter die Detailkarte der
/// Session unter dem Zeiger mit Status, Gedächtnis-Balken, Antwortfeld und Knöpfen.
struct SessionCirclesPanel: View {
    let model: AppModel

    var body: some View {
        let sessions = model.sessions
        let selected = sessions.first { $0.id == model.selectedCircleID } ?? sessions.first
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if sessions.isEmpty {
                    Text(L("Keine aktiven Sessions"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SessionPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    HStack(spacing: 8) {
                        ForEach(sessions.prefix(12)) { session in
                            SessionCircle(session: session, settings: model.settingsStore.settings, size: 26,
                                          selected: session.id == selected?.id)
                                .onHover { inside in if inside { select(session) } }
                                .onTapGesture { select(session) }
                        }
                    }
                    if let selected {
                        SessionRowView(session: selected, now: context.date, model: model, alwaysShowsReply: true)
                            .padding(8)
                            .frame(width: 360, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                            .frame(maxWidth: .infinity)
                    }
                }
                SessionFooter(model: model)
            }
        }
        .onAppear {
            if let selected { model.replyTargetID = selected.id }
        }
    }

    @MainActor private func select(_ session: AgentSession) {
        model.selectedCircleID = session.id
        model.replyTargetID = session.id
    }
}

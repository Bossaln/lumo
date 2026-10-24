import NotchaiCore
import SwiftUI

/// Reiter „Sessions“: eine Zeile pro Session, darunter die Tagesbilanz. Ein Klick auf eine Zeile zeigt ihre Details.
struct SessionListView: View {
    let model: AppModel

    /// Mehr Zeilen passen nicht ins Panel (höchstens 420 pt); der Rest wird gezählt.
    private static let maxRows = 6

    var body: some View {
        // Die Zeitangaben („vor 2 min“) laufen auch ohne neue Ereignisse weiter.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                if let detail = model.detailSession {
                    SessionDetailView(session: detail, now: context.date, model: model)
                        .transition(.blurFade)
                } else if model.sessions.isEmpty {
                    Text(L("Keine aktiven Sessions"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SessionPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ForEach(model.sessions.prefix(Self.maxRows)) { session in
                        SessionRowView(session: session, now: context.date, model: model)
                    }
                    if model.sessions.count > Self.maxRows {
                        Text(L("+ {0} weitere", model.sessions.count - Self.maxRows))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SessionPalette.secondary)
                            .padding(.leading, 26)
                    }
                }
                SessionFooter(model: model)
            }
            .animation(.easeInOut(duration: 0.22), value: model.detailSession?.id)
        }
        // Beim nächsten Aufklappen wieder die Liste.
        .onDisappear { model.closeSessionDetail() }
    }
}

/// Hinweis nach einer Antwort oder die Tagesbilanz.
struct SessionFooter: View {
    let model: AppModel

    var body: some View {
        Text(model.notice ?? model.dailyStats.formatted())
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(model.notice == nil ? SessionPalette.footer : Color.white)
            .lineLimit(1)
            .padding(.top, 6)
            .padding(.leading, 2)
            .animation(.easeInOut(duration: 0.2), value: model.notice)
    }
}

import NotchaiCore
import SwiftUI

/// Reiter „Sessions“: eine Zeile pro Session, darunter die Tagesbilanz.
struct SessionListView: View {
    let model: AppModel

    /// Mehr Zeilen passen nicht ins Panel (höchstens 420 pt); der Rest wird gezählt.
    private static let maxRows = 6

    var body: some View {
        // Die Zeitangaben („vor 2 min“) laufen auch ohne neue Ereignisse weiter.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                if model.sessions.isEmpty {
                    Text("Keine aktiven Sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SessionPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ForEach(model.sessions.prefix(Self.maxRows)) { session in
                        SessionRowView(session: session, now: context.date, model: model)
                    }
                    if model.sessions.count > Self.maxRows {
                        Text("+ \(model.sessions.count - Self.maxRows) weitere")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SessionPalette.secondary)
                            .padding(.leading, 26)
                    }
                }
                SessionFooter(model: model)
            }
        }
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

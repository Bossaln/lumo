import AppKit
import NotchaiCore
import SwiftUI

/// Reiterleiste des Panels: runde Symbolknöpfe links, rechts der Name des Reiters – im Reiter
/// „Musik“ das Symbol und der Name des Players, der gerade läuft (z. B. Spotify).
struct PanelTabBar: View {
    @Binding var selection: PanelTab
    /// Text rechts; ohne Angabe der Name des Reiters.
    var label: String? = nil
    /// Symbol vor dem Text (App des Players).
    var icon: NSImage? = nil
    /// Der helle Kreis gleitet zum gewählten Reiter, statt umzuspringen.
    @Namespace private var highlight

    /// #8E8E93, auch für Nebentexte im Panel.
    static let gray = Color(.sRGB, red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)

    var body: some View {
        let title = label ?? selection.title
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    Image(systemName: Self.symbol(for: tab))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isActive ? Color.white : Self.gray)
                        .frame(width: 26, height: 26)
                        .background {
                            if isActive {
                                Circle()
                                    .fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "aktiv", in: highlight)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 15, height: 15)
                    }
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Self.gray)
                        .lineLimit(1)
                }
                .id(title)
                .transition(.blurFade)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
        .animation(.easeInOut(duration: 0.25), value: title)
    }

    private static func symbol(for tab: PanelTab) -> String {
        switch tab {
        case .music: "music.note"
        case .sessions: "terminal"
        case .office: "building.2"
        case .shelf: "tray.full"
        case .notes: "note.text"
        }
    }
}

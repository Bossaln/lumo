import AppKit
import NotchaiCore
import SwiftUI

/// Startseite der Einstellungen: groß der Name, darunter jeder Bereich als Kachel. Beim Darüberfahren hebt sich die
/// Kachel und leuchtet in ihrer Farbe.
struct SettingsHome: View {
    let panes: [SettingsPane]
    let version: String
    let namespace: Namespace.ID
    let open: (SettingsPane) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(panes) { pane in
                        SettingsTile(pane: pane, namespace: namespace) { open(pane) }
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 70)
            .padding(.bottom, 48)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: Color.white.opacity(0.12), radius: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text("notchai")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Lux.primary)
                Text(L("Version {0}", version))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Lux.tertiary)
            }
        }
    }
}

/// Eine Kachel: Symbol, Name und eine Zeile Beschreibung. Hover hebt sie an und lässt sie in ihrer Farbe leuchten.
struct SettingsTile: View {
    let pane: SettingsPane
    let namespace: Namespace.ID
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsIcon(pane: pane, size: 40)
                    .matchedGeometryEffect(id: pane, in: namespace)
                    .shadow(color: pane.colors.1.opacity(hovering ? 0.7 : 0.35), radius: hovering ? 16 : 8, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Lux.primary)
                    Text(pane.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Lux.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous)
                    .fill(hovering ? Lux.cardHover : Lux.card)
                    // Schein in der Farbe des Bereichs, von oben links.
                    .overlay(
                        RadialGradient(colors: [pane.colors.0.opacity(hovering ? 0.28 : 0.10), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 260)
                            .clipShape(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [pane.colors.0.opacity(hovering ? 0.6 : 0.0), Lux.hairline],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: pane.colors.1.opacity(hovering ? 0.30 : 0), radius: 26, y: 10)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Lux.spring, value: hovering)
    }
}

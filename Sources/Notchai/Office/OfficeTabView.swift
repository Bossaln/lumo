import NotchaiCore
import SwiftUI

/// Reiter „Büro“: die Lagerhalle verkleinert und live. Ein Klick daneben (nicht auf eine Figur) öffnet sie groß.
struct OfficeTabView: View {
    /// Volle Breite des Panel-Inhalts, Höhe im Seitenverhältnis der Halle.
    static let previewSize: CGSize = {
        let width = NotchGeometry.panelWidth - 2 * NotchGeometry.panelEar - 2 * 22
        return CGSize(width: width, height: (width * CGFloat(OfficeLayout.height) / CGFloat(OfficeLayout.width)).rounded())
    }()

    let model: AppModel

    var body: some View {
        let settings = model.settingsStore.settings
        if !settings.officeEnabled {
            VStack(spacing: 10) {
                Text(L("Das Büro ist ausgeschaltet."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelTabBar.gray)
                Button(L("Einstellungen öffnen")) { model.openSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.bottom, 16)
        } else if let director = model.officeDirector {
            OfficeView(director: director, compact: true, onBackgroundTap: { model.openOffice() })
                .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) { caption(hotkey: settings.officeHotkey) }
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
    }

    private func caption(hotkey: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8, weight: .bold))
            Text(hotkey ? L("Groß öffnen: klicken oder 2× rechte ⌘") : L("Klicken, um groß zu öffnen"))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(7)
        .allowsHitTesting(false)
    }
}

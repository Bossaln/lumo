import AppKit
import NotchaiCore
import SwiftUI

/// Vorschaubild je Stil der Titelanzeige: eine kleine Notch auf dem Schreibtisch, so wie sie ausfährt.
struct TrackChangeThumbnail: View {
    let style: TrackChangeStyle

    private static let cover = LinearGradient(colors: [Color(.sRGB, red: 1.0, green: 0.36, blue: 0.5),
                                                       Color(.sRGB, red: 0.55, green: 0.18, blue: 0.75)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let pink = Color(.sRGB, red: 1.0, green: 0.38, blue: 0.58)

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackdrop()
            switch style {
            case .island:
                NotchShape(bottomRadius: 6, topCornerRadius: 3)
                    .fill(Color.black)
                    .frame(width: 100, height: 14)
                    .overlay {
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Self.cover)
                                .frame(width: 9, height: 9)
                            Spacer()
                            // Platz der Kamera, rechts daneben Titel und Interpret.
                            Color.clear.frame(width: 26)
                            VStack(alignment: .leading, spacing: 1.5) {
                                Capsule().fill(Color.white).frame(width: 22, height: 2.5)
                                Capsule().fill(Color.white.opacity(0.45)).frame(width: 14, height: 2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 7)
                    }
            case .banner:
                NotchShape(bottomRadius: 9, topCornerRadius: 4)
                    .fill(Color.black)
                    .frame(width: 80, height: 34)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Self.cover)
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Capsule().fill(Color.white).frame(width: 26, height: 3)
                                Capsule().fill(Color.white.opacity(0.45)).frame(width: 17, height: 2.5)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.bottom, 5)
                    }
            case .off:
                NotchShape(bottomRadius: 6, topCornerRadius: 3)
                    .fill(Color.black)
                    .frame(width: 58, height: 14)
                    .overlay {
                        HStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Self.cover)
                                .frame(width: 8, height: 8)
                            Spacer()
                            HStack(spacing: 1.5) {
                                ForEach([5.0, 8, 4], id: \.self) { height in
                                    Capsule().fill(Self.pink).frame(width: 1.8, height: height)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
            }
        }
    }
}

/// Ob echter Ton für die Balken ankommt, und was zu tun ist, wenn nicht.
struct VisualizerStatusRow: View {
    let status: MusicVisualizer.Status

    var body: some View {
        switch status {
        case .idle, .starting:
            StatusBadge(text: L("Läuft, sobald Musik spielt und Balken zu sehen sind."), color: .gray)
        case .running:
            StatusBadge(text: L("Echter Ton kommt an."), color: .green)
        case .silent:
            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(text: L("Es kommt kein Ton an."), color: .orange)
                Text(L("Erlaube notchai unter Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme (nur Systemaudio). Bis dahin tanzen die Balken animiert."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Systemeinstellungen öffnen")) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    NSWorkspace.shared.open(url)
                }
            }
        case .unsupported:
            StatusBadge(text: L("Echte Balken brauchen macOS 14.2 oder neuer; bis dahin tanzen sie animiert."), color: .gray)
        case .failed(let reason):
            StatusBadge(text: L("Ton abgreifen ging nicht: {0}", reason), color: .orange)
        }
    }
}

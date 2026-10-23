import AppKit
import NotchaiCore
import SwiftUI

/// Reiter „Ablage“. Zieht man Dateien über die Notch, klappt sie hierher auf und zeigt zwei Ziele: AirDrop und
/// Ablage. Abgelegte Dateien stehen als Kacheln in einer Reihe und lassen sich wieder herausziehen.
struct ShelfTabView: View {
    let model: AppModel

    var body: some View {
        let receiving = model.notch.isReceivingFiles
        ZStack(alignment: .top) {
            if !model.settingsStore.settings.shelfEnabled {
                disabled
            } else if receiving {
                ShelfDropTargets(model: model)
                    .transition(.shelfSwap)
            } else if model.shelfStore.shelf.items.isEmpty {
                empty
                    .transition(.shelfSwap)
            } else {
                ShelfItemsView(model: model)
                    .transition(.shelfSwap)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: receiving)
        .onAppear { model.shelfStore.pruneMissing() }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .frame(width: 58, height: 46)
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            Text("Zieh Dateien auf die Notch")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Color.white)
            Text("Dann per AirDrop senden oder hier kurz ablegen und später wieder herausziehen.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(PanelTabBar.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var disabled: some View {
        VStack(spacing: 10) {
            Text("Die Ablage ist ausgeschaltet.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelTabBar.gray)
            Button("Einstellungen öffnen") { model.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}

// MARK: - Ziele beim Ziehen

/// Zwei große Karten: links AirDrop, rechts die Ablage. Die Karte unter der Datei leuchtet in ihrer Farbe auf,
/// wächst ein wenig und ihr Symbol hüpft.
struct ShelfDropTargets: View {
    let model: AppModel

    @ViewState private var targeted: ShelfTarget?
    @ViewState private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(ShelfTarget.allCases.enumerated()), id: \.element) { index, target in
                ShelfDropCard(target: target, isTargeted: targeted == target)
                    .onDrop(of: [.fileURL], isTargeted: binding(for: target)) { providers in
                        ShelfActions.receive(providers, for: target, model: model)
                        return true
                    }
                    // Die Karten kommen nacheinander von unten herein.
                    .offset(y: shown ? 0 : 14)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.05 + Double(index) * 0.06),
                               value: shown)
            }
        }
        .padding(.top, 2)
        .onAppear { shown = true }
    }

    private func binding(for target: ShelfTarget) -> Binding<Bool> {
        Binding(
            get: { targeted == target },
            set: { inside in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                    if inside {
                        targeted = target
                    } else if targeted == target {
                        targeted = nil
                    }
                }
            }
        )
    }
}

struct ShelfDropCard: View {
    let target: ShelfTarget
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(target.color.opacity(isTargeted ? 0.32 : 0.16))
                    .frame(width: 50, height: 50)
                Image(systemName: target.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(target.color)
                    .symbolEffect(.bounce, value: isTargeted)
            }
            .scaleEffect(isTargeted ? 1.12 : 1)
            Text(target.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
            ZStack {
                Text(isTargeted ? target.releaseHint : target.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isTargeted ? target.color : PanelTabBar.gray)
                    .id(isTargeted)
                    .transition(.blurFade)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(shape.fill(isTargeted ? target.color.opacity(0.14) : Color.white.opacity(0.05)))
        .overlay(
            shape.strokeBorder(isTargeted ? target.color : Color.white.opacity(0.16),
                               style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.2, dash: isTargeted ? [] : [6, 5]))
        )
        .shadow(color: target.color.opacity(isTargeted ? 0.5 : 0), radius: 16)
        .scaleEffect(isTargeted ? 1.04 : 1)
        .contentShape(shape)
    }
}

// MARK: - Abgelegte Dateien

/// Kacheln der abgelegten Dateien (neueste links) und darunter Anzahl, AirDrop und Leeren.
struct ShelfItemsView: View {
    let model: AppModel

    var body: some View {
        let items = model.shelfStore.shelf.items
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        ShelfFileTile(item: item, model: model)
                            .transition(.shelfTile)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .frame(height: 100)
            footer(items)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.76), value: items.map(\.path))
    }

    private func footer(_ items: [ShelfItem]) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                Text(model.notice ?? Self.countText(items.count))
                    .id(model.notice ?? "")
                    .transition(.blurFade)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(model.notice == nil ? PanelTabBar.gray : Color.white)
            .animation(.easeInOut(duration: 0.2), value: model.notice)
            Spacer(minLength: 0)
            ShelfFooterButton(title: "AirDrop", symbol: "dot.radiowaves.left.and.right") {
                ShelfActions.airDrop(items.map(\.url), model: model)
            }
            ShelfFooterButton(title: "Leeren", symbol: "trash") {
                model.shelfStore.removeAll()
            }
        }
    }

    static func countText(_ count: Int) -> String {
        count == 1 ? "1 Datei · zum Herausnehmen ziehen" : "\(count) Dateien · zum Herausnehmen ziehen"
    }
}

/// Eine abgelegte Datei: Symbol und Name. Ziehen nimmt sie heraus (als Kopie), Doppelklick öffnet sie,
/// beim Darüberfahren erscheint ✕, ein Rechtsklick zeigt alle Aktionen.
struct ShelfFileTile: View {
    let item: ShelfItem
    let model: AppModel

    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: ShelfActions.icon(for: item.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .shadow(color: Color.black.opacity(0.4), radius: 3, y: 2)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 28, alignment: .top)
        }
        .frame(width: 80, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    model.shelfStore.remove(item.path)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(white: 0.28)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(NotchControlButtonStyle())
                .padding(3)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .accessibilityLabel("Aus der Ablage entfernen")
            }
        }
        .scaleEffect(hovering ? 1.05 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = inside }
        }
        .onTapGesture(count: 2) { ShelfActions.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Öffnen") { ShelfActions.open(item) }
            Button("Im Finder zeigen") { ShelfActions.reveal(item) }
            Button("Per AirDrop senden") { ShelfActions.airDrop([item.url], model: model) }
            Divider()
            Button("Aus der Ablage entfernen") { model.shelfStore.remove(item.path) }
        }
        .help(item.path)
    }
}

/// Kleiner runder Knopf mit Text in der Fußzeile der Ablage.
struct ShelfFooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.16 : 0.09)))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }
}

extension AnyTransition {
    /// Zwischen Zielen und Dateien: weich, unscharf und leicht verkleinert.
    static var shelfSwap: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// Eine neue Datei springt aus der Notch in die Reihe, eine entfernte schrumpft weg.
    static var shelfTile: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.4, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -18)),
            removal: .scale(scale: 0.5).combined(with: .opacity)
        )
    }
}

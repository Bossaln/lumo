import AppKit
import NotchaiCore
import SwiftUI

/// Reiter „Notizen“: oben das Feld für eine Schnellnotiz (↩ speichert, ⌥↩ neue Zeile, Escape schließt), darunter
/// die gespeicherten, neueste zuerst. Zweimal ⌃ öffnet ihn von überall, mit dem Feld bereit zum Schreiben.
struct NotesTabView: View {
    let model: AppModel

    @FocusState private var fieldFocused: Bool

    /// Bis zu so vielen Notizen stehen untereinander; mehr lassen sich scrollen.
    private static let visibleNotes = 3
    private static let listHeight: CGFloat = 150

    var body: some View {
        let notes = model.noteStore.book.notes
        VStack(alignment: .leading, spacing: 10) {
            composer
            if notes.isEmpty {
                empty
            } else if notes.count <= Self.visibleNotes {
                rows(notes)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    rows(notes)
                }
                .frame(height: Self.listHeight)
            }
            footer(count: notes.count)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: notes.map(\.id))
        .onAppear { if model.notch.isWritingNote { fieldFocused = true } }
        .onChange(of: model.notch.isWritingNote) { _, writing in
            if writing { fieldFocused = true }
        }
        .onChange(of: fieldFocused) { _, focused in
            model.send(.noteFieldFocused(focused))
        }
    }

    private var composer: some View {
        let draft = Binding(get: { model.noteDraft }, set: { model.noteDraft = $0 })
        let canSave = !model.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fieldFocused ? Color.white : PanelTabBar.gray)
            TextField(L("Schnellnotiz …"), text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.white)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onSubmit { model.saveNote() }
            if canSave {
                Button { model.saveNote() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .help(L("Speichern (↩)"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(fieldFocused ? 0.13 : 0.07)))
        .animation(.easeInOut(duration: 0.18), value: canSave)
        .animation(.easeInOut(duration: 0.18), value: fieldFocused)
    }

    private func rows(_ notes: [QuickNote]) -> some View {
        VStack(spacing: 6) {
            ForEach(notes) { note in
                NoteRow(note: note, model: model)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text(L("Noch keine Notizen"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
            Text(L("Zweimal ⌃ drücken, schreiben, ↩ – von überall."))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(PanelTabBar.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func footer(count: Int) -> some View {
        let text = model.notice ?? (model.notch.isWritingNote ? L("↩ speichern · ⌥↩ neue Zeile · esc schließen")
            : count == 1 ? L("1 Notiz · Klick kopiert") : L("{0} Notizen · Klick kopiert", count))
        return ZStack(alignment: .leading) {
            Text(text)
                .id(text)
                .transition(.blurFade)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(model.notice == nil ? PanelTabBar.gray : Color.white)
        .animation(.easeInOut(duration: 0.2), value: text)
    }
}

/// Eine gespeicherte Notiz: Text und Alter. Klick kopiert sie, beim Darüberfahren erscheint ✕ zum Löschen.
struct NoteRow: View {
    let note: QuickNote
    let model: AppModel

    @ViewState private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RelativeTime.short(from: note.createdAt, now: Date()))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(PanelTabBar.gray)
            }
            Button { model.noteStore.remove(note.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(L("Notiz löschen"))
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.1 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture { copy() }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
        model.showNotice(L("Notiz kopiert"))
    }
}

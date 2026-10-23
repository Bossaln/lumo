import NotchaiCore
import SwiftUI

/// Einrichtungs-Assistent in drei Schritten: Erklärung, Claude Code verbinden, Codex verbinden.
/// Jeder Schritt lässt sich überspringen.
struct SetupAssistantView: View {
    let setup: SetupController
    let finish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, claude, codex
    }

    @ViewState private var step: Step = .welcome

    private static let claudeEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, StopFailure, SubagentStart, SubagentStop (nur melden) sowie PermissionRequest und AskUserQuestion (Freigaben und Fragen in der Notch beantworten)"
    private static let codexEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop (nur melden) sowie PermissionRequest"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message = setup.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(setup.lastActionFailed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Schritt \(visibleIndex) von \(visibleSteps.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                buttons
            }
        }
        .padding(24)
        .frame(width: 560, height: 400)
        .onAppear { setup.refresh() }
    }

    // MARK: - Inhalt

    private var title: String {
        switch step {
        case .welcome: "notchai einrichten"
        case .claude: "Claude Code verbinden"
        case .codex: "Codex verbinden"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 10) {
                Text("Damit die Notch sieht, was Claude Code und Codex tun, trägt notchai eigene Hooks in deren Einstellungen ein.")
                Text("Vor jeder Änderung legt notchai eine Sicherung an. Fremde Einträge bleiben unverändert, und unter Einstellungen › Agenten lässt sich alles mit einem Knopf wieder entfernen.")
                Text("Läuft notchai nicht, arbeiten Claude Code und Codex genau wie vorher weiter.")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .claude:
            VStack(alignment: .leading, spacing: 10) {
                Text("notchai trägt in ~/.claude/settings.json Hooks für diese Ereignisse ein:")
                Text(Self.claudeEvents)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                stateLine(installed: setup.status?.claudeInstalled ?? false)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codex:
            VStack(alignment: .leading, spacing: 10) {
                Text("notchai trägt in ~/.codex/hooks.json Hooks für diese Ereignisse ein. Die config.toml bleibt unberührt.")
                Text(Self.codexEvents)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Codex führt neue Hooks erst aus, wenn du sie einmal bestätigt hast: Starte danach Codex im Terminal und wähle bei „Hooks need review“ „Trust all and continue“.")
                    .font(.callout)
                stateLine(installed: setup.status?.codexInstalled ?? false)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stateLine(installed: Bool) -> some View {
        Label(installed ? "Verbunden" : "Noch nicht verbunden",
              systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(installed ? Color.green : Color.secondary)
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .welcome:
            Button("Später") { finish() }
            Button("Weiter") { advance() }
                .keyboardShortcut(.defaultAction)
        case .claude:
            Button("Überspringen") { advance() }
            Button(setup.status?.claudeInstalled == true ? "Weiter" : "Claude Code verbinden") {
                if setup.status?.claudeInstalled != true { setup.connectClaude() }
                if setup.status?.claudeInstalled == true { advance() }
            }
            .keyboardShortcut(.defaultAction)
        case .codex:
            Button("Überspringen") { advance() }
            Button(setup.status?.codexInstalled == true ? "Weiter" : "Codex verbinden") {
                if setup.status?.codexInstalled != true { setup.connectCodex() }
                if setup.status?.codexInstalled == true { advance() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Ablauf

    private var visibleSteps: [Step] { Step.allCases }

    private var visibleIndex: Int {
        (visibleSteps.firstIndex(of: step) ?? 0) + 1
    }

    private func advance() {
        guard let index = visibleSteps.firstIndex(of: step), index + 1 < visibleSteps.count else {
            finish()
            return
        }
        step = visibleSteps[index + 1]
    }
}

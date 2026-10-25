import AppKit
import LumoCore
import Observation

/// Richtet lumos Hooks ein und wieder aus (gemeinsam für Assistent und Einstellungen).
/// Jede Änderung legt vorher eine Sicherung an; fremde Einträge bleiben stehen (`HookInstaller`).
@MainActor @Observable
final class SetupController {
    private(set) var status: HookInstallStatus?
    /// Letzte Meldung (Erfolg oder Fehler) für die Ansicht.
    private(set) var message: String?
    private(set) var lastActionFailed = false

    @ObservationIgnored private let installer: HookInstaller
    @ObservationIgnored let backupsFolder: URL

    init(home: URL) {
        installer = HookInstaller(home: home, hookBinaryPath: LumoPaths.hookBinary(home: home).path)
        backupsFolder = LumoPaths.backupsDir(home: home)
        refresh()
    }

    func refresh() {
        do {
            status = try installer.status()
        } catch {
            status = nil
            report(error)
        }
    }

    func connectClaude() {
        perform { try self.installer.installClaude()
            return L("Claude Code ist verbunden. Laufende Claude-Sessions neu starten, damit sie lumo kennen.") }
    }

    func connectCodex() {
        perform { try self.installer.installCodex()
            return L("Codex ist verbunden. Starte Codex einmal im Terminal und wähle bei „Hooks need review“ „Trust all and continue“.")
        }
    }

    func removeAll() {
        perform { try self.installer.uninstallAll()
            return L("Alle lumo-Einträge entfernt. Fremde Einträge sind unverändert.") }
    }

    func showBackups() {
        try? FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupsFolder)
    }

    private func perform(_ action: () throws -> String) {
        do {
            message = try action()
            lastActionFailed = false
        } catch {
            report(error)
        }
        refresh()
    }

    private func report(_ error: Error) {
        message = (error as? LocalizedError)?.errorDescription ?? L("Fehler: {0}", error.localizedDescription)
        lastActionFailed = true
    }
}

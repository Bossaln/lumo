import Foundation

public struct HookInstallStatus: Equatable, Sendable {
    /// Alle lumo-Einträge stehen vollständig und mit dem aktuellen Programmpfad in der Datei.
    public var claudeInstalled: Bool
    public var codexInstalled: Bool

    public init(claudeInstalled: Bool, codexInstalled: Bool) {
        self.claudeInstalled = claudeInstalled
        self.codexInstalled = codexInstalled
    }
}

public enum HookInstallerError: Error, Equatable, LocalizedError {
    /// Die Datei ist kein JSON-Objekt (oder `hooks` hat eine unerwartete Form); sie bleibt unverändert.
    case unreadable(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): L("„{0}“ ist kein lesbares JSON und wurde nicht verändert.", path)
        }
    }
}

/// Trägt lumos Hooks in `~/.claude/settings.json` und `~/.codex/hooks.json` ein und wieder aus.
/// Fremde Einträge bleiben unangetastet, vor jedem Schreiben wird gesichert, `~/.codex/config.toml` wird
/// nie geschrieben. Bearbeitet wird über `JSONSerialization`, damit unbekannte Felder erhalten bleiben.
public struct HookInstaller: Sendable {
    /// lumo-Einträge erkennt man am Programmpfad, auch wenn er sich geändert hat.
    private static let lumoMarker = "/lumo/bin/lumo-hook"

    /// Einträge der alten App (notchai, bis 0.7.0) gelten als eigene: Sie werden mit entfernt und ersetzt.
    private static func isOwn(_ command: String) -> Bool {
        command.contains(lumoMarker) || command.contains(LegacyMigration.legacyHookMarker)
    }

    private struct Entry {
        var event: String
        var matcher = ""
        var mode: HookMode
        var timeout: Int
        var async: Bool
    }

    private static func event(_ name: String) -> Entry {
        Entry(event: name, mode: .event, timeout: 5, async: true)
    }

    /// Entscheidungen warten bis 125 s auf die App; der Agent bricht nach 130 s ab.
    private static func decide(_ name: String, matcher: String = "") -> Entry {
        Entry(event: name, matcher: matcher, mode: .decide, timeout: 130, async: false)
    }

    private static let claudeEntries: [Entry] =
        ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
         "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop"].map(event)
        + [decide("PermissionRequest"), decide("PreToolUse", matcher: "AskUserQuestion")]

    /// Codex führt `SessionEnd` immer synchron aus und kürzt dort auf 3 s (`docs/hooks.md`, Abschnitt 4).
    private static let codexEntries: [Entry] =
        ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SubagentStart", "SubagentStop"].map(event)
        + [Entry(event: "SessionEnd", mode: .event, timeout: 3, async: false), decide("PermissionRequest")]

    private let home: URL
    private let hookBinaryPath: String
    private let now: @Sendable () -> Date

    public init(home: URL, hookBinaryPath: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.home = home
        self.hookBinaryPath = hookBinaryPath
        self.now = now
    }

    private var claudeFile: URL { home.appending(path: ".claude/settings.json") }
    private var codexFile: URL { home.appending(path: ".codex/hooks.json") }

    // MARK: - Öffentlich

    public func status() throws -> HookInstallStatus {
        let claude = try read(claudeFile) ?? [:]
        let codex = try read(codexFile) ?? [:]
        return HookInstallStatus(
            claudeInstalled: Self.claudeEntries.allSatisfy { contains(claude, $0, agent: .claude) },
            codexInstalled: Self.codexEntries.allSatisfy { contains(codex, $0, agent: .codex) })
    }

    public func installClaude() throws {
        try install(Self.claudeEntries, agent: .claude, file: claudeFile, backupPrefix: "claude-settings")
    }

    public func installCodex() throws {
        try install(Self.codexEntries, agent: .codex, file: codexFile, backupPrefix: "codex-hooks")
    }

    /// Entfernt nur lumos eigene Einträge.
    public func uninstallAll() throws {
        try update(claudeFile, backupPrefix: "claude-settings", createIfMissing: false) {
            _ = try Self.removeHooks(in: &$0) { Self.isOwn($0) }
        }
        try update(codexFile, backupPrefix: "codex-hooks", createIfMissing: false) {
            _ = try Self.removeHooks(in: &$0) { Self.isOwn($0) }
        }
    }

    /// Stehen noch Einträge der alten App (notchai) in den Dateien?
    public func legacyStatus() throws -> HookInstallStatus {
        func hasLegacy(_ file: URL) throws -> Bool {
            guard let root = try read(file), let hooks = try Self.hooksObject(root) else { return false }
            return hooks.values.contains { groups in
                (groups as? [Any] ?? []).contains { group in
                    ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains { definition in
                        (((definition as? [String: Any])?["command"] as? String) ?? "").contains(LegacyMigration.legacyHookMarker)
                    }
                }
            }
        }
        return HookInstallStatus(claudeInstalled: try hasLegacy(claudeFile), codexInstalled: try hasLegacy(codexFile))
    }

    /// Ersetzt Einträge der alten App durch eigene, nur dort, wo welche stehen. Gibt zurück, was umgestellt wurde.
    /// Codex fragt danach einmal neu nach dem Vertrauen in die Hooks (anderes Kommando).
    @discardableResult
    public func migrateLegacy() throws -> HookInstallStatus {
        let legacy = try legacyStatus()
        if legacy.claudeInstalled { try installClaude() }
        if legacy.codexInstalled { try installCodex() }
        return legacy
    }

    /// Kopiert das mitgelieferte `lumo-hook` an seinen festen Ort, wenn es sich unterscheidet.
    /// Atomar ersetzt, damit gerade laufende Hooks die alte Datei zu Ende lesen.
    @discardableResult
    public func copyHookBinary(from bundled: URL) throws -> Bool {
        let target = LumoPaths.hookBinary(home: home)
        let fm = FileManager.default
        let data = try Data(contentsOf: bundled)
        let changed = (try? Data(contentsOf: target)) != data
        if changed {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return changed
    }

    // MARK: - Einträge

    private func command(_ agent: AgentKind, _ mode: HookMode) -> String {
        "\"\(hookBinaryPath)\" \(agent.rawValue) \(mode.rawValue)"
    }

    private func install(_ entries: [Entry], agent: AgentKind, file: URL, backupPrefix: String) throws {
        try update(file, backupPrefix: backupPrefix, createIfMissing: true) { root in
            // Erst alte lumo-Einträge (auch mit anderem Pfad) entfernen, dann frisch anhängen.
            _ = try Self.removeHooks(in: &root) { Self.isOwn($0) }
            var hooks = try Self.hooksObject(root) ?? [:]
            for entry in entries {
                var definition: [String: Any] = ["type": "command", "command": command(agent, entry.mode), "timeout": entry.timeout]
                if entry.async { definition["async"] = true }
                var groups = hooks[entry.event] as? [Any] ?? []
                groups.append(["matcher": entry.matcher, "hooks": [definition]] as [String: Any])
                hooks[entry.event] = groups
            }
            root["hooks"] = hooks
        }
    }

    private func contains(_ root: [String: Any], _ entry: Entry, agent: AgentKind) -> Bool {
        let expected = command(agent, entry.mode)
        let groups = (root["hooks"] as? [String: Any])?[entry.event] as? [Any] ?? []
        return groups.contains { group in
            guard let group = group as? [String: Any], (group["matcher"] as? String ?? "") == entry.matcher else { return false }
            return (group["hooks"] as? [Any] ?? []).contains { ($0 as? [String: Any])?["command"] as? String == expected }
        }
    }

    /// `hooks` als Objekt; `nil`, wenn es fehlt. Eine andere Form gilt als unlesbar.
    private static func hooksObject(_ root: [String: Any]) throws -> [String: Any]? {
        guard let value = root["hooks"] else { return nil }
        guard let hooks = value as? [String: Any] else { throw HookInstallerError.unreadable(path: "hooks") }
        return hooks
    }

    /// Entfernt alle Hook-Definitionen, deren Kommando `matches` erfüllt. Leer gewordene Gruppen,
    /// Ereignisse und ein leeres `hooks` verschwinden. Ohne Treffer bleibt `root` unberührt.
    private static func removeHooks(in root: inout [String: Any], where matches: (String) -> Bool) throws -> Int {
        guard var hooks = try hooksObject(root) else { return 0 }
        var removed = 0
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            for group in groups {
                guard var g = group as? [String: Any], let definitions = g["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let remaining = definitions.filter { definition in
                    guard let command = (definition as? [String: Any])?["command"] as? String, matches(command) else { return true }
                    removed += 1
                    return false
                }
                if remaining.count == definitions.count {
                    kept.append(group)
                } else if !remaining.isEmpty {
                    g["hooks"] = remaining
                    kept.append(g)
                }
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard removed > 0 else { return 0 }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return removed
    }

    // MARK: - Dateien

    /// Liest ein JSON-Objekt; `nil`, wenn die Datei fehlt.
    private func read(_ file: URL) throws -> [String: Any]? {
        let target = file.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        guard let data = try? Data(contentsOf: target),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.unreadable(path: file.path)
        }
        return root
    }

    /// Liest, ändert und schreibt `file` nur, wenn sich wirklich etwas ändert; vorher wird gesichert.
    /// Ein Symlink (etwa aus einem Dotfiles-Repository) bleibt erhalten, geschrieben wird sein Ziel.
    private func update(_ file: URL, backupPrefix: String, createIfMissing: Bool,
                        _ change: (inout [String: Any]) throws -> Void) throws {
        let target = file.resolvingSymlinksInPath()
        let existing = try read(target)
        guard existing != nil || createIfMissing else { return }
        var root = existing ?? [:]
        try change(&root)
        let newData = try Self.serialize(root)
        if let existing, try Self.serialize(existing) == newData { return }
        if existing != nil { try backup(target, prefix: backupPrefix) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try newData.write(to: target, options: .atomic)
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Kopiert die Datei unverändert nach `backups/<prefix>-<yyyyMMdd-HHmmss>.json`; nie über eine ältere Sicherung.
    private func backup(_ file: URL, prefix: String) throws {
        let dir = LumoPaths.backupsDir(home: home)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        var name = "\(prefix)-\(stamp).json"
        var counter = 2
        while FileManager.default.fileExists(atPath: dir.appending(path: name).path) {
            name = "\(prefix)-\(stamp)-\(counter).json"
            counter += 1
        }
        try FileManager.default.copyItem(at: file, to: dir.appending(path: name))
    }
}

import Foundation
import LumoCore

/// Startet Programme ohne die App zu blockieren und sammelt ihre Ausgabe (stdout und stderr zusammen,
/// mit `includeErrors: false` nur stdout).
enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil, includeErrors: Bool = true) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = includeErrors ? pipe : FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription))
                    return
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning { process.terminate() }
                    }
                }
                // Erst lesen, dann warten: Sonst blockiert ein voller Puffer das Programm.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: CommandResult(status: process.terminationStatus,
                                                             output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

/// Die Umgebung der Login-Shell des Besitzers. Aus der Menüleiste gestartete Apps kennen den `PATH`
/// aus `.zprofile` nicht; Git und Swift sollen aber dieselben Programme finden wie im Terminal.
actor LoginEnvironment {
    static let shared = LoginEnvironment()
    private static let marker = "__LUMO_PATH__"
    private var cached: [String: String]?

    func environment() async -> [String: String] {
        if let cached { return cached }
        var env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        let result = await ProcessRunner.run(shell, ["-l", "-c", "printf '%s%s' '\(Self.marker)' \"$PATH\""], timeout: 10)
        if result.status == 0, let path = result.output.components(separatedBy: Self.marker).last, !path.isEmpty {
            env["PATH"] = path.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Nie auf eine Passwort-Abfrage warten, die niemand sieht.
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        cached = env
        return env
    }
}

/// Führt Kommandos mit der Umgebung der Login-Shell in einem Ordner aus (für den Update-Knopf).
struct LoginShellRunner: CommandRunning {
    func run(_ command: String, in directory: String) async -> CommandResult {
        let env = await LoginEnvironment.shared.environment()
        // Git bekommt eine Minute, das Bauen beliebig lange.
        let timeout: TimeInterval? = command.hasPrefix("git ") ? 60 : nil
        return await ProcessRunner.run("/bin/sh", ["-c", "cd \(ShellQuote.quote(directory)) && \(command)"],
                                       environment: env, timeout: timeout)
    }
}

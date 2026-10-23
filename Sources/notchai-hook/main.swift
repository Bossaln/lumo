import Foundation
import NotchaiCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Wird von Claude Code und Codex als Hook aufgerufen. Endet immer mit Exit-Code 0 und schreibt nur eine
// Entscheidungs-JSON oder nichts; eine geschlossene Verbindung darf das Programm nicht beenden.
signal(SIGPIPE, SIG_IGN)

/// Mehr als 4 MB Eingabe werden nicht gelesen; das Ereignis gilt dann als unlesbar.
let inputLimit = 4 << 20
var input = Data()
while input.count <= inputLimit, let chunk = try? FileHandle.standardInput.read(upToCount: 64 << 10), !chunk.isEmpty {
    input.append(chunk)
}

let output = HookClient.run(arguments: Array(CommandLine.arguments.dropFirst()),
                            stdin: input.count <= inputLimit ? input : Data(),
                            env: ProcessInfo.processInfo.environment,
                            home: FileManager.default.homeDirectoryForCurrentUser)
if !output.isEmpty {
    try? FileHandle.standardOutput.write(contentsOf: Data(output.utf8))
}
exit(0)

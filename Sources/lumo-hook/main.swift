import Foundation
import LumoCore
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

// Der Agent über diesem Hook (meist über eine Shell): Endet er, verschwindet seine Session aus der Notch.
let output = HookClient.run(arguments: Array(CommandLine.arguments.dropFirst()),
                            stdin: input.count <= inputLimit ? input : Data(),
                            env: ProcessInfo.processInfo.environment,
                            home: FileManager.default.homeDirectoryForCurrentUser,
                            agentPid: ProcessTree.agent(above: getppid(), lookup: ProcessTree.systemLookup))
if !output.isEmpty {
    try? FileHandle.standardOutput.write(contentsOf: Data(output.utf8))
}
exit(0)

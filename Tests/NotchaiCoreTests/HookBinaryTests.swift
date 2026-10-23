import Foundation
import Testing

/// Ordner des Pakets, aufgelöst von dieser Datei aus (`Tests/NotchaiCoreTests/…`).
private let packageDir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Das von `swift build` bzw. `swift test` gebaute `notchai-hook`. Je nach SwiftPM-Version liegt es unter
/// `.build/debug`, `.build/<Ziel>/debug` oder `.build/out/Products/Debug…`; genommen wird das jüngste.
private let hookBinary: URL? = {
    let fm = FileManager.default
    let build = packageDir.appending(path: ".build")
    let folders = [build.appending(path: "debug")]
        + ((try? fm.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? []).map { $0.appending(path: "debug") }
        + ((try? fm.contentsOfDirectory(at: build.appending(path: "out/Products"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.lowercased().hasPrefix("debug") }
    func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    return folders.map { $0.appending(path: "notchai-hook") }
        .filter { fm.isExecutableFile(atPath: $0.path) }
        .max { modified($0) < modified($1) }
}()

private struct HookBinaryMissing: Error, CustomStringConvertible {
    var description: String { "notchai-hook nicht gebaut – erst `swift build`" }
}

private func requireHookBinary() throws -> URL {
    guard let hookBinary else { throw HookBinaryMissing() }
    return hookBinary
}

private func runHookBinary(_ binary: URL, args: [String], stdin: String, env: [String: String]) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = binary
    process.arguments = args
    process.environment = env
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    let out = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: out, as: UTF8.self))
}

@Test func hookExitsQuicklyWithoutApp() throws {
    let binary = try requireHookBinary()
    let start = Date()
    let (code, out) = try runHookBinary(binary, args: ["claude", "decide"], stdin: #"{"session_id":"s","hook_event_name":"PermissionRequest"}"#,
                                        env: ["NOTCHAI_SOCKET": "/tmp/nope-\(UUID()).sock"])
    #expect(code == 0); #expect(out.isEmpty); #expect(Date().timeIntervalSince(start) < 1.0)
}

@Test func hookSurvivesNonsense() throws {
    let binary = try requireHookBinary()
    for args in [[], ["claude"], ["codex", "decide", "extra"], ["gemini", "event"]] {
        let (code, out) = try runHookBinary(binary, args: args, stdin: "\u{0}kein json", env: [:])
        #expect(code == 0); #expect(out.isEmpty)
    }
}

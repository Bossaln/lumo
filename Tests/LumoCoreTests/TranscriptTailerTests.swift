import Foundation
import Testing
@testable import LumoCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "lumo-tail-\(UUID().uuidString).jsonl")
}

private func append(_ text: String, to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

private func strings(_ lines: [Data]) -> [String] { lines.map { String(decoding: $0, as: UTF8.self) } }

@Test func readsAppendedLinesOnce() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let tailer = TranscriptTailer()
    try append("eins\nzwei\n", to: url)
    #expect(strings(tailer.readNewLines(at: url)) == ["eins", "zwei"])
    #expect(tailer.readNewLines(at: url).isEmpty)
    try append("drei\n", to: url)
    #expect(strings(tailer.readNewLines(at: url)) == ["drei"])
}

@Test func partialLineIsBufferedUntilNewline() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let tailer = TranscriptTailer()
    try append("{\"halb\":", to: url)
    #expect(tailer.readNewLines(at: url).isEmpty)
    try append("1}\n{\"ganz\":2}\n", to: url)
    #expect(strings(tailer.readNewLines(at: url)) == ["{\"halb\":1}", "{\"ganz\":2}"])
}

@Test func truncatedFileRestarts() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let tailer = TranscriptTailer()
    try append("alt eins\nalt zwei\n", to: url)
    _ = tailer.readNewLines(at: url)
    try Data("neu\n".utf8).write(to: url)
    #expect(tailer.wasRestarted(url) == false)
    #expect(strings(tailer.readNewLines(at: url)) == ["neu"])
    #expect(tailer.wasRestarted(url))
}

@Test func missingFileGivesNothing() {
    #expect(TranscriptTailer().readNewLines(at: tempFile()).isEmpty)
}

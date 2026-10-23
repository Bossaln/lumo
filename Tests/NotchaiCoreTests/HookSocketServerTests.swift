import Foundation
import Testing
@testable import NotchaiCore

/// Server auf einem Wegwerf-Socket; jedes ankommende Envelope landet in `envelopes`.
private struct Harness {
    let path = "/tmp/notchai-test-\(UUID().uuidString.prefix(8)).sock"
    let server: HookSocketServer
    let envelopes: AsyncStream<HookEnvelope>

    init() throws {
        let (stream, continuation) = AsyncStream.makeStream(of: HookEnvelope.self)
        envelopes = stream
        server = HookSocketServer(socketPath: path, onEnvelope: { continuation.yield($0) })
        try server.start()
    }

    /// Ruft `HookClient.run` auf einem Hintergrund-Thread auf, wie es `notchai-hook` täte.
    func client(_ mode: String, session: String = "s1", event: String = "PermissionRequest",
                decisionTimeout: TimeInterval = 10) async -> String {
        let stdin = Data(#"{"session_id":"\#(session)","hook_event_name":"\#(event)"}"#.utf8)
        let env = ["NOTCHAI_SOCKET": path, "TERM_PROGRAM": "vscode"]
        return await withCheckedContinuation { done in
            DispatchQueue.global().async {
                done.resume(returning: HookClient.run(arguments: ["claude", mode], stdin: stdin, env: env,
                                                      home: URL(filePath: "/tmp"), decisionTimeout: decisionTimeout))
            }
        }
    }

    func nextEnvelope() async throws -> HookEnvelope {
        var iterator = envelopes.makeAsyncIterator()
        return try #require(await iterator.next())
    }

    func tearDown() {
        server.stop()
        unlink(path)
    }
}

@Test func eventArrivesAtServer() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    let out = await h.client("event", event: "Stop")
    let envelope = try await h.nextEnvelope()
    #expect(out == "")
    #expect(envelope.event.sessionId == "s1")
    #expect(envelope.event.hookEventName == "Stop")
    #expect(envelope.mode == .event)
    #expect(envelope.agent == .claude)
    #expect(envelope.env == ["TERM_PROGRAM": "vscode"])
}

@Test func decisionRoundTrip() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    async let out = h.client("decide")
    let envelope = try await h.nextEnvelope()
    #expect(envelope.mode == .decide)
    h.server.reply(HookReply(requestId: envelope.requestId, stdout: HookOutput.permissionAllow()))
    #expect(await out == HookOutput.permissionAllow())
}

@Test func repliesRouteByRequestId() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    async let outA = h.client("decide", session: "a")
    async let outB = h.client("decide", session: "b")
    var bySession: [String: UUID] = [:]
    var iterator = h.envelopes.makeAsyncIterator()
    for _ in 0..<2 {
        let e = try #require(await iterator.next())
        bySession[e.event.sessionId] = e.requestId
    }
    // Vertauschte Reihenfolge: jede Antwort muss trotzdem bei ihrem Hook ankommen.
    h.server.reply(HookReply(requestId: try #require(bySession["b"]), stdout: "B"))
    h.server.reply(HookReply(requestId: try #require(bySession["a"]), stdout: "A"))
    #expect(await outA == "A")
    #expect(await outB == "B")
}

@Test func serverStopWhileWaitingReleasesHook() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    async let out = h.client("decide", decisionTimeout: 30)
    _ = try await h.nextEnvelope()
    let stoppedAt = Date()
    h.server.stop()
    #expect(await out == "")
    #expect(Date().timeIntervalSince(stoppedAt) < 1.0)
}

@Test func decisionTimeoutGivesNoOutput() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    let start = Date()
    let out = await h.client("decide", decisionTimeout: 0.5)
    let elapsed = Date().timeIntervalSince(start)
    #expect(out == "")
    #expect(elapsed >= 0.4 && elapsed < 2.0)
}

@Test func replyForUnknownOrAnsweredIdIsIgnored() async throws {
    let h = try Harness()
    defer { h.tearDown() }
    h.server.reply(HookReply(requestId: UUID(), stdout: "x"))
    async let out = h.client("decide")
    let envelope = try await h.nextEnvelope()
    h.server.reply(HookReply(requestId: envelope.requestId, stdout: "erste"))
    h.server.reply(HookReply(requestId: envelope.requestId, stdout: "zweite"))
    #expect(await out == "erste")
}

@Test func staleSocketFileIsReplaced() throws {
    // Nach einem Absturz bleibt die Socket-Datei liegen; der nächste Start muss trotzdem klappen.
    let path = "/tmp/notchai-test-\(UUID().uuidString.prefix(8)).sock"
    FileManager.default.createFile(atPath: path, contents: Data("alt".utf8))
    let server = HookSocketServer(socketPath: path, onEnvelope: { _ in })
    defer { server.stop(); unlink(path) }
    try server.start()
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect(attributes[.type] as? FileAttributeType == .typeSocket)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

import AppKit
import NotchaiCore

/// Verbindet Hook-Server, Transkripte und Session-Buch mit der Notch: Ereignisse werden zu Sessions und
/// Signalen, Entscheidungen aus der Notch gehen an den wartenden Hook zurück. Lebt so lange wie die App.
@MainActor
final class HookCoordinator {
    /// So viele Hook-Ereignisse merkt sich die Entwickler-Seite der Einstellungen.
    private static let recentLimit = 40

    private let model: AppModel
    private let home: URL
    private var book = SessionBook()
    private var server: HookSocketServer?
    private var monitor: SessionMonitor?
    private var tickTimer: Timer?
    private let sounds = SoundPlayer()
    let replies: ReplySender
    private var recentEnvelopes: [HookEnvelope] = []
    /// Zu welcher Session das angezeigte Signal gehört (Signal-ID → Session-Schlüssel).
    private var signalSessions: [UUID: String] = [:]
    /// Meldet, ob irgendeine Session auf den Besitzer wartet (Menüleisten-Punkt).
    var onWaitingChange: ((Bool) -> Void)?
    /// Fehler beim Start des Servers, für den Bereich „Allgemein“.
    private(set) var startError: String?

    init(model: AppModel, home: URL) {
        self.model = model
        self.home = home
        replies = ReplySender(home: home)
    }

    func start() {
        installHookBinary()
        let server = HookSocketServer(
            socketPath: NotchaiPaths.socketPath(home: home, env: ProcessInfo.processInfo.environment),
            onEnvelope: { [weak self] envelope in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { MainThreadWork.measure("Hooks.event") { self?.handle(envelope) } }
                }
            })
        do {
            try server.start()
            self.server = server
        } catch {
            startError = "Hook-Server startet nicht: \(error)"
        }
        let monitor = SessionMonitor(home: home, maxAgeHours: { [weak model] in model?.settingsStore.settings.sessionMaxAgeHours ?? 24 },
                                     onUpdate: { [weak self] summaries, stats in
                                         MainThreadWork.measure("Hooks.transcripts") { self?.apply(summaries, stats: stats) }
                                     })
        monitor.start()
        self.monitor = monitor
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { MainThreadWork.measure("Hooks.tick") { self?.tick() } }
        }
    }

    /// Wartende Hooks bekommen beim Beenden sofort „keine Entscheidung“; die Agenten fragen dann selbst.
    func stop() {
        tickTimer?.invalidate()
        monitor?.stop()
        server?.stop()
    }

    /// Kopiert das mitgelieferte `notchai-hook` an seinen festen Ort (nur wenn es sich geändert hat).
    private func installHookBinary() {
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/notchai-hook")
        guard FileManager.default.fileExists(atPath: bundled.path) else { return }
        let installer = HookInstaller(home: home, hookBinaryPath: NotchaiPaths.hookBinary(home: home).path)
        _ = try? installer.copyHookBinary(from: bundled)
    }

    // MARK: - Eingänge

    private func handle(_ incoming: HookEnvelope) {
        var envelope = incoming
        recentEnvelopes.append(envelope)
        if recentEnvelopes.count > Self.recentLimit { recentEnvelopes.removeFirst(recentEnvelopes.count - Self.recentLimit) }
        // Ohne Notch-Bildschirm sieht niemand das Signal: sofort „keine Entscheidung“, der Agent fragt selbst.
        if envelope.mode == .decide, model.screen == nil {
            server?.reply(HookReply(requestId: envelope.requestId, stdout: HookOutput.noDecision))
            envelope.mode = .event
        }
        // „Wartet auf dich“ ohne Hook verschwindet, sobald dieselbe Session weiterläuft.
        let key = SessionBook.key(envelope.agent, envelope.event.sessionId)
        if let shown = model.activeSignal, signalSessions[shown.id] == key, !isPending(shown.id),
           case .question = shown.kind, envelope.event.hookEventName != "Notification" {
            closeSignal(shown.id)
        }
        process(book.apply(envelope: envelope, settings: settings, now: Date()))
        refreshSessions()
    }

    private func apply(_ summaries: [TranscriptSummary], stats: DailyStats) {
        let now = Date()
        for summary in summaries {
            process(book.apply(summary: summary, settings: settings, now: now))
        }
        if model.dailyStats != stats { model.dailyStats = stats }
        refreshSessions()
    }

    private func tick() {
        let (changes, expired) = book.tick(now: Date())
        for id in expired {
            server?.reply(HookReply(requestId: id, stdout: HookOutput.noDecision))
        }
        process(changes)
        // Terminal oder App geschlossen, ohne dass `SessionEnd` kam: Der Agent-Prozess ist weg, die Session auch.
        process(book.removeEnded(isAlive: ProcessTree.isAlive))
        refreshSessions()
    }

    /// Nimmt eine Session aus der Notch, bis sie wieder etwas tut (Detailansicht, „Aus der Notch entfernen“).
    func dismiss(_ session: AgentSession) {
        process(book.dismiss(session.id, now: Date()))
        refreshSessions()
    }

    private var settings: AppSettings { model.settingsStore.settings }

    // MARK: - Änderungen des Session-Buchs

    private func process(_ changes: [SessionChange]) {
        for change in changes {
            switch change {
            case .release(let requestId):
                server?.reply(HookReply(requestId: requestId, stdout: HookOutput.noDecision))
                closeSignal(requestId)
            case .clear(let key):
                if let shown = model.activeSignal, signalSessions[shown.id] == key, !isPending(shown.id) {
                    closeSignal(shown.id)
                }
                showNextRequest()
            case .raise(let key, let trigger):
                sounds.play(trigger, settings: settings)
                switch trigger {
                case .permission, .question:
                    if !showNextRequest(), book.sessions[key]?.pending == nil, let content = attentionSignal(key) {
                        show(content, for: key)
                    }
                case .done, .error:
                    if let content = statusSignal(key, trigger: trigger) { show(content, for: key) }
                }
            }
        }
    }

    /// Zeigt die älteste offene Anfrage, solange keine andere angezeigt wird. Echte Anfragen haben Vorrang
    /// vor „Wartet auf dich“, „fertig“ und „Fehler“. `true`, wenn danach eine Anfrage angezeigt wird.
    @discardableResult
    private func showNextRequest() -> Bool {
        if let shown = model.activeSignal, isPending(shown.id) { return true }
        let candidates = book.pendingRequests().filter { entry in
            switch entry.request.kind {
            case .permission: settings.signalOnPermission
            case .question: settings.signalOnQuestion
            }
        }
        guard let next = candidates.first, let content = requestSignal(next) else { return false }
        show(content, for: next.sessionKey)
        return true
    }

    /// Ein wartendes Signal wird nie von „fertig“ oder „Fehler“ verdrängt.
    private func show(_ content: SignalContent, for key: String) {
        if let shown = model.activeSignal, shown.id != content.id, shown.kind.isAwaitingOwner, !content.kind.isAwaitingOwner,
           isPending(shown.id) {
            return
        }
        // Es ist immer nur ein Signal zu sehen; ältere Zuordnungen (auch von selbst geschlossenen) verfallen.
        signalSessions = [content.id: key]
        model.raiseSignal(content)
    }

    private func closeSignal(_ id: UUID) {
        guard model.activeSignal?.id == id else { return }
        signalSessions[id] = nil
        model.clearSignal(id)
    }

    /// Signale zu Anfragen tragen die ID der Anfrage, alle anderen eine eigene.
    private func isPending(_ id: UUID) -> Bool {
        book.pendingRequests().contains { $0.request.requestId == id }
    }

    // MARK: - Signal-Inhalte

    private func title(_ session: AgentSession) -> String {
        "\(session.projectName) · \(session.agent.displayName)"
    }

    private func requestSignal(_ entry: PendingEntry) -> SignalContent? {
        guard let session = book.sessions[entry.sessionKey] else { return nil }
        switch entry.request.kind {
        case .permission(let tool, let summary):
            let isShell = ["Bash", "exec_command", "shell"].contains(tool)
            return SignalContent(id: entry.request.requestId, agent: session.agent, title: title(session),
                                 subtitle: isShell ? L("Möchte ausführen:") : L("Möchte {0} verwenden:", tool),
                                 detail: summary, kind: .permission)
        case .question(let question):
            let more = question.moreCount > 0 ? " (+\(question.moreCount) weitere)" : ""
            return SignalContent(id: entry.request.requestId, agent: session.agent, title: title(session),
                                 subtitle: question.question + more, kind: .question(options: question.options))
        }
    }

    /// Der Agent wartet, ohne dass notchai die Frage kennt (`Notification`): Antwort geht über `ReplySender`.
    private func attentionSignal(_ key: String) -> SignalContent? {
        guard let session = book.sessions[key] else { return nil }
        return SignalContent(agent: session.agent, title: title(session), subtitle: L("Wartet auf dich"),
                             kind: .question(options: []))
    }

    private func statusSignal(_ key: String, trigger: SignalTrigger) -> SignalContent? {
        guard let session = book.sessions[key] else { return nil }
        let kind: SignalKind = trigger == .error ? .error : .done
        let fallback = trigger == .error ? L("Fehler") : L("Fertig")
        return SignalContent(agent: session.agent, title: title(session), subtitle: session.lastStep ?? fallback, kind: kind)
    }

    // MARK: - Entscheidungen

    /// Entscheidung aus Signal oder Session-Zeile. `id` ist die Signal-ID, bei Anfragen deren `requestId`.
    func decide(_ id: UUID, action: SignalAction) {
        if let entry = book.pendingRequests().first(where: { $0.request.requestId == id }) {
            let output: String
            switch (entry.request.kind, action) {
            case (.permission, .allow): output = HookOutput.permissionAllow()
            case (.permission, .deny): output = HookOutput.permissionDeny(message: L("In notchai abgelehnt"))
            case (.question(let question), .answer(let text)):
                output = HookOutput.questionAnswer(toolInput: entry.request.toolInput ?? .object([:]),
                                                   answers: [question.question: text])
            case (_, .dismiss): output = HookOutput.noDecision
            default: return
            }
            server?.reply(HookReply(requestId: id, stdout: output))
            closeSignal(id)
            process(book.resolvePending(requestId: id))
            refreshSessions()
            return
        }
        // Kein wartender Hook: „fertig“, „Fehler“ oder eine Frage, die nur im Terminal steht.
        let key = signalSessions[id]
        closeSignal(id)
        if case .answer(let text) = action, let key, let session = book.sessions[key] {
            reply(text, to: session)
        }
        showNextRequest()
    }

    /// Antwort aus Liste, Kreisen oder Signal an eine Session schicken.
    func reply(_ text: String, to session: AgentSession) {
        let current = self.settings
        Task { [weak self] in
            guard let self else { return }
            let result = await replies.send(text, to: session, settings: current)
            model.showNotice(result.notice)
        }
    }

    // MARK: - Ausgaben

    private func refreshSessions() {
        let visible = book.visibleSessions(settings: settings, now: Date())
        if visible != model.sessions { model.sessions = visible }
        onWaitingChange?(visible.contains { $0.status.isWaiting })
    }

    /// Woher die Sessions kommen und warum eine fehlt (Entwickler-Seite): Transkripte je Agent, dann jede bekannte
    /// Session mit Herkunft, Prozess und ob die Notch sie zeigt.
    func sessionSourcesText() -> String {
        let now = Date()
        let report = TranscriptLibrary.sourceReport(home: home, now: now, maxAgeHours: settings.sessionMaxAgeHours,
                                                    calendar: .current)
        return ([report, ""] + book.diagnosticLines(settings: settings, now: now)).joined(separator: "\n")
    }

    /// Die letzten Hook-Ereignisse als JSON-Zeilen (Entwickler-Seite der Einstellungen; hilft bei den offenen Mac-Prüfungen).
    func recentEventsText() -> String {
        recentEnvelopes.compactMap { try? HookWire.encodeLine($0) }
            .map { String(decoding: $0, as: UTF8.self) }
            .joined()
    }
}

import AppKit
import LumoCore
import Observation

/// Update-Knopf, je nach Herkunft der App:
/// - Aus einem Quellordner gebaut (`LumoSourceDirectory` in der `Info.plist`, gesetzt von `scripts/build-app.sh`):
///   neuen Stand per Git holen (`UpdateChecker`), bauen und neu starten.
/// - Fertige Version (Homebrew oder Download): neueste Version auf GitHub prüfen (`ReleaseCheck`). Mit Homebrew
///   installiert, aktualisiert `brew upgrade` und startet neu; sonst öffnet sich die Seite der Version.
@MainActor @Observable
final class UpdateController {
    /// Automatisch wird höchstens so oft nachgesehen.
    private static let interval: TimeInterval = 6 * 3600
    /// Erste automatische Prüfung kurz nach dem Start, wenn alles andere läuft.
    private static let startDelay: TimeInterval = 20

    let buildInfo: BuildInfo
    private(set) var state: UpdateState
    private(set) var lastChecked: Date?

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let checker: UpdateChecker?
    @ObservationIgnored private var timer: Timer?

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/lumo/update.log")
    }

    init(settingsStore: SettingsStore, bundle: Bundle = .main) {
        self.settingsStore = settingsStore
        buildInfo = BuildInfo(infoDictionary: bundle.infoDictionary ?? [:])
        checker = buildInfo.sourceDirectory.map {
            UpdateChecker(sourceDirectory: $0, runner: LoginShellRunner(), logPath: Self.logURL.path)
        }
        state = .idle
    }

    /// Homebrew, das diese App installiert hat (`nil` ohne Homebrew-Installation).
    private static var homebrew: String? {
        for prefix in ["/opt/homebrew", "/usr/local"]
        where FileManager.default.fileExists(atPath: "\(prefix)/Caskroom/lumo") {
            let brew = "\(prefix)/bin/brew"
            if FileManager.default.isExecutableFile(atPath: brew) { return brew }
        }
        return nil
    }

    /// Woher die Updates kommen (für die Einstellungen).
    var sourceDescription: String {
        if let source = buildInfo.sourceDirectory { return source }
        return Self.homebrew == nil ? "GitHub (\(ReleaseCheck.repository))" : "Homebrew"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .installing: true
        default: false
        }
    }

    /// Plant die automatischen Prüfungen (sofern eingeschaltet).
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.startDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
    }

    private func automaticCheck() {
        if settingsStore.settings.checkForUpdates, !isBusy {
            Task { await check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        if let checker {
            state = await checker.check()
        } else {
            state = await checkRelease()
        }
        lastChecked = Date()
    }

    /// Neueste Version auf GitHub; ohne veröffentlichte Version gilt lumo als aktuell. Antwortet die Schnittstelle
    /// nicht (Abfragelimit, Störung), zählt die Weiterleitung der Versionsseite; sie hat kein Limit.
    private func checkRelease() async -> UpdateState {
        let viaHomebrew = Self.homebrew != nil
        var request = URLRequest(url: ReleaseCheck.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("lumo/\(buildInfo.version)", forHTTPHeaderField: "User-Agent")
        let apiFailure: UpdateState
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .upToDate }
            if status == 200 {
                return ReleaseCheck.state(currentVersion: buildInfo.version, response: data, viaHomebrew: viaHomebrew)
            }
            apiFailure = .failed("GitHub antwortet nicht wie erwartet (\(status)).")
        } catch {
            apiFailure = .failed("GitHub ist nicht erreichbar: \(error.localizedDescription)")
        }
        var page = URLRequest(url: ReleaseCheck.latestPageURL, timeoutInterval: 15)
        page.setValue("lumo/\(buildInfo.version)", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: page),
              (response as? HTTPURLResponse)?.statusCode == 200, let final = response.url,
              let state = ReleaseCheck.state(currentVersion: buildInfo.version, releasePage: final, viaHomebrew: viaHomebrew) else {
            return apiFailure
        }
        return state
    }

    /// Kann der Knopf „Jetzt aktualisieren“ etwas tun?
    var canInstall: Bool {
        switch state {
        case .available, .releaseAvailable: true
        default: false
        }
    }

    /// Holt und baut den neuen Stand; danach ersetzt `scripts/install-app.sh` diese App und startet sie neu.
    func install() async {
        guard !isBusy else { return }
        guard let checker, let source = buildInfo.sourceDirectory else {
            await installRelease()
            return
        }
        if case .available = state {} else { await check() }
        guard case .available(let offer) = state else { return }
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        state = .installing("Starte …")
        let result = await checker.install(offer) { step in
            Task { @MainActor [weak self] in
                guard let self, case .installing = self.state else { return }
                self.state = .installing(step)
            }
        }
        switch result {
        case .success(let builtApp):
            state = .installing(L("Starte lumo neu …"))
            relaunch(builtApp: builtApp, source: source)
        case .failure(let error):
            state = .failed(error.message)
        }
    }

    /// Fertige Version: mit Homebrew aktualisieren und neu starten, sonst die Seite der Version öffnen.
    private func installRelease() async {
        if case .releaseAvailable = state {} else { await check() }
        guard case .releaseAvailable(let offer) = state else { return }
        guard offer.viaHomebrew, let brew = Self.homebrew else {
            if let url = URL(string: offer.pageURL) { NSWorkspace.shared.open(url) }
            return
        }
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        state = .installing(L("Homebrew aktualisiert lumo …"))
        // brew läuft in lumo; Homebrew beendet lumo deshalb nicht selbst. Ob es geklappt hat, zeigt danach die
        // Version im Programme-Ordner (`homebrewFinished`).
        let app = Bundle.main.bundlePath
        let script = ReleaseCheck.homebrewUpgradeScript(brew: brew, log: Self.logURL.path, app: app,
                                                        appPID: ProcessInfo.processInfo.processIdentifier)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.environment = ReleaseCheck.homebrewEnvironment(brew: brew, base: ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor [weak self] in self?.homebrewFinished(status: status, offer: offer) }
        }
        do {
            try process.run()
        } catch {
            state = .failed("Homebrew ließ sich nicht starten: \(error.localizedDescription)")
            return
        }
        // Hängt brew (Netz weg), endet das Update mit Fehler statt für immer mit „aktualisiert …“.
        let log = Self.logURL
        DispatchQueue.global().asyncAfter(deadline: .now() + ReleaseCheck.upgradeTimeout) {
            guard process.isRunning else { return }
            if let handle = try? FileHandle(forWritingTo: log) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("Abgebrochen: Homebrew hat nach \(Int(ReleaseCheck.upgradeTimeout / 60)) Minuten nicht geantwortet.\n".utf8))
            }
            process.terminate()
        }
    }

    /// Homebrew ist fertig: Liegt eine neuere Version im Programme-Ordner, beendet sich lumo und öffnet sie.
    private func homebrewFinished(status: Int32, offer: ReleaseOffer) {
        let app = Bundle.main.bundlePath
        switch ReleaseCheck.upgradeOutcome(exitStatus: status, installedVersion: Self.installedVersion(at: app),
                                           runningVersion: buildInfo.version, offeredVersion: offer.version) {
        case .relaunch:
            state = .installing(L("Starte lumo neu …"))
            let process = Process()
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-c", ReleaseCheck.relaunchScript(pid: ProcessInfo.processInfo.processIdentifier, app: app)]
            do {
                try process.run()
            } catch {
                state = .failed(L("Die neue Version ist installiert. Bitte lumo beenden und neu öffnen."))
                return
            }
            NSApp.terminate(nil)
        case .failed(let message):
            state = .failed(message)
        }
    }

    /// Version der App im Programme-Ordner, frisch von der Platte (`Bundle` hielte die alte fest).
    private static func installedVersion(at app: String) -> String? {
        let plist = URL(filePath: app).appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Übergibt an `scripts/install-app.sh`: Es wartet, bis diese App beendet ist, ersetzt sie durch die
    /// frisch gebaute und öffnet sie wieder.
    private func relaunch(builtApp: String, source: String) {
        let script = URL(filePath: source).appending(path: "scripts/install-app.sh").path
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [script, String(ProcessInfo.processInfo.processIdentifier), builtApp, Bundle.main.bundlePath]
        if let log = try? FileHandle(forWritingTo: Self.logURL) {
            _ = try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
        } catch {
            state = .failed("Neustart ging nicht: \(error.localizedDescription). Die neue Version liegt in \(builtApp).")
            return
        }
        NSApp.terminate(nil)
    }

    /// Kurzer Text für Menü und Einstellungen.
    var summary: String {
        switch state {
        case .idle: L("Noch nicht geprüft")
        case .checking: L("Suche nach Updates …")
        case .upToDate: L("lumo ist aktuell")
        case .available(let offer): Self.describe(offer)
        case .releaseAvailable(let offer):
            offer.viaHomebrew ? L("Version {0} ist da", offer.version) : L("Version {0} ist da (Download auf GitHub)", offer.version)
        case .blocked(let reason): reason
        case .installing(let step): step
        case .failed(let message): message
        case .unavailable(let reason): reason
        }
    }

    private static func describe(_ offer: UpdateOffer) -> String {
        let changes = offer.count == 1 ? L("1 neue Änderung") : L("{0} neue Änderungen", offer.count)
        guard let target = offer.switchTo else { return L("Update verfügbar: {0}", changes) }
        return L("Update verfügbar: Wechsel auf {0} ({1})", target, changes)
    }
}

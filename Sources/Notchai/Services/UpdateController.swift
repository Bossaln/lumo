import AppKit
import NotchaiCore
import Observation

/// Update-Knopf, je nach Herkunft der App:
/// - Aus einem Quellordner gebaut (`NotchaiSourceDirectory` in der `Info.plist`, gesetzt von `scripts/build-app.sh`):
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
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/notchai/update.log")
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
        where FileManager.default.fileExists(atPath: "\(prefix)/Caskroom/notchai") {
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

    /// Neueste Version auf GitHub; ohne veröffentlichte Version gilt notchai als aktuell.
    private func checkRelease() async -> UpdateState {
        var request = URLRequest(url: ReleaseCheck.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("notchai/\(buildInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .upToDate }
            guard status == 200 else { return .failed("GitHub antwortet nicht wie erwartet (\(status)).") }
            return ReleaseCheck.state(currentVersion: buildInfo.version, response: data, viaHomebrew: Self.homebrew != nil)
        } catch {
            return .failed("GitHub ist nicht erreichbar: \(error.localizedDescription)")
        }
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
            state = .installing("Starte notchai neu …")
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
        state = .installing("Homebrew aktualisiert notchai …")
        // Homebrew beendet notchai selbst (`uninstall quit:` im Cask); das Skript läuft weiter und öffnet die neue Version.
        let log = ShellQuote.quote(Self.logURL.path)
        let app = ShellQuote.quote(Bundle.main.bundlePath)
        let script = "\(ShellQuote.quote(brew)) upgrade --cask notchai >> \(log) 2>&1 && open \(app)"
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", script]
        // Läuft notchai danach noch, hat Homebrew nicht aktualisiert.
        process.terminationHandler = { [weak self] finished in
            guard finished.terminationStatus != 0 else { return }
            Task { @MainActor [weak self] in
                self?.state = .failed("Homebrew konnte notchai nicht aktualisieren. Details im Protokoll.")
            }
        }
        do {
            try process.run()
        } catch {
            state = .failed("Homebrew ließ sich nicht starten: \(error.localizedDescription)")
        }
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
        case .idle: "Noch nicht geprüft"
        case .checking: "Suche nach Updates …"
        case .upToDate: "notchai ist aktuell"
        case .available(let offer): Self.describe(offer)
        case .releaseAvailable(let offer):
            offer.viaHomebrew ? "Version \(offer.version) ist da" : "Version \(offer.version) ist da (Download auf GitHub)"
        case .blocked(let reason): reason
        case .installing(let step): step
        case .failed(let message): message
        case .unavailable(let reason): reason
        }
    }

    private static func describe(_ offer: UpdateOffer) -> String {
        let changes = offer.count == 1 ? "1 neue Änderung" : "\(offer.count) neue Änderungen"
        guard let target = offer.switchTo else { return "Update verfügbar: \(changes)" }
        return "Update verfügbar: Wechsel auf \(target) (\(changes))"
    }
}

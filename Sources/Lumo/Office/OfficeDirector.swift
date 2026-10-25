import AppKit
import LumoCore
import Observation

/// Hält die Lagerhalle am Laufen: Simulation aus den Sessions, Hintergrund je Tageslicht und ein Bild je Takt
/// (12 Bilder/s). Der Takt läuft nur, solange das Büro irgendwo sichtbar ist (Reiter oder großes Fenster).
@MainActor @Observable
final class OfficeDirector {
    private static let fps = 12.0
    /// Längste Zeit, die beim Öffnen nachgeholt wird (sonst stünden alle noch an der Treppe).
    private static let maxCatchUp: TimeInterval = 60

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var simulation = OfficeSimulation()
    @ObservationIgnored private var background: PixelCanvas?
    @ObservationIgnored private var backgroundLevel = -1.0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastStep: Date?
    @ObservationIgnored private var viewers = 0

    /// Aktuelles Bild der Halle (Pixel scharf anzeigen).
    private(set) var frame: CGImage?
    private(set) var agents: [OfficeAgent] = []
    /// 0 = Nacht, 1 = Tag (in Zehnteln, damit der Hintergrund selten neu gezeichnet wird).
    private(set) var daylight = 0.0
    private(set) var now = Date()

    /// Klick auf eine Figur: Fenster ihrer Session nach vorn holen.
    @ObservationIgnored var onFocus: ((AgentSession) -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    var settings: AppSettings { model.settingsStore.settings }

    /// Eine Ansicht zeigt das Büro; der Takt startet mit der ersten.
    func attach() {
        viewers += 1
        guard viewers == 1 else { return }
        catchUp()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { MainThreadWork.measure("Office.frame") { self?.tick() } }
        }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func focus(_ agent: OfficeAgent) {
        onFocus?(agent.session)
    }

    /// War das Büro zu, holt die Simulation die verpasste Zeit in großen Schritten nach.
    private func catchUp() {
        let now = Date()
        simulation.update(sessions: model.sessions, now: now)
        guard let last = lastStep else {
            lastStep = now
            return
        }
        let missed = min(now.timeIntervalSince(last), Self.maxCatchUp)
        var elapsed = 0.0
        while elapsed < missed {
            simulation.step(dt: 0.2, now: now.addingTimeInterval(elapsed - missed))
            elapsed += 0.2
        }
        lastStep = now
    }

    private func tick() {
        let now = Date()
        let dt = min(0.25, max(0, now.timeIntervalSince(lastStep ?? now)))
        lastStep = now
        let settings = settings
        simulation.update(sessions: model.sessions, now: now)
        simulation.step(dt: dt, now: now)
        let level = (Daylight.level(settings: settings, date: now) * 10).rounded() / 10
        if background == nil || level != backgroundLevel {
            background = OfficeArt.background(daylight: level)
            backgroundLevel = level
        }
        guard let background else { return }
        let colors = OfficeRenderer.Colors(claude: Self.rgba(settings.claudeColorHex), codex: Self.rgba(settings.codexColorHex))
        let canvas = OfficeRenderer.frame(background: background, agents: simulation.agents, colors: colors,
                                          time: now.timeIntervalSinceReferenceDate)
        frame = Self.image(canvas)
        agents = simulation.agents
        daylight = level
        self.now = now
    }

    static func rgba(_ hex: String) -> RGBA {
        let rgb = ColorHex.parse(hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        return RGBA(UInt8(rgb.r * 255), UInt8(rgb.g * 255), UInt8(rgb.b * 255))
    }

    /// Pixelpuffer als Bild (RGBA, nicht vormultipliert, deckend).
    static func image(_ canvas: PixelCanvas) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(canvas.rgbaBytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: canvas.width, height: canvas.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: canvas.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

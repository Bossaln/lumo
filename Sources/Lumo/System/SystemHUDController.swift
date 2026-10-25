import AppKit
import ApplicationServices
import Foundation
import LumoCore
import Observation

/// Bringt die Systemanzeigen von macOS in die Notch: Lautstärke, Helligkeit, Tastaturlicht, Fokus, Timer, Wecker,
/// Mikrofon und Kamera, Strom, Audioausgabe und Feststelltaste. Startet und stoppt die Beobachter nach den
/// Einstellungen und fängt auf Wunsch die Sondertasten ab, damit macOS seine eigene Einblendung nicht mehr zeigt.
@MainActor @Observable
final class SystemHUDController {
    /// Darf lumo Tasten in anderen Apps sehen und abfangen (Bedienungshilfen)?
    private(set) var accessibilityTrusted = AXIsProcessTrusted()
    /// Voller Festplattenzugriff (für Fokus, Timer und Wecker): `nil`, solange es nicht probiert wurde.
    var fullDiskAccess: Bool? { focus.access == true || clock.access == true ? true : (focus.access == nil && clock.access == nil ? nil : false) }
    /// Die Sondertasten werden abgefangen (Einblendung von macOS aus).
    private(set) var interceptsKeys = false
    var clockProblem: String? { clock.problem }
    var activeFocusName: String? { focus.state?.activeMode?.name }

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let audio = AudioDeviceWatcher()
    @ObservationIgnored private let camera = CameraWatcher()
    @ObservationIgnored private let brightness = DisplayBrightness()
    @ObservationIgnored private let backlight = KeyboardBacklight()
    @ObservationIgnored private let keys = MediaKeyTap()
    @ObservationIgnored private let power = PowerWatcher()
    @ObservationIgnored private let focus: FocusWatcher
    @ObservationIgnored private let clock: ClockWatcher
    @ObservationIgnored private let capsLock = CapsLockWatcher()
    @ObservationIgnored private var powerTracker = PowerTracker()
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var started = false
    /// Nach einem Gerätewechsel meldet Core Audio kurz die Lautstärke des neuen Geräts; das soll nicht den Hinweis
    /// auf das Gerät verdrängen.
    @ObservationIgnored private var deviceChangedAt = Date.distantPast
    @ObservationIgnored private var demoIndex = 0

    init(model: AppModel, settingsStore: SettingsStore, home: URL) {
        self.model = model
        self.settingsStore = settingsStore
        focus = FocusWatcher(home: home)
        clock = ClockWatcher(home: home)
    }

    func start() {
        guard !started else { return }
        started = true
        wire()
        apply()
        observeSettings()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
    }

    private var settings: AppSettings { settingsStore.settings }

    private func wire() {
        audio.onVolume = { [weak self] level, muted in
            guard let self, Date().timeIntervalSince(deviceChangedAt) > 1 else { return }
            show(.volume(level: level, muted: muted))
        }
        audio.onOutputDevice = { [weak self] name, transport in
            guard let self else { return }
            deviceChangedAt = Date()
            show(.audioOutput(name: name, symbol: AudioOutputKind.symbol(name: name, transport: transport)))
        }
        audio.onMicrophone = { [weak self] active in
            guard let self else { return }
            model.microphoneInUse = active && settings.shows(.microphone)
            show(.microphone(active: active))
        }
        camera.onCamera = { [weak self] active in
            guard let self else { return }
            model.cameraInUse = active && settings.shows(.camera)
            show(.camera(active: active))
        }
        keys.handler = { [weak self] press, modifiers in self?.handle(press, modifiers: modifiers) ?? false }
        power.onChange = { [weak self] state in
            guard let self, let indicator = powerTracker.update(state) else { return }
            show(indicator)
        }
        focus.onChange = { [weak self] mode, previous in
            guard let self else { return }
            show(mode.map(SystemIndicator.focus) ?? .focusOff(previous))
        }
        clock.onTimer = { [weak self] status in self?.timerChanged(status) }
        clock.onAlarm = { [weak self] status in self?.alarmChanged(status) }
        capsLock.onChange = { [weak self] on in self?.show(.capsLock(on: on)) }
    }

    /// Startet, was die Einstellungen verlangen, und stoppt den Rest.
    private func apply() {
        let settings = settings
        let any = settings.systemHUD
        run(audio, any && (settings.shows(.volume) || settings.shows(.audioOutput) || settings.shows(.microphone)))
        run(camera, any && settings.shows(.camera))
        run(power, any && settings.shows(.power))
        run(focus, any && settings.shows(.focus))
        run(clock, any && (settings.shows(.timer) || settings.shows(.alarm)))
        run(capsLock, any && settings.shows(.capsLock) && accessibilityTrusted)
        if !settings.shows(.microphone) { model.microphoneInUse = false }
        if !settings.shows(.camera) { model.cameraInUse = false }
        if !settings.shows(.timer) { model.endSystemIndicator(.timer) }
        if !settings.shows(.alarm) { model.endSystemIndicator(.alarm) }
        updateKeyTap()
    }

    private func run(_ watcher: AudioDeviceWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }
    private func run(_ watcher: CameraWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }
    private func run(_ watcher: PowerWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }
    private func run(_ watcher: FocusWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }
    private func run(_ watcher: ClockWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }
    private func run(_ watcher: CapsLockWatcher, _ wanted: Bool) { wanted ? watcher.start() : watcher.stop() }

    /// Abfangen, wenn die Einblendung von macOS aus sein soll und lumo darf; sonst nur mithören, damit Helligkeit
    /// und Tastaturlicht (ohne eigene Meldung von macOS) trotzdem in der Notch erscheinen.
    private func updateKeyTap() {
        let settings = settings
        let wantsKeys = settings.systemHUD && (settings.shows(.volume) || settings.shows(.brightness) || settings.shows(.keyboardBacklight))
        guard wantsKeys, accessibilityTrusted else {
            keys.stop()
            interceptsKeys = false
            return
        }
        let intercept = settings.suppressMacHUD
        keys.start(listenOnly: !intercept)
        interceptsKeys = keys.isActive && intercept
    }

    private func checkTrust() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let trusted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, trusted != self.accessibilityTrusted else { return }
                    self.accessibilityTrusted = trusted
                    self.apply()
                }
            }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            let settings = settingsStore.settings
            _ = settings.systemHUD
            _ = settings.hudHidden
            _ = settings.suppressMacHUD
            _ = settings.timerStaysVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                apply()
                if let status = clock.timerStatus { timerChanged(status) }
                observeSettings()
            }
        }
    }

    // MARK: - Anzeigen

    private func show(_ indicator: SystemIndicator) {
        guard settings.shows(indicator.kind) else { return }
        model.showSystemIndicator(indicator)
    }

    private func timerChanged(_ status: TimerStatus?) {
        guard settings.shows(.timer) else { return }
        switch status {
        case .running(let fireDate):
            var indicator = SystemIndicator.timerRunning(until: fireDate)
            indicator.sticky = settings.timerStaysVisible
            model.endSystemIndicator(.timer)
            model.showSystemIndicator(indicator)
        case .paused(let remaining):
            var indicator = SystemIndicator.timerPaused(remaining: remaining)
            indicator.sticky = settings.timerStaysVisible
            model.endSystemIndicator(.timer)
            model.showSystemIndicator(indicator)
        case .fired:
            model.showSystemIndicator(.timerFired())
        case nil:
            model.endSystemIndicator(.timer)
        }
    }

    private func alarmChanged(_ status: AlarmStatus?) {
        guard settings.shows(.alarm) else { return }
        switch status {
        case .ringing(let title):
            model.showSystemIndicator(.alarmRinging(title: title))
        case .snoozed(let until):
            model.endSystemIndicator(.alarm)
            model.showSystemIndicator(.alarmSnoozed(until: until))
        case nil:
            model.endSystemIndicator(.alarm)
        }
    }

    // MARK: - Sondertasten

    /// Stellt Lautstärke, Helligkeit und Tastaturlicht selbst, wenn lumo die Tasten abfängt; `true` heißt, macOS
    /// bekommt die Taste nicht mehr.
    private func handle(_ press: MediaKeyPress, modifiers: MediaKeyTap.Modifiers) -> Bool {
        guard press.key.isHandledByLumo, !modifiers.optionOnly else { return false }
        let settings = settings
        // Losgelassene Tasten schlucken, sonst sähe macOS ein Loslassen ohne Drücken.
        guard press.down else { return interceptsKeys }
        switch press.key {
        case .soundUp, .soundDown:
            guard settings.shows(.volume) else { return false }
            guard interceptsKeys else { return false }
            guard audio.canSetVolume, let level = audio.volume else { return false }
            let next = MediaKeys.adjusted(level, up: press.key == .soundUp, fine: modifiers.fine)
            audio.setVolume(next)
            if next > 0, audio.isMuted { audio.setMuted(false) }
            show(.volume(level: next, muted: next == 0))
            Self.playVolumeFeedback()
            return true
        case .mute:
            guard settings.shows(.volume), interceptsKeys, audio.canSetVolume else { return false }
            let muted = !audio.isMuted
            audio.setMuted(muted)
            show(.volume(level: audio.volume ?? 0, muted: muted))
            return true
        case .brightnessUp, .brightnessDown:
            guard settings.shows(.brightness) else { return false }
            guard interceptsKeys else {
                readSoon { [weak self] in self?.brightness.level.map { self?.show(.brightness(level: $0)) } }
                return false
            }
            guard brightness.isAvailable, let level = brightness.level else { return false }
            let next = MediaKeys.adjusted(level, up: press.key == .brightnessUp, fine: modifiers.fine)
            brightness.setLevel(next)
            show(.brightness(level: next))
            return true
        case .illuminationUp, .illuminationDown:
            guard settings.shows(.keyboardBacklight) else { return false }
            guard interceptsKeys else {
                readSoon { [weak self] in self?.backlight.level.map { self?.show(.keyboardBacklight(level: $0)) } }
                return false
            }
            guard backlight.isAvailable, let level = backlight.level else { return false }
            let next = MediaKeys.adjusted(level, up: press.key == .illuminationUp, fine: modifiers.fine)
            backlight.setLevel(next)
            show(.keyboardBacklight(level: next))
            return true
        case .illuminationToggle:
            guard settings.shows(.keyboardBacklight) else { return false }
            guard interceptsKeys else {
                readSoon { [weak self] in self?.backlight.level.map { self?.show(.keyboardBacklight(level: $0)) } }
                return false
            }
            guard let level = backlight.toggle() else { return false }
            show(.keyboardBacklight(level: level))
            return true
        default:
            return false
        }
    }

    /// Im Mithör-Modus stellt macOS den Wert erst nach dem Tastendruck; kurz danach lesen.
    private func readSoon(_ read: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            read()
            try? await Task.sleep(for: .milliseconds(250))
            read()
        }
    }

    /// Der Klick beim Ändern der Lautstärke, wenn er in den Systemeinstellungen (Ton) an ist; den spielt sonst macOS.
    private static func playVolumeFeedback() {
        guard UserDefaults.standard.integer(forKey: "com.apple.sound.beep.feedback") == 1 else { return }
        let url = URL(fileURLWithPath: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff")
        NSSound(contentsOf: url, byReference: true)?.play()
    }

    // MARK: - Ausprobieren

    /// Einstellungen › System: Bei jedem Klick die nächste Anzeige, auch ohne Tasten, Timer oder Fokus.
    func preview() {
        let samples: [SystemIndicator] = [
            .volume(level: 0.56, muted: false),
            .brightness(level: 0.8),
            .keyboardBacklight(level: 0.4),
            .focus(FocusMode(identifier: "demo", name: L("Arbeiten"), symbol: "briefcase.fill", tint: FocusTint.rgb(named: "teal"))),
            .timerRunning(until: Date().addingTimeInterval(95)),
            .alarmRinging(title: L("Aufstehen")),
            .microphone(active: true),
            .camera(active: true),
            .power(charging: true, level: 0.67),
            .lowBattery(level: 0.1),
            .audioOutput(name: "AirPods Pro", symbol: "airpodspro"),
            .capsLock(on: true),
        ]
        var sample = samples[demoIndex % samples.count]
        demoIndex += 1
        // Zum Ausprobieren bleibt nichts stehen.
        sample.sticky = false
        model.showSystemIndicator(sample)
    }

    static func openAccessibilitySettings() {
        DoubleTapHotkeys.openAccessibilitySettings()
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

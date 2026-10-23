import AppKit
import ApplicationServices
import NotchaiCore
import Observation

/// Tastenkürzel aus zweimal Antippen einer Sondertaste, auch wenn eine andere App vorn ist:
/// - zweimal rechte ⌘ öffnet oder schließt das große Büro (Einstellung `officeHotkey`),
/// - zweimal ⌃ öffnet eine Schnellnotiz in der Notch (Einstellung `notesHotkey`).
/// Tasten in anderen Apps sieht notchai nur mit der Berechtigung „Bedienungshilfen“; ohne sie gehen Büro und
/// Notizen über ihre Reiter in der Notch.
@MainActor
final class DoubleTapHotkeys {
    private let settingsStore: SettingsStore
    private var monitors: [Any] = []
    private var office = ModifierTapTracker(key: .rightCommand)
    private var note = ModifierTapTracker(key: .control)
    /// Prüft, ob die Berechtigung inzwischen erteilt wurde; die Monitore werden dann neu angelegt.
    private var trustTimer: Timer?
    private var wasTrusted = false
    /// Stand der Einstellungen (Büro, Notiz), für den die Monitore angelegt sind.
    private var installedFor: [Bool]?

    var onOffice: (() -> Void)?
    var onNote: (() -> Void)?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func start() {
        wasTrusted = AXIsProcessTrusted()
        Self.isTrusted = wasTrusted
        install()
        observeSettings()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
    }

    /// Darf notchai Tasten in anderen Apps sehen? Zuletzt geprüfter Stand (alle 5 s, im Hintergrund).
    private(set) static var isTrusted = false

    /// Öffnet Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private var wanted: [Bool] {
        [settingsStore.settings.officeHotkey, settingsStore.settings.notesHotkey]
    }

    private func install() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        office = ModifierTapTracker(key: .rightCommand)
        note = ModifierTapTracker(key: .control)
        installedFor = wanted
        guard wanted.contains(true) else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        // Nur die Werte gehen in den MainActor, nicht das Ereignis selbst.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let (type, keyCode, flags) = (event.type, event.keyCode, UInt64(event.modifierFlags.rawValue))
            MainActor.assumeIsolated { self?.handle(type, keyCode: keyCode, flags: flags) }
        }) {
            monitors.append(global)
        }
        // In notchais eigenen Fenstern (Büro, Einstellungen) kommen die Tasten über den lokalen Monitor.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let (type, keyCode, flags) = (event.type, event.keyCode, UInt64(event.modifierFlags.rawValue))
            MainActor.assumeIsolated { self?.handle(type, keyCode: keyCode, flags: flags) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ type: NSEvent.EventType, keyCode: UInt16, flags: UInt64) {
        let settings = settingsStore.settings
        if type == .flagsChanged {
            let now = Date()
            if office.flagsChanged(keyCode: keyCode, flags: flags, at: now), settings.officeHotkey { onOffice?() }
            if note.flagsChanged(keyCode: keyCode, flags: flags, at: now), settings.notesHotkey { onNote?() }
        } else {
            office.keyDown()
            note.keyDown()
        }
    }

    /// Die Abfrage geht an einen anderen Prozess und kann dauern; sie läuft deshalb im Hintergrund.
    private func checkTrust() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let trusted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Self.isTrusted = trusted
                    guard let self, trusted != self.wasTrusted else { return }
                    self.wasTrusted = trusted
                    self.install()
                }
            }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = wanted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if wanted != installedFor { install() }
                observeSettings()
            }
        }
    }
}

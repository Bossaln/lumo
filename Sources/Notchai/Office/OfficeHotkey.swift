import AppKit
import ApplicationServices
import NotchaiCore
import Observation

/// Zweimal rechte ⌘ öffnet oder schließt das große Büro (Einstellung `officeHotkey`).
/// Tasten in anderen Apps sieht notchai nur mit der Berechtigung „Bedienungshilfen“; ohne sie öffnet sich
/// das Büro über den Reiter „Büro“ in der Notch.
@MainActor
final class OfficeHotkey {
    private let settingsStore: SettingsStore
    private var monitors: [Any] = []
    private var tracker = RightCommandTapTracker()
    /// Prüft, ob die Berechtigung inzwischen erteilt wurde; die Monitore werden dann neu angelegt.
    private var trustTimer: Timer?
    private var wasTrusted = false
    /// Stand der Einstellung, für den die Monitore angelegt sind.
    private var installedFor: Bool?

    var onTrigger: (() -> Void)?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func start() {
        wasTrusted = AXIsProcessTrusted()
        install()
        observeSetting()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
    }

    /// Darf notchai Tasten in anderen Apps sehen?
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Öffnet Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func install() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        tracker = RightCommandTapTracker()
        installedFor = settingsStore.settings.officeHotkey
        guard settingsStore.settings.officeHotkey else { return }
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
        if type == .flagsChanged {
            if tracker.flagsChanged(keyCode: keyCode, flags: flags, at: .now) { onTrigger?() }
        } else {
            tracker.keyDown()
        }
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        install()
    }

    private func observeSetting() {
        withObservationTracking {
            _ = settingsStore.settings.officeHotkey
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if settingsStore.settings.officeHotkey != installedFor { install() }
                observeSetting()
            }
        }
    }
}

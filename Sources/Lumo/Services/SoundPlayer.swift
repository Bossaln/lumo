import AppKit
import LumoCore

/// Kurze Systemtöne zu Signalen; still, wenn Töne in den Einstellungen aus sind.
@MainActor
final class SoundPlayer {
    func play(_ trigger: SignalTrigger, settings: AppSettings) {
        guard settings.soundsEnabled else { return }
        let name = switch trigger {
        case .permission, .question: "Ping"
        case .done: "Glass"
        case .error: "Basso"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

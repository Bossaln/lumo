import Foundation
import IOKit.ps
import LumoCore

/// Meldet jede Änderung der Stromversorgung (Netzteil, Füllstand) über IOKit.
@MainActor
final class PowerWatcher {
    var onChange: ((PowerState) -> Void)?
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let watcher = Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.report() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            return
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        report()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    /// Liest den Stand; ohne Batterie zählt nur, ob Netzstrom anliegt.
    static func current() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var external = providing == kIOPSACPowerValue
        var level: Double?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let state = description[kIOPSPowerSourceStateKey] as? String { external = external || state == kIOPSACPowerValue }
            if let current = description[kIOPSCurrentCapacityKey] as? Double, let max = description[kIOPSMaxCapacityKey] as? Double, max > 0 {
                level = current / max
            }
        }
        return PowerState(external: external, level: level)
    }

    private func report() {
        guard let state = Self.current() else { return }
        onChange?(state)
    }
}

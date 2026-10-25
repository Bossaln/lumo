import AppKit
import Foundation

/// Meldet, wenn die Feststelltaste ein- oder ausgeschaltet wird. In anderen Apps sieht lumo die Taste nur mit der
/// Berechtigung „Bedienungshilfen“.
@MainActor
final class CapsLockWatcher {
    var onChange: ((Bool) -> Void)?
    private var monitors: [Any] = []
    private var capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    private static let capsLockKeyCode: UInt16 = 57

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let (keyCode, on) = (event.keyCode, event.modifierFlags.contains(.capsLock))
            MainActor.assumeIsolated { self?.handle(keyCode: keyCode, on: on) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let (keyCode, on) = (event.keyCode, event.modifierFlags.contains(.capsLock))
            MainActor.assumeIsolated { self?.handle(keyCode: keyCode, on: on) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func handle(keyCode: UInt16, on: Bool) {
        guard keyCode == Self.capsLockKeyCode, on != capsLockOn else { return }
        capsLockOn = on
        onChange?(on)
    }
}

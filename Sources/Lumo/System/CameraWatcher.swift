import CoreMediaIO
import Foundation

/// Beobachtet über Core Media I/O, ob irgendeine Kamera gerade von einer App benutzt wird.
@MainActor
final class CameraWatcher {
    var onCamera: ((Bool) -> Void)?
    private(set) var cameraActive = false
    private var listeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var started = false

    private static let system = CMIOObjectID(kCMIOObjectSystemObject)

    func start() {
        guard !started else { return }
        started = true
        let devicesAddress = Self.address(kCMIOHardwarePropertyDevices)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.devicesChanged() } }
        var mutable = devicesAddress
        if CMIOObjectAddPropertyListenerBlock(Self.system, &mutable, DispatchQueue.main, block) == noErr {
            listeners.append((Self.system, devicesAddress, block))
        }
        devicesChanged()
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners = []
        started = false
    }

    private func devicesChanged() {
        for (object, address, block) in listeners where object != Self.system {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners.removeAll { $0.0 != Self.system }
        for device in Self.devices() {
            let address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.cameraChanged() } }
            var mutable = address
            if CMIOObjectAddPropertyListenerBlock(device, &mutable, DispatchQueue.main, block) == noErr {
                listeners.append((device, address, block))
            }
        }
        cameraChanged()
    }

    private func cameraChanged() {
        let active = listeners.contains { $0.0 != Self.system && Self.isRunningSomewhere($0.0) }
        guard active != cameraActive else { return }
        cameraActive = active
        onCamera?(active)
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func devices() -> [CMIOObjectID] {
        var size: UInt32 = 0
        var address = address(kCMIOHardwarePropertyDevices)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    private static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        var running: UInt32 = 0
        var used: UInt32 = 0
        var address = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr && running != 0
    }
}

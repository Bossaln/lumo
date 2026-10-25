import AudioToolbox
import CoreAudio
import Foundation
import LumoCore

/// Beobachtet Core Audio: Lautstärke und Stummschaltung des Ausgabegeräts, Wechsel des Ausgabegeräts und ob
/// irgendein Eingabegerät (Mikrofon) gerade von einer App benutzt wird. Alles öffentliche Schnittstellen; die
/// Rückrufe kommen auf dem Hauptthread.
@MainActor
final class AudioDeviceWatcher {
    var onVolume: ((Double, Bool) -> Void)?
    /// Name und Transportcode (`AudioOutputKind.transportCode`) des neuen Ausgabegeräts.
    var onOutputDevice: ((String, String?) -> Void)?
    var onMicrophone: ((Bool) -> Void)?

    private var outputDevice = AudioDeviceID(kAudioObjectUnknown)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var inputListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var started = false
    private(set) var microphoneActive = false

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        guard !started else { return }
        started = true
        listen(Self.system, Self.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in self?.outputDeviceChanged(announce: true) }
        listen(Self.system, Self.address(kAudioHardwarePropertyDevices)) { [weak self] in self?.devicesChanged() }
        outputDeviceChanged(announce: false)
        devicesChanged()
    }

    func stop() {
        for (object, address, block) in listeners + inputListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners = []
        inputListeners = []
        started = false
    }

    // MARK: - Lautstärke

    /// Lautstärke 0…1 des Ausgabegeräts; `nil`, wenn es keine hat (etwa Bildschirme über HDMI).
    var volume: Double? {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
        guard outputDevice != kAudioObjectUnknown,
              AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &level) == noErr else { return nil }
        return Double(level)
    }

    var isMuted: Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard outputDevice != kAudioObjectUnknown,
              AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    /// Lässt sich die Lautstärke überhaupt stellen? Sonst bleibt die Taste bei macOS.
    var canSetVolume: Bool {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
        var settable = DarwinBoolean(false)
        guard outputDevice != kAudioObjectUnknown,
              AudioObjectIsPropertySettable(outputDevice, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    @discardableResult
    func setVolume(_ level: Double) -> Bool {
        var value = Float32(min(max(level, 0), 1))
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
        guard outputDevice != kAudioObjectUnknown else { return false }
        return AudioObjectSetPropertyData(outputDevice, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard outputDevice != kAudioObjectUnknown else { return false }
        return AudioObjectSetPropertyData(outputDevice, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    // MARK: - Geräte

    private func outputDeviceChanged(announce: Bool) {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &device) == noErr else { return }
        guard device != outputDevice else { return }
        // Die Lautstärke-Beobachter hängen am alten Gerät.
        for (object, address, block) in listeners where object == outputDevice {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners.removeAll { $0.0 == outputDevice }
        outputDevice = device
        guard device != kAudioObjectUnknown else { return }
        listen(device, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)) { [weak self] in
            self?.volumeChanged()
        }
        listen(device, Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)) { [weak self] in self?.volumeChanged() }
        if announce, let name = Self.name(of: device) {
            onOutputDevice?(name, Self.transport(of: device))
        }
    }

    private func volumeChanged() {
        guard let volume else { return }
        onVolume?(volume, isMuted)
    }

    /// Alle Eingabegeräte neu einsammeln (angesteckt, entfernt) und beobachten, ob eines läuft.
    private func devicesChanged() {
        for (object, address, block) in inputListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        inputListeners = []
        for device in Self.inputDevices() {
            let address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.microphoneChanged() }
            }
            var mutable = address
            if AudioObjectAddPropertyListenerBlock(device, &mutable, DispatchQueue.main, block) == noErr {
                inputListeners.append((device, address, block))
            }
        }
        microphoneChanged()
    }

    private func microphoneChanged() {
        let active = inputListeners.contains { Self.isRunningSomewhere($0.0) }
        guard active != microphoneActive else { return }
        microphoneActive = active
        onMicrophone?(active)
    }

    // MARK: - Core-Audio-Hilfen

    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping @MainActor () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        var mutable = address
        if AudioObjectAddPropertyListenerBlock(object, &mutable, DispatchQueue.main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Geräte mit Eingabekanälen, ohne lumos eigenen Tonabgriff (ein zusammengesetztes Gerät) und andere
    /// zusammengesetzte Geräte.
    private static func inputDevices() -> [AudioDeviceID] {
        var size: UInt32 = 0
        var address = address(kAudioHardwarePropertyDevices)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            guard transport(of: device) != "grup", hasInput(device) else { return false }
            return !(name(of: device)?.localizedCaseInsensitiveContains("lumo") ?? false)
        }
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    static func name(of device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    static func transport(of device: AudioDeviceID) -> String? {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return nil }
        return AudioOutputKind.transportCode(transport)
    }
}

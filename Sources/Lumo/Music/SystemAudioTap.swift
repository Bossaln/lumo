import CoreAudio
import Foundation
import LumoCore

/// Greift den Ton ab, der gerade spielt, ohne ihn zu verändern (Core-Audio-Tap, ab macOS 14.2). Bevorzugt nur die
/// Prozesse des Players samt Helfern (Chrome spielt über „Google Chrome Helper“), sonst alles außer lumo selbst.
/// Die Samples landen im `AudioSampleRing`; nichts wird gespeichert oder verschickt.
///
/// Beim ersten Start fragt macOS, ob lumo Systemaudio aufnehmen darf. Ohne Freigabe kommen nur Nullen an.
/// Aufrufe nur aus einer seriellen Warteschlange (`MusicVisualizer`): Anlegen und Abbauen dauert einige Millisekunden.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) (\(status))" }
    }

    private let ring: AudioSampleRing
    private let ioQueue = DispatchQueue(label: "com.bossaln.lumo.audio-tap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Abtastrate des abgegriffenen Tons.
    private(set) var sampleRate: Double = 48_000
    /// Nur der Player (`true`) oder alles außer lumo (`false`).
    private(set) var tapsPlayerOnly = false

    init(ring: AudioSampleRing) {
        self.ring = ring
    }

    deinit {
        stop()
    }

    /// Startet den Abgriff neu; `bundleId` ist der Player, `nil` heißt alles.
    func start(bundleId: String?) throws {
        stop()
        ring.reset()
        let player = bundleId.map(Self.playingProcesses(of:)) ?? []
        tapsPlayerOnly = !player.isEmpty
        let description = player.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcess().map { [$0] } ?? [])
            : CATapDescription(stereoMixdownOfProcesses: player)
        description.uuid = UUID()
        description.name = "lumo"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        do {
            try Self.check("Tap", AudioHardwareCreateProcessTap(description, &tapID))
            var format = AudioStreamBasicDescription()
            try Self.check("Format", Self.read(tapID, kAudioTapPropertyFormat, into: &format))
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else { throw Failure(step: "Format", status: -1) }
            sampleRate = format.mSampleRate
            let output = try Self.defaultOutputUID()
            // Privates Aggregat-Gerät aus der Ausgabe und dem Tap; niemand sonst sieht es.
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "lumo",
                kAudioAggregateDeviceUIDKey: "com.bossaln.lumo.tap." + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            try Self.check("Aggregat", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
            let ring = self.ring
            try Self.check("IOProc", AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, input, _, _, _ in
                Self.copy(input, into: ring)
            })
            try Self.check("Start", AudioDeviceStart(aggregateID, procID))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                _ = AudioDeviceStop(aggregateID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != AudioObjectID(kAudioObjectUnknown) { _ = AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Läuft im Audio-Thread: Stereo (verschachtelt oder je Kanal ein Puffer) als Mono in den Ringpuffer.
    private static func copy(_ input: UnsafePointer<AudioBufferList>, into ring: AudioSampleRing) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let left = UnsafePointer(data.assumingMemoryBound(to: Float.self))
        let channels = max(Int(first.mNumberChannels), 1)
        if channels == 1, buffers.count > 1, let second = buffers[1].mData {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            ring.write(left, UnsafePointer(second.assumingMemoryBound(to: Float.self)), frames: frames, stride: 1)
        } else {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            ring.write(left, channels > 1 ? left + 1 : nil, frames: frames, stride: channels)
        }
    }

    // MARK: - Core-Audio-Eigenschaften

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure(step: step, status: status) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Liest einen Wert fester Größe (Zahl, Struktur); Texte über `readString`.
    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                into value: inout T) -> OSStatus {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        // Core Audio übergibt den Text mit +1; wir geben ihn wieder frei.
        return value.takeRetainedValue() as String
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioDeviceID(kAudioObjectUnknown)
        try check("Ausgabe", read(system, kAudioHardwarePropertyDefaultSystemOutputDevice, into: &device))
        guard let uid = readString(device, kAudioDevicePropertyDeviceUID) else { throw Failure(step: "Ausgabe", status: -1) }
        return uid
    }

    /// Prozesse des Players (gleiche Bundle-ID oder ein Helfer darunter), die gerade Ton ausgeben.
    private static func playingProcesses(of bundleId: String) -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.filter { object in
            guard let id = readString(object, kAudioProcessPropertyBundleID),
                  id == bundleId || id.hasPrefix(bundleId + ".") else { return false }
            var running: UInt32 = 0
            return read(object, kAudioProcessPropertyIsRunningOutput, into: &running) == noErr && running != 0
        }
    }

    /// lumo selbst (Signal-Töne gehören nicht in die Balken); `nil`, solange lumo nie Ton ausgegeben hat.
    private static func ownProcess() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != AudioObjectID(kAudioObjectUnknown) ? object : nil
    }
}

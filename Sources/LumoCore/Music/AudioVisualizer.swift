import Foundation

/// Frequenzen eines Tonausschnitts: Hann-Fenster und schnelle Fourier-Transformation (Radix 2).
/// Tabellen und Arbeitsspeicher entstehen einmal; jeder Aufruf rechnet nur noch.
public struct SpectrumAnalyzer: Sendable {
    public let size: Int
    private let window: [Float]
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let reversed: [Int]
    private var real: [Float]
    private var imaginary: [Float]

    public static func isValidSize(_ size: Int) -> Bool { size >= 2 && size & (size - 1) == 0 }

    public init(size: Int) {
        precondition(Self.isValidSize(size), "Größe muss eine Zweierpotenz sein")
        self.size = size
        window = (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
        cosTable = (0..<size / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<size / 2).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
        let bits = size.trailingZeroBitCount
        reversed = (0..<size).map { index in
            var value = 0
            for bit in 0..<bits where index & (1 << bit) != 0 { value |= 1 << (bits - 1 - bit) }
            return value
        }
        real = [Float](repeating: 0, count: size)
        imaginary = [Float](repeating: 0, count: size)
    }

    /// Beträge der Frequenzen 0 … size/2 − 1. Ein voller Sinus genau auf einer Frequenz ergibt dort 0,5
    /// (Hann-Fenster). Weniger Samples als `size` werden mit Stille aufgefüllt.
    public mutating func magnitudes(of samples: [Float]) -> [Float] {
        let n = size
        let count = min(samples.count, n)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                for index in 0..<n {
                    let target = reversed[index]
                    re[target] = index < count ? samples[index] * window[index] : 0
                    im[target] = 0
                }
                var length = 2
                while length <= n {
                    let half = length / 2, step = n / length
                    for start in stride(from: 0, to: n, by: length) {
                        for k in 0..<half {
                            let wr = cosTable[k * step], wi = -sinTable[k * step]
                            let a = start + k, b = a + half
                            let tr = re[b] * wr - im[b] * wi
                            let ti = re[b] * wi + im[b] * wr
                            re[b] = re[a] - tr
                            im[b] = im[a] - ti
                            re[a] += tr
                            im[a] += ti
                        }
                    }
                    length *= 2
                }
            }
        }
        let scale = 2 / Float(n)
        return (0..<n / 2).map { (real[$0] * real[$0] + imaginary[$0] * imaginary[$0]).squareRoot() * scale }
    }
}

/// Macht aus dem Spektrum die Höhen der Balken (0…1): je Balken ein Frequenzband (logarithmisch verteilt, tief
/// links). Hoch geht es schnell, runter weich; über jedem Balken schwebt seine Spitze und sinkt langsam nach.
///
/// Eingepegelt wird je nach `Leveling`: je Band (wenige Balken schlagen auch bei leiser Musik voll aus, der Bass
/// verdeckt die Höhen nicht) oder gemeinsam (viele Balken zeigen die Form des Klangs wie ein echter Visualizer).
public struct VisualizerBars: Sendable {
    public enum Leveling: Hashable, Sendable {
        /// Jedes Band pegelt sich selbst ein.
        case perBand
        /// Alle Bänder teilen sich einen Pegel; die Höhen werden leicht angehoben, wie man sie hört.
        case shared
    }

    public static let lowestFrequency = 50.0
    public static let highestFrequency = 12_000.0
    /// Darunter gilt ein Band als still (Energie in dB, voller Sinus = −6 dB).
    static let silence = -70.0
    /// So viele dB unter dem bisher Lautesten steht ein Balken unten.
    static let range = 24.0
    static let sharedRange = 30.0
    /// Anhebung je Oktave über der tiefsten Frequenz, bei gemeinsamer Pegelung.
    static let tiltPerOctave = 1.5
    /// So schnell sinkt das bisher Lauteste, damit sich die Balken an leisere Stellen anpassen.
    static let loudestDecayPerSecond = 4.0
    /// Zeitkonstanten (Sekunden) für Steigen und Fallen.
    static let attack = 0.03
    static let release = 0.12
    /// So schnell sinkt eine Spitze (Balkenhöhen pro Sekunde).
    static let peakFallPerSecond = 0.8

    public let count: Int
    public let leveling: Leveling
    /// Grenzen der Bänder in Frequenz-Indizes (count + 1 Werte, aufsteigend).
    public let bandEdges: [Int]
    public private(set) var levels: [Double]
    /// Spitzen über den Balken (0…1), nie unter dem Balken.
    public private(set) var peaks: [Double]
    /// Anhebung je Band in dB (nur bei gemeinsamer Pegelung).
    private let tilt: [Double]
    /// Bisher Lautestes je Band (bzw. gemeinsam an Stelle 0), in dB.
    private var loudest: [Double?]

    public init(count: Int, sampleRate: Double, fftSize: Int, leveling: Leveling = .perBand) {
        self.count = count
        self.leveling = leveling
        let bins = fftSize / 2
        let binWidth = sampleRate / Double(fftSize)
        let ratio = pow(Self.highestFrequency / Self.lowestFrequency, 1 / Double(max(count, 1)))
        var edges: [Int] = []
        for index in 0...count {
            let frequency = Self.lowestFrequency * pow(ratio, Double(index))
            var bin = min(max(Int((frequency / binWidth).rounded()), 1), bins)
            // Jedes Band mindestens eine Frequenz breit.
            if let last = edges.last, bin <= last { bin = min(last + 1, bins) }
            edges.append(bin)
        }
        bandEdges = edges
        tilt = (0..<count).map { index in
            guard leveling == .shared else { return 0 }
            // Mitte des Bandes in Oktaven über der tiefsten Frequenz.
            return Self.tiltPerOctave * (Double(index) + 0.5) * log2(ratio)
        }
        levels = [Double](repeating: 0, count: count)
        peaks = [Double](repeating: 0, count: count)
        loudest = [Double?](repeating: nil, count: count)
    }

    /// Neue Höhen aus dem Spektrum eines Bildes; `dt` ist die Zeit seit dem letzten Bild.
    @discardableResult
    public mutating func update(magnitudes: [Float], dt: TimeInterval) -> [Double] {
        let dt = max(dt, 0)
        let decibels = (0..<count).map { band -> Double in
            let lower = bandEdges[band], upper = min(bandEdges[band + 1], magnitudes.count)
            var energy = 0.0
            if lower < upper {
                for bin in lower..<upper { energy += Double(magnitudes[bin] * magnitudes[bin]) }
            }
            return 10 * log10(energy + 1e-20)
        }
        let targets: [Double]
        switch leveling {
        case .perBand:
            targets = (0..<count).map { band in
                level(decibels[band], slot: band, range: Self.range, loudestNow: decibels[band], dt: dt)
            }
        case .shared:
            let shown = zip(decibels, tilt).map { $0 > Self.silence ? $0 + $1 : $0 }
            let loudestNow = shown.filter { $0 > Self.silence }.max() ?? Self.silence
            // Den gemeinsamen Pegel einmal je Bild nachführen, dann alle Bänder daran messen.
            _ = level(loudestNow, slot: 0, range: Self.sharedRange, loudestNow: loudestNow, dt: dt)
            targets = shown.map { value in
                guard value > Self.silence, let reference = loudest[0] else { return 0 }
                return min(max((value - (reference - Self.sharedRange)) / Self.sharedRange, 0), 1)
            }
        }
        for band in 0..<count {
            let constant = targets[band] > levels[band] ? Self.attack : Self.release
            levels[band] += (targets[band] - levels[band]) * (1 - exp(-dt / constant))
            if levels[band] < 0.001 { levels[band] = 0 }
            peaks[band] = max(levels[band], peaks[band] - Self.peakFallPerSecond * dt)
            if peaks[band] < 0.001 { peaks[band] = 0 }
        }
        return levels
    }

    /// Führt das bisher Lauteste an Stelle `slot` nach und misst `value` daran (0…1); Stille ergibt 0.
    private mutating func level(_ value: Double, slot: Int, range: Double, loudestNow: Double, dt: TimeInterval) -> Double {
        guard value > Self.silence else { return 0 }
        let decayed = (loudest[slot] ?? loudestNow) - Self.loudestDecayPerSecond * dt
        let reference = max(loudestNow, decayed, Self.silence + range)
        loudest[slot] = reference
        return min(max((value - (reference - range)) / range, 0), 1)
    }
}

/// Die jüngsten Samples des abgegriffenen Tons (Mono). Geschrieben wird aus dem Audio-Thread, gelesen beim Zeichnen;
/// beide Seiten halten die Sperre nur für ein Kopieren.
public final class AudioSampleRing: @unchecked Sendable {
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let lock = NSLock()
    private var writeIndex = 0
    private var written = 0
    private var total = 0
    private var heardSound = false

    public init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Hängt `frames` Samples an: aus `left` (und, falls da, gemittelt mit `right`), jedes `stride`-te.
    /// Für verschachteltes Stereo zeigt `right` auf `left + 1` und `stride` ist 2.
    public func write(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>?, frames: Int, stride: Int) {
        lock.lock()
        defer { lock.unlock() }
        var sound = heardSound
        for frame in 0..<frames {
            let offset = frame * stride
            let sample = right.map { (left[offset] + $0[offset]) * 0.5 } ?? left[offset]
            if !sound, abs(sample) > 1e-6 { sound = true }
            storage[writeIndex] = sample
            writeIndex = writeIndex + 1 == capacity ? 0 : writeIndex + 1
        }
        heardSound = sound
        written = min(written + frames, capacity)
        total += frames
    }

    /// Alle bisher geschriebenen Samples; steht der Zähler still, kommt kein Ton mehr an.
    public var framesWritten: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    /// Kopiert die jüngsten `out.count` Samples (älteste zuerst). `false`, solange noch nicht genug da sind.
    public func copyLatest(into out: inout [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let count = out.count
        guard count <= written else { return false }
        var index = (writeIndex - count + capacity) % capacity
        for position in 0..<count {
            out[position] = storage[index]
            index = index + 1 == capacity ? 0 : index + 1
        }
        return true
    }

    /// Kam schon einmal echter Ton an (nicht nur Stille)? Ohne Freigabe liefert macOS nur Nullen.
    public var hasHeardSound: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heardSound
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        written = 0
        total = 0
        heardSound = false
    }
}

import Foundation
import Testing
@testable import LumoCore

private let rate = 48_000.0
private let size = 1024

/// Sinus mit `frequency` Hz und Amplitude `amplitude`, `count` Samples ab Sample `start`.
private func sine(_ frequency: Double, amplitude: Float = 1, count: Int = size, start: Int = 0) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double(start + $0) / rate)) }
}

// MARK: - Spektrum

@Test func spectrumFindsASineInItsBin() {
    var analyzer = SpectrumAnalyzer(size: size)
    // Bin 40 liegt bei 40 · 48000 / 1024 = 1875 Hz.
    let magnitudes = analyzer.magnitudes(of: sine(40 * rate / Double(size)))
    #expect(magnitudes.count == size / 2)
    let peak = magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] }
    #expect(peak == 40)
    // Mit Hann-Fenster hat ein voller Sinus den Betrag 0,5.
    #expect(abs(magnitudes[40] - 0.5) < 0.01)
    #expect(magnitudes[100] < 0.001)
}

@Test func spectrumOfSilenceIsZero() {
    var analyzer = SpectrumAnalyzer(size: size)
    #expect(analyzer.magnitudes(of: [Float](repeating: 0, count: size)).allSatisfy { $0 == 0 })
}

@Test func spectrumSizeMustBeAPowerOfTwo() {
    #expect(SpectrumAnalyzer.isValidSize(1024))
    #expect(!SpectrumAnalyzer.isValidSize(1000))
    #expect(!SpectrumAnalyzer.isValidSize(0))
}

// MARK: - Balken

/// Lässt `signal` (fortlaufend) `frames` Bilder lang durch die Balken laufen, 60 Bilder pro Sekunde.
private func run(_ bars: inout VisualizerBars, frames: Int, signal: (Int) -> [Float]) -> [Double] {
    var analyzer = SpectrumAnalyzer(size: size)
    var levels: [Double] = []
    for frame in 0..<frames {
        levels = bars.update(magnitudes: analyzer.magnitudes(of: signal(frame * 800)), dt: 1.0 / 60)
    }
    return levels
}

@Test func bandsAreLogarithmicAndInsideTheSpectrum() {
    let bars = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    let edges = bars.bandEdges
    #expect(edges.count == 4)
    #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
    #expect(edges.first! >= 1)
    #expect(edges.last! <= size / 2)
}

@Test func bassMovesTheFirstBarAndTrebleTheLast() {
    var low = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    let bass = run(&low, frames: 30) { sine(90, start: $0) }
    #expect(bass[0] > 0.8)
    #expect(bass[2] < 0.2)

    var high = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    let treble = run(&high, frames: 30) { sine(6_000, start: $0) }
    #expect(treble[2] > 0.8)
    #expect(treble[0] < 0.2)
}

@Test func silenceKeepsTheBarsDown() {
    var bars = VisualizerBars(count: 4, sampleRate: rate, fftSize: size)
    let levels = run(&bars, frames: 20) { _ in [Float](repeating: 0, count: size) }
    #expect(levels == [0, 0, 0, 0])
}

@Test func quietMusicStillFillsTheBars() {
    // Leise gestellt (−26 dB) zeigt der Visualizer trotzdem volle Ausschläge.
    var bars = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    let levels = run(&bars, frames: 60) { sine(90, amplitude: 0.05, start: $0) }
    #expect(levels[0] > 0.8)
}

@Test func barsFallSmoothlyAfterTheMusicStops() {
    var bars = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    var analyzer = SpectrumAnalyzer(size: size)
    for frame in 0..<30 {
        _ = bars.update(magnitudes: analyzer.magnitudes(of: sine(90, start: frame * 800)), dt: 1.0 / 60)
    }
    let silence = analyzer.magnitudes(of: [Float](repeating: 0, count: size))
    let first = bars.update(magnitudes: silence, dt: 1.0 / 60)
    // Ein Bild nach dem Ende steht der Balken noch fast oben …
    #expect(first[0] > 0.6)
    // … nach einer halben Sekunde ist er unten.
    var levels = first
    for _ in 0..<30 { levels = bars.update(magnitudes: silence, dt: 1.0 / 60) }
    #expect(levels[0] < 0.05)
}

@Test func levelsStayBetweenZeroAndOne() {
    var bars = VisualizerBars(count: 4, sampleRate: rate, fftSize: size)
    var analyzer = SpectrumAnalyzer(size: size)
    for frame in 0..<120 {
        // Wechselnd laut und leise, mit Rauschen.
        let loud: Float = frame % 20 < 10 ? 1 : 0.01
        var generator = SplitMix(seed: UInt64(frame))
        let noise = (0..<size).map { _ in loud * Float(generator.unit() * 2 - 1) }
        let levels = bars.update(magnitudes: analyzer.magnitudes(of: noise), dt: 1.0 / 60)
        #expect(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

// MARK: - Spektrum mit vielen Balken

@Test func manyBarsStillHaveDistinctBands() {
    let bars = VisualizerBars(count: 20, sampleRate: rate, fftSize: size, leveling: .shared)
    let edges = bars.bandEdges
    #expect(edges.count == 21)
    #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
    #expect(edges.last! <= size / 2)
}

@Test func sharedLevelingKeepsTheShapeOfTheSound() {
    // Lauter Bass und leise Höhen: Wie ein echter Visualizer steht der Bass oben, die Höhen sichtbar darunter.
    // Je Band eingepegelt stünden beide ganz oben.
    var bars = VisualizerBars(count: 16, sampleRate: rate, fftSize: size, leveling: .shared)
    let levels = run(&bars, frames: 40) { start in
        zip(sine(90, start: start), sine(6_000, amplitude: 0.05, start: start)).map { $0 + $1 }
    }
    // 90 Hz liegt bei 16 Balken im zweiten Band.
    #expect(levels[0...2].max()! > 0.9)
    let treble = levels[10...].max()!
    #expect(treble > 0.2 && treble < 0.8)
    // Dazwischen ist es still.
    #expect(levels[6] < 0.1)
}

@Test func peaksHoldAndFallSlowly() {
    var bars = VisualizerBars(count: 3, sampleRate: rate, fftSize: size)
    var analyzer = SpectrumAnalyzer(size: size)
    for frame in 0..<30 {
        bars.update(magnitudes: analyzer.magnitudes(of: sine(90, start: frame * 800)), dt: 1.0 / 60)
    }
    #expect(bars.peaks[0] > 0.9)
    let silence = analyzer.magnitudes(of: [Float](repeating: 0, count: size))
    for _ in 0..<30 { bars.update(magnitudes: silence, dt: 1.0 / 60) }
    // Nach einer halben Sekunde ist der Balken unten, seine Spitze schwebt noch darüber …
    #expect(bars.levels[0] < 0.05)
    #expect(bars.peaks[0] > 0.4)
    // … und ist nach zwei Sekunden auch unten.
    for _ in 0..<90 { bars.update(magnitudes: silence, dt: 1.0 / 60) }
    #expect(bars.peaks[0] == 0)
}

/// Kleiner, fester Zufallsgenerator für Testsignale.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

// MARK: - Ringpuffer

@Test func ringReturnsTheNewestSamplesInOrder() {
    let ring = AudioSampleRing(capacity: 8)
    var out = [Float](repeating: -1, count: 4)
    #expect(!ring.copyLatest(into: &out))
    let first: [Float] = [1, 2, 3]
    first.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 3, stride: 1) }
    #expect(!ring.copyLatest(into: &out))
    let second: [Float] = [4, 5, 6, 7, 8, 9, 10]
    second.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 7, stride: 1) }
    #expect(ring.copyLatest(into: &out))
    #expect(out == [7, 8, 9, 10])
}

@Test func ringMixesStereoToMono() {
    let ring = AudioSampleRing(capacity: 8)
    // Verschachtelt: L, R, L, R …
    let interleaved: [Float] = [1, 3, 2, 4, 0, 1]
    interleaved.withUnsafeBufferPointer { buffer in
        ring.write(buffer.baseAddress!, buffer.baseAddress! + 1, frames: 3, stride: 2)
    }
    var out = [Float](repeating: 0, count: 3)
    #expect(ring.copyLatest(into: &out))
    #expect(out == [2, 3, 0.5])
}

@Test func ringCountsEveryFrame() {
    // Steht der Zähler still, kommt kein Ton mehr an (etwa nach dem Wechsel auf AirPods).
    let ring = AudioSampleRing(capacity: 4)
    #expect(ring.framesWritten == 0)
    let samples = [Float](repeating: 0.1, count: 6)
    samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 6, stride: 1) }
    samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 3, stride: 1) }
    #expect(ring.framesWritten == 9)
}

@Test func ringNoticesRealSound() {
    let ring = AudioSampleRing(capacity: 8)
    let silence = [Float](repeating: 0, count: 4)
    silence.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 4, stride: 1) }
    #expect(!ring.hasHeardSound)
    let sound: [Float] = [0, 0.2, 0, 0]
    sound.withUnsafeBufferPointer { ring.write($0.baseAddress!, nil, frames: 4, stride: 1) }
    #expect(ring.hasHeardSound)
    ring.reset()
    #expect(!ring.hasHeardSound)
    var out = [Float](repeating: 0, count: 2)
    #expect(!ring.copyLatest(into: &out))
}

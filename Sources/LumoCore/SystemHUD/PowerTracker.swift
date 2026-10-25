import Foundation

/// Stand der Stromversorgung, aus IOKit gelesen.
public struct PowerState: Equatable, Sendable {
    /// Netzteil angeschlossen.
    public var external: Bool
    /// Füllstand 0…1; `nil` ohne Batterie.
    public var level: Double?

    public init(external: Bool, level: Double?) {
        self.external = external
        self.level = level
    }
}

/// Entscheidet, wann die Notch etwas zum Strom sagt: beim An- und Abstecken des Netzteils und einmal je Entladung
/// bei 20 % und 10 %.
public struct PowerTracker: Equatable, Sendable {
    public static let lowLevels: [Double] = [0.2, 0.1]

    private var last: PowerState?
    /// Schwellen, vor denen schon gewarnt wurde; beim nächsten Laden fängt es von vorn an.
    private var warned: Set<Int> = []

    public init() {}

    /// Nimmt den neuen Stand und sagt, was zu zeigen ist. Der erste Stand zeigt nichts (das ist nur der Start).
    public mutating func update(_ state: PowerState) -> SystemIndicator? {
        defer { last = state }
        guard let last else { return nil }
        if state.external != last.external {
            if state.external { warned = [] }
            return .power(charging: state.external, level: state.level)
        }
        guard !state.external, let level = state.level else { return nil }
        for (index, threshold) in Self.lowLevels.enumerated() where level <= threshold && !warned.contains(index) {
            warned.insert(index)
            return .lowBattery(level: level)
        }
        return nil
    }
}

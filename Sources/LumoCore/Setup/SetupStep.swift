/// Schritte des Einrichtungs-Assistenten, in dieser Reihenfolge.
public enum SetupStep: Int, CaseIterable, Sendable {
    case language, welcome, claude, codex, signalStyle, appearance, permissions, done

    public var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }
    public var previous: SetupStep? { SetupStep(rawValue: rawValue - 1) }

    /// 0 beim ersten, 1 beim letzten Schritt.
    public var progress: Double {
        Double(rawValue) / Double(SetupStep.allCases.count - 1)
    }
}

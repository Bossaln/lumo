import Foundation

/// Zeile der Timer-Tabelle in der Datenbank der Uhr-App (`local.sqlite` im Gruppen-Container von `mobiletimerd`,
/// Core-Data-Entität `MTCDTimer`). Zustände: 1 gestoppt, 2 pausiert, 3 läuft.
public struct TimerRow: Equatable, Sendable {
    public var state: Int
    public var duration: TimeInterval
    /// Archivierter Zündzeitpunkt: ein Datum (läuft) oder eine Restzeit (pausiert).
    public var fireTime: Data?
    public var firedDate: Date?
    public var dismissedDate: Date?
    public var title: String?
    public var lastModified: Date?

    public init(state: Int, duration: TimeInterval, fireTime: Data? = nil, firedDate: Date? = nil, dismissedDate: Date? = nil,
                title: String? = nil, lastModified: Date? = nil) {
        self.state = state
        self.duration = duration
        self.fireTime = fireTime
        self.firedDate = firedDate
        self.dismissedDate = dismissedDate
        self.title = title
        self.lastModified = lastModified
    }

    public static let stopped = 1, paused = 2, running = 3
}

/// Zeile der Wecker-Tabelle (`MTCDAlarm`).
public struct AlarmRow: Equatable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int
    public var title: String?
    public var firedDate: Date?
    public var dismissedDate: Date?
    public var snoozeFireDate: Date?

    public init(enabled: Bool, hour: Int, minute: Int, title: String? = nil, firedDate: Date? = nil, dismissedDate: Date? = nil,
                snoozeFireDate: Date? = nil) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.title = title
        self.firedDate = firedDate
        self.dismissedDate = dismissedDate
        self.snoozeFireDate = snoozeFireDate
    }
}

/// Was die Uhr-App gerade tut, aus den Zeilen abgeleitet.
public enum TimerStatus: Equatable, Sendable {
    case running(fireDate: Date)
    case paused(remaining: TimeInterval)
    /// Abgelaufen und noch nicht beendet.
    case fired
}

public enum AlarmStatus: Equatable, Sendable {
    case ringing(title: String?)
    case snoozed(until: Date)
}

public enum ClockState {
    /// So lange gilt ein abgelaufener Timer oder Wecker als „klingelt noch“, falls die Uhr-App das Beenden nicht
    /// mehr einträgt.
    public static let ringingWindow: TimeInterval = 15 * 60

    /// Der Timer, den die Notch zeigt: ein laufender vor einem pausierten vor einem abgelaufenen.
    public static func timer(rows: [TimerRow], now: Date) -> TimerStatus? {
        var running: Date?, paused: TimeInterval?, fired = false
        for row in rows {
            switch row.state {
            case TimerRow.running:
                if let date = fireDate(of: row, now: now) {
                    if date > now {
                        running = min(running ?? .distantFuture, date)
                    } else if isRinging(fired: date, dismissed: row.dismissedDate, now: now) {
                        fired = true
                    }
                }
            case TimerRow.paused:
                if let remaining = remainingTime(of: row), remaining > 0 { paused = min(paused ?? .infinity, remaining) }
            default:
                if let firedDate = row.firedDate, isRinging(fired: firedDate, dismissed: row.dismissedDate, now: now) { fired = true }
            }
        }
        if let running { return .running(fireDate: running) }
        if let paused { return .paused(remaining: paused) }
        return fired ? .fired : nil
    }

    /// Klingelt ein Wecker oder schlummert einer?
    public static func alarm(rows: [AlarmRow], now: Date) -> AlarmStatus? {
        var ringing: AlarmRow?, snoozed: Date?
        for row in rows {
            if let snooze = row.snoozeFireDate, snooze > now, row.dismissedDate.map({ $0 < snooze }) ?? true {
                snoozed = min(snoozed ?? .distantFuture, snooze)
            } else if let fired = row.firedDate, isRinging(fired: fired, dismissed: row.dismissedDate, now: now) {
                if ringing.map({ ($0.firedDate ?? .distantPast) < fired }) ?? true { ringing = row }
            }
        }
        if let ringing { return .ringing(title: ringing.title) }
        if let snoozed { return .snoozed(until: snoozed) }
        return nil
    }

    static func isRinging(fired: Date, dismissed: Date?, now: Date) -> Bool {
        guard fired <= now, now.timeIntervalSince(fired) < ringingWindow else { return false }
        return dismissed.map { $0 < fired } ?? true
    }

    static func fireDate(of row: TimerRow, now: Date) -> Date? {
        switch row.fireTime.flatMap(ArchivedFireTime.decode) {
        case .date(let date): date
        case .interval(let seconds): (row.lastModified ?? now).addingTimeInterval(seconds)
        case nil: nil
        }
    }

    static func remainingTime(of row: TimerRow) -> TimeInterval? {
        switch row.fireTime.flatMap(ArchivedFireTime.decode) {
        case .interval(let seconds): seconds
        case .date, nil: nil
        }
    }
}

/// Der Zündzeitpunkt eines Timers liegt als Keyed-Archive in der Datenbank: ein `MTTimerFireDate` mit Datum
/// oder ein `MTTimerTimeInterval` mit Restzeit. Gelesen wird das Archiv als Property-List: das erste Datum, sonst
/// die erste Zahl unter einem Schlüssel mit „Interval“.
public enum ArchivedFireTime: Equatable, Sendable {
    case date(Date)
    case interval(TimeInterval)

    public static func decode(_ data: Data) -> ArchivedFireTime? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let archive = plist as? [String: Any], let objects = archive["$objects"] as? [Any] else { return nil }
        for object in objects {
            guard let dictionary = object as? [String: Any] else { continue }
            if let time = dictionary["NS.time"] as? Double { return .date(Date(timeIntervalSinceReferenceDate: time)) }
        }
        for object in objects {
            guard let dictionary = object as? [String: Any] else { continue }
            for (key, value) in dictionary where key.localizedCaseInsensitiveContains("interval") {
                if let seconds = value as? Double { return .interval(seconds) }
                if let seconds = value as? Int { return .interval(TimeInterval(seconds)) }
            }
        }
        return nil
    }
}

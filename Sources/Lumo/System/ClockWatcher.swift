import Foundation
import LumoCore
import SQLite3

/// Liest Timer und Wecker aus der Datenbank der Uhr-App (`mobiletimerd`). Die Datei ist geschützt: Ohne vollen
/// Festplattenzugriff bleibt `access` falsch. Gelesen wird nur; die Uhr-App behält die Hoheit.
@MainActor
final class ClockWatcher {
    var onTimer: ((TimerStatus?) -> Void)?
    var onAlarm: ((AlarmStatus?) -> Void)?
    private(set) var access: Bool?
    /// Letzter Fehler beim Lesen (Seite „System“ in den Einstellungen), `nil` wenn alles klappt.
    private(set) var problem: String?
    private(set) var timerStatus: TimerStatus?
    private(set) var alarmStatus: AlarmStatus?

    private let databaseURL: URL
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?

    private static let timerQuery =
        "SELECT ZSTATE, ZDURATION, ZFIRETIME, ZFIREDDATE, ZDISMISSEDDATE, ZTITLE, ZLASTMODIFIEDDATE FROM ZMTCDTIMER"
    private static let alarmQuery =
        "SELECT ZENABLED, ZHOUR, ZMINUTE, ZTITLE, ZFIREDDATE, ZDISMISSEDDATE, ZSNOOZEFIREDATE FROM ZMTCDALARM"

    init(home: URL) {
        databaseURL = home.appending(path: "Library/Group Containers/group.com.apple.mobiletimerd/local.sqlite")
    }

    func start() {
        guard timer == nil else { return }
        read()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
    }

    /// Mit Zugriff alle drei Sekunden (die Restzeit zählt die Notch selbst), ohne alle 15, falls die
    /// Berechtigung inzwischen erteilt wurde.
    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: access == true ? 3 : 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func watchDirectory() {
        guard source == nil else { return }
        let descriptor = open(databaseURL.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .attrib], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func read() {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            setAccess(false)
            return
        }
        defer { sqlite3_close(database) }
        let now = Date()
        do {
            let timers = try Self.rows(database, Self.timerQuery).map { row in
                TimerRow(state: row.int(0), duration: row.double(1), fireTime: row.data(2), firedDate: row.date(3),
                         dismissedDate: row.date(4), title: row.string(5), lastModified: row.date(6))
            }
            let alarms = try Self.rows(database, Self.alarmQuery).map { row in
                AlarmRow(enabled: row.int(0) != 0, hour: row.int(1), minute: row.int(2), title: row.string(3), firedDate: row.date(4),
                         dismissedDate: row.date(5), snoozeFireDate: row.date(6))
            }
            problem = nil
            setAccess(true)
            update(timer: ClockState.timer(rows: timers, now: now), alarm: ClockState.alarm(rows: alarms, now: now))
        } catch {
            // Die Datei ist lesbar, aber anders aufgebaut als erwartet (neue macOS-Version).
            problem = String(describing: error)
            setAccess(true)
        }
    }

    private func setAccess(_ granted: Bool) {
        guard access != granted else { return }
        access = granted
        if granted { watchDirectory() }
        schedule()
    }

    private func update(timer: TimerStatus?, alarm: AlarmStatus?) {
        if timer != timerStatus {
            timerStatus = timer
            onTimer?(timer)
        }
        if alarm != alarmStatus {
            alarmStatus = alarm
            onAlarm?(alarm)
        }
    }

    // MARK: - SQLite

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Eine gelesene Zeile; Core Data speichert Daten als Sekunden seit 2001.
    struct Row {
        var values: [Any?]

        func int(_ index: Int) -> Int { (values[index] as? Int64).map(Int.init) ?? Int((values[index] as? Double) ?? 0) }
        func double(_ index: Int) -> Double { (values[index] as? Double) ?? Double((values[index] as? Int64) ?? 0) }
        func string(_ index: Int) -> String? { values[index] as? String }
        func data(_ index: Int) -> Data? { values[index] as? Data }
        func date(_ index: Int) -> Date? {
            guard let seconds = values[index] as? Double else { return nil }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
    }

    private static func rows(_ database: OpaquePointer, _ query: String) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw Failure(message: String(cString: sqlite3_errmsg(database))) }
            let count = Int(sqlite3_column_count(statement))
            var values: [Any?] = []
            for column in 0..<Int32(count) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: values.append(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: values.append(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: values.append(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, column) {
                        values.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))))
                    } else {
                        values.append(nil)
                    }
                default: values.append(nil)
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }
}

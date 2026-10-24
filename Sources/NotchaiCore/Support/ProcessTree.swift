import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Prozesse über ihre Eltern verfolgen: Welcher Agent hat einen Hook gestartet, läuft er noch?
public enum ProcessTree {
    /// Elternprozess und Name einer Prozess-ID; `nil`, wenn es den Prozess nicht gibt.
    public typealias Lookup = (Int32) -> (parent: Int32, name: String)?

    /// Shells und Hilfsprogramme, über die Agenten ihre Hooks starten.
    static let launchers: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "nice", "nohup", "timeout"]

    /// Der Agent über einem Hook: `pid` selbst oder der erste Vorfahr, der keine Shell ist.
    public static func agent(above pid: Int32, lookup: Lookup) -> Int32? {
        var current = pid
        var seen: Set<Int32> = []
        while current > 1, seen.insert(current).inserted, let process = lookup(current) {
            if !launchers.contains(process.name) { return current }
            current = process.parent
        }
        return nil
    }

    /// Läuft der Prozess noch? (Gibt es ihn, aber gehört er jemand anderem, zählt er auch.)
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Elternprozess und Name aus dem System (macOS: `sysctl`); anderswo `nil`.
    public static func systemLookup(_ pid: Int32) -> (parent: Int32, name: String)? {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (info.kp_eproc.e_ppid, name)
        #else
        return nil
        #endif
    }
}

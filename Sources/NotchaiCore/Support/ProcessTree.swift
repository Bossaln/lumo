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

    /// Startet ein Kindprozess von `parent` (außer den schon bekannten `known`), dessen Befehlszeile `needle`
    /// enthält? So erkennt die App, dass eine Freigabe im Terminal erlaubt wurde: Claude Code meldet das nicht,
    /// startet aber den Befehl (`docs/hooks.md`).
    public static func startedChild(of parent: Int32, containing needle: String, except known: Set<Int32>,
                                    children: (Int32) -> [Int32] = systemChildren,
                                    arguments: (Int32) -> String? = systemArguments) -> Bool {
        children(parent).contains { !known.contains($0) && (arguments($0)?.contains(needle) ?? false) }
    }

    /// Direkte Kindprozesse (macOS: alle Prozesse per `sysctl`, gefiltert nach Elternprozess); anderswo leer.
    public static func systemChildren(_ parent: Int32) -> [Int32] {
        #if canImport(Darwin)
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Zwischen den beiden Aufrufen können Prozesse dazukommen.
        size += size / 8
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride)
            .filter { $0.kp_eproc.e_ppid == parent }.map { $0.kp_proc.p_pid }
        #else
        return []
        #endif
    }

    /// Befehlszeile eines Prozesses (Argumente mit Leerzeichen verbunden; macOS: `KERN_PROCARGS2`).
    public static func systemArguments(_ pid: Int32) -> String? {
        #if canImport(Darwin)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
        #else
        return nil
        #endif
    }

    /// `KERN_PROCARGS2`: Anzahl der Argumente (Int32), Programmpfad, Füll-Nullen, dann die Argumente.
    static func parseProcArgs(_ bytes: [UInt8]) -> String? {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize else { return nil }
        let argc = bytes.prefix(countSize).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = countSize
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var args: [String] = []
        while index < bytes.count, args.count < argc {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            args.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
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

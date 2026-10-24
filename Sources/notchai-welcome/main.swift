#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import NotchaiCore

// Läuft nach `brew install` und `brew upgrade` (Cask: `postflight_steps`). Homebrew reicht die Ausgabe von
// Programmen nur zeilenweise weiter; damit der Wagen flüssig fährt, schreibt es direkt ins Terminal.
// Ohne Terminal steht nur der Satz da. Endet immer mit 0, damit die Installation nie daran scheitert.

// Homebrew reicht `LANG` und `LC_ALL` durch; ohne sie zählt die Sprache des Macs.
Localization.language = AppLanguage.fromEnvironment(ProcessInfo.processInfo.environment)
    ?? AppLanguage.preferred(from: Locale.preferredLanguages)

/// Elternprozess und Name eines Prozesses (nur macOS).
func processInfo(_ pid: Int32) -> (parent: Int32, name: String)? {
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

// Beim Update über den Knopf in notchai schreibt Homebrew alles ins Protokoll; dort reicht der Satz.
let terminal = InstallGreeting.isRunByNotchai(pid: getpid(), lookup: processInfo) ? -1 : open("/dev/tty", O_WRONLY | O_NOCTTY)
guard terminal >= 0 else {
    print(InstallGreeting.plain)
    exit(0)
}

func put(_ text: String) {
    var text = text
    text.withUTF8 { bytes in _ = write(terminal, bytes.baseAddress, bytes.count) }
}

// Bricht jemand mitten in der Fahrt ab, kommt der Cursor zurück.
for stop in [SIGINT, SIGTERM, SIGHUP] {
    signal(stop) { _ in
        put("\u{1B}[0m\u{1B}[?25h\n")
        exit(0)
    }
}

var size = winsize()
let columns = withUnsafeMutablePointer(to: &size) { ioctl(terminal, UInt(TIOCGWINSZ), $0) } == 0 && size.ws_col > 0
    ? Int(size.ws_col) : 80
for frame in InstallGreeting.frames(columns: columns) {
    put(frame.text)
    if frame.pause > 0 { usleep(UInt32(frame.pause * 1_000_000)) }
}
close(terminal)
exit(0)

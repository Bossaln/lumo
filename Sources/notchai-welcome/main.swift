#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import NotchaiCore

// Läuft nach `brew install` und `brew upgrade` (Cask: `postflight_steps`). Homebrew reicht die Ausgabe von
// Programmen nur zeilenweise weiter; damit der Wagen flüssig fährt, schreibt es direkt ins Terminal.
// Ohne Terminal steht nur der Satz da. Endet immer mit 0, damit die Installation nie daran scheitert.

let terminal = open("/dev/tty", O_WRONLY | O_NOCTTY)
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

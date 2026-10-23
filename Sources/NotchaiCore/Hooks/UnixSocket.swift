import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Dünne Hülle um POSIX-Unix-Sockets für `HookClient` und `HookSocketServer`. Alle Sockets sind
/// nicht-blockierend; gewartet wird nur mit `poll` und immer mit Frist. Die `#if`-Zweige gleichen
/// Darwin und Glibc an, damit die Logik-Tests auch unter Linux laufen.
enum UnixSocket {
    #if canImport(Darwin)
    private static let streamType = SOCK_STREAM
    private static let sendFlags: Int32 = 0
    #else
    private static let streamType = Int32(SOCK_STREAM.rawValue)
    /// Unter Linux verhindert das Flag pro Aufruf SIGPIPE; unter Darwin übernimmt das `SO_NOSIGPIPE`.
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif

    /// Adresse für `path`; `nil`, wenn der Pfad leer ist oder nicht in `sun_path` passt (etwa 104 Bytes).
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return addr
    }

    /// Neuer nicht-blockierender Stream-Socket, der nicht an Kindprozesse vererbt wird.
    static func makeSocket() -> Int32? {
        let fd = socket(AF_UNIX, streamType, 0)
        guard fd >= 0 else { return nil }
        configure(fd)
        return fd
    }

    /// Nicht-blockierend, close-on-exec und (Darwin) ohne SIGPIPE.
    static func configure(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        #if canImport(Darwin)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    /// Verbindet mit `path` und wartet dabei höchstens `timeout`; `nil`, wenn niemand zuhört.
    static func openClient(path: String, timeout: TimeInterval) -> Int32? {
        guard var addr = address(path), let fd = makeSocket() else { return nil }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            guard errno == EINPROGRESS || errno == EAGAIN,
                  wait(fd, events: Int16(POLLOUT), timeout: timeout),
                  getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0, err == 0 else {
                close(fd)
                return nil
            }
        }
        return fd
    }

    /// Bindet einen lauschenden Socket an `path` (eine alte Datei dort wird ersetzt) mit Rechten 0600.
    static func openServer(path: String) throws -> Int32 {
        guard var addr = address(path) else { throw HookSocketError.pathTooLong(path) }
        guard let fd = makeSocket() else { throw HookSocketError.system("socket", errno) }
        unlink(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw HookSocketError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw HookSocketError.system("listen", code)
        }
        return fd
    }

    /// Wartet, bis `fd` für `events` bereit ist; `false` bei Frist oder Fehler.
    static func wait(_ fd: Int32, events: Int16, timeout: TimeInterval) -> Bool {
        var p = pollfd(fd: fd, events: events, revents: 0)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let ms = Int32(min(Double(Int32.max), max(0, deadline.timeIntervalSinceNow * 1000)).rounded(.up))
            let r = poll(&p, 1, ms)
            if r > 0 { return true }
            if r == 0 || errno != EINTR { return false }
        }
    }

    /// Schreibt `data` vollständig; `false`, wenn die Gegenseite weg ist oder die Frist abläuft.
    static func sendAll(_ fd: Int32, _ data: Data, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = send(fd, base + offset, raw.count - offset, sendFlags)
                if n > 0 {
                    offset += n
                } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                    guard wait(fd, events: Int16(POLLOUT), timeout: deadline.timeIntervalSinceNow) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// Liest bis einschließlich `\n`. `nil` bei Verbindungsende, Fehler, Frist oder mehr als `limit` Bytes.
    static func readLine(_ fd: Int32, timeout: TimeInterval, limit: Int) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while line.count <= limit {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                line.append(contentsOf: chunk[0..<n])
                if line.contains(UInt8(ascii: "\n")) { return line }
            } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                guard wait(fd, events: Int16(POLLIN), timeout: deadline.timeIntervalSinceNow) else { return nil }
            } else {
                return nil
            }
        }
        return nil
    }
}

public enum HookSocketError: Error, Equatable {
    case pathTooLong(String)
    case system(String, Int32)
}

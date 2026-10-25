import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unix-Socket-Server der App. Jede Verbindung schickt genau ein `HookEnvelope` als Zeile.
/// `event`-Verbindungen werden danach geschlossen; `decide`-Verbindungen bleiben offen, bis `reply` mit
/// ihrer `requestId` kommt oder `stop()` sie schließt – dann bekommt der Hook „keine Entscheidung“.
///
/// Alles läuft auf einem eigenen Thread mit `poll`. `onEnvelope` wird auf diesem Thread aufgerufen;
/// `reply` und `stop` dürfen von jedem Thread kommen.
public final class HookSocketServer: @unchecked Sendable {
    /// Größte Zeile, die angenommen wird (`lumo-hook` liest höchstens 4 MB Eingabe).
    private static let lineLimit = 5 << 20
    /// So lange darf ein Hook für seine Zeile brauchen, bevor die Verbindung verworfen wird.
    private static let readTimeout: TimeInterval = 10

    private struct Connection {
        var buffer = Data()
        var openedAt = Date()
        /// Gesetzt, sobald eine `decide`-Anfrage gelesen ist; dann wartet die Verbindung auf `reply`.
        var waitingFor: UUID?
    }

    private let socketPath: String
    private let onEnvelope: @Sendable (HookEnvelope) -> Void

    /// Schützt alles darunter. Geschlossen wird ein Socket nur unter dieser Sperre, damit `reply` nie
    /// auf einen schon geschlossenen (und vielleicht neu vergebenen) Dateideskriptor schreibt.
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1
    private var connections: [Int32: Connection] = [:]
    private var waiting: [UUID: Int32] = [:]
    private var running = false
    private var loopFinished: DispatchSemaphore?

    public init(socketPath: String, onEnvelope: @escaping @Sendable (HookEnvelope) -> Void) {
        self.socketPath = socketPath
        self.onEnvelope = onEnvelope
    }

    deinit {
        stop()
    }

    /// Ersetzt eine alte Socket-Datei, bindet mit Rechten 0600 und nimmt Verbindungen an.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        try FileManager.default.createDirectory(atPath: (socketPath as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let fd = try UnixSocket.openServer(path: socketPath)
        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else {
            close(fd)
            unlink(socketPath)
            throw HookSocketError.system("pipe", errno)
        }
        for end in pipeFDs { _ = fcntl(end, F_SETFL, fcntl(end, F_GETFL) | O_NONBLOCK) }
        listenFD = fd
        wakeRead = pipeFDs[0]
        wakeWrite = pipeFDs[1]
        running = true
        let finished = DispatchSemaphore(value: 0)
        loopFinished = finished
        let thread = Thread { [self] in
            runLoop()
            finished.signal()
        }
        thread.name = "lumo.hook-socket"
        thread.start()
    }

    /// Schließt alle Verbindungen (wartende Hooks bekommen sofort „keine Entscheidung“) und den Socket.
    public func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        let finished = loopFinished
        wake()
        lock.unlock()
        _ = finished?.wait(timeout: .now() + 2)

        lock.lock()
        for fd in connections.keys { close(fd) }
        connections.removeAll()
        waiting.removeAll()
        for fd in [listenFD, wakeRead, wakeWrite] where fd >= 0 { close(fd) }
        listenFD = -1
        wakeRead = -1
        wakeWrite = -1
        unlink(socketPath)
        lock.unlock()
    }

    /// Schickt die Entscheidung an den wartenden Hook. Unbekannte oder schon beantwortete IDs: nichts.
    public func reply(_ r: HookReply) {
        guard let line = try? HookWire.encodeLine(r) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let fd = waiting.removeValue(forKey: r.requestId) else { return }
        // Eine Zeile mit wenigen hundert Bytes passt sofort in den leeren Puffer.
        _ = UnixSocket.sendAll(fd, line, timeout: 1)
        closeLocked(fd)
        wake()
    }

    // MARK: - Schleife

    private func runLoop() {
        while true {
            lock.lock()
            guard running else {
                lock.unlock()
                return
            }
            var fds = [pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0)]
            fds += connections.keys.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            lock.unlock()

            // Spätestens jede Sekunde aufwachen, um hängende Verbindungen zu verwerfen.
            let ready = poll(&fds, nfds_t(fds.count), 1000)
            if ready < 0, errno != EINTR { return }

            var delivered: [HookEnvelope] = []
            lock.lock()
            if fds[1].revents != 0 { drainWakePipe() }
            if fds[0].revents & Int16(POLLIN) != 0 { acceptAll() }
            for p in fds.dropFirst(2) where p.revents != 0 {
                if let envelope = readFrom(p.fd) { delivered.append(envelope) }
            }
            dropStaleConnections()
            lock.unlock()

            // Außerhalb der Sperre, damit `onEnvelope` direkt `reply` aufrufen darf.
            for envelope in delivered { onEnvelope(envelope) }
        }
    }

    private func acceptAll() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            UnixSocket.configure(fd)
            connections[fd] = Connection()
        }
    }

    /// Liest, was da ist. Gibt das Envelope zurück, sobald die erste Zeile vollständig ist.
    private func readFrom(_ fd: Int32) -> HookEnvelope? {
        guard var connection = connections[fd] else { return nil }
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        // Ein `event`-Hook schließt direkt nach dem Senden; seine Zeile gilt trotzdem.
        var peerClosed = false
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                // Nach der Anfrage schickt ein wartender Hook nichts mehr; weitere Bytes werden ignoriert.
                if connection.waitingFor == nil { connection.buffer.append(contentsOf: chunk[0..<n]) }
            } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                break
            } else {
                peerClosed = true
                break
            }
        }
        guard connection.waitingFor == nil else {
            // Ein wartender Hook ist weg (beendet oder vom Agenten abgebrochen): Anfrage verwerfen.
            if peerClosed { closeLocked(fd) } else { connections[fd] = connection }
            return nil
        }
        guard let newline = connection.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            if peerClosed || connection.buffer.count > Self.lineLimit { closeLocked(fd) } else { connections[fd] = connection }
            return nil
        }
        guard let envelope = try? HookWire.decodeLine(connection.buffer[..<newline], as: HookEnvelope.self) else {
            closeLocked(fd)
            return nil
        }
        switch envelope.mode {
        case .event:
            closeLocked(fd)
        case .decide where peerClosed:
            // Niemand wartet mehr auf diese Entscheidung.
            closeLocked(fd)
            return nil
        case .decide:
            connection.waitingFor = envelope.requestId
            connection.buffer = Data()
            connections[fd] = connection
            waiting[envelope.requestId] = fd
        }
        return envelope
    }

    private func dropStaleConnections() {
        let now = Date()
        for (fd, connection) in connections
        where connection.waitingFor == nil && now.timeIntervalSince(connection.openedAt) > Self.readTimeout {
            closeLocked(fd)
        }
    }

    private func closeLocked(_ fd: Int32) {
        guard let connection = connections.removeValue(forKey: fd) else { return }
        if let id = connection.waitingFor, waiting[id] == fd { waiting[id] = nil }
        close(fd)
    }

    private func wake() {
        guard wakeWrite >= 0 else { return }
        var byte: UInt8 = 1
        _ = write(wakeWrite, &byte, 1)
    }

    private func drainWakePipe() {
        var buffer = [UInt8](repeating: 0, count: 64)
        while buffer.withUnsafeMutableBytes({ read(wakeRead, $0.baseAddress, $0.count) }) > 0 {}
    }
}

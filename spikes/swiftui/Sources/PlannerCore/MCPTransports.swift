import Foundation
import Network

/// Where the gate server listens, and how to describe it to an ACP agent in
/// `session/new.mcpServers`.
public protocol MCPGateTransport: AnyObject, Sendable {
    /// The `McpServer` entry for session/new (stdio or http variant).
    var acpServerConfig: JSONValue { get }
    var transportName: String { get }
    func stop()
}

public enum MCPGateHost {
    /// Starts the gate server for one session. Tries Streamable HTTP on
    /// 127.0.0.1 first; when binding a port is not allowed (the Claude Code
    /// sandbox returns EPERM for both TCP and Unix sockets) it falls back to
    /// a stdio shim relaying over two FIFOs.
    public static func start(server: MCPGateServer, preferHTTP: Bool = true) -> (MCPGateTransport, note: String?) {
        if preferHTTP {
            do {
                return (try MCPHTTPTransport(server: server), nil)
            } catch {
                let note = "HTTP MCP server unavailable (\(error)); using the FIFO stdio shim"
                if let fifo = try? MCPFifoTransport(server: server) { return (fifo, note) }
            }
        }
        do {
            return (try MCPFifoTransport(server: server), nil)
        } catch {
            return (DisabledTransport(), "No MCP transport: \(error)")
        }
    }
}

final class DisabledTransport: MCPGateTransport {
    var acpServerConfig: JSONValue { .null }
    var transportName: String { "none" }
    func stop() {}
}

// MARK: - stdio shim over FIFOs

/// The agent (Claude Code) spawns a stdio MCP server; that server is a
/// two-line `/bin/sh` relay, `cat <out & exec cat >in`, between its stdio and
/// two FIFOs this object owns. No sockets, so it works where port binding is
/// blocked. One connection at a time; if the agent restarts the server, the
/// loop accepts the next one.
public final class MCPFifoTransport: MCPGateTransport, @unchecked Sendable {
    public let directory: URL
    let server: MCPGateServer
    private let lock = NSLock()
    private var stopped = false
    private var current: FifoConnection?

    public var transportName: String { "stdio shim over FIFOs" }

    /// `cat <out` runs in the background with an explicit redirect (a
    /// background job in non-interactive sh otherwise gets /dev/null as
    /// stdin); `exec cat >in` keeps the agent's stdin.
    public static let shimScript = #"cat <"$0/out" & exec cat >"$0/in""#

    public var acpServerConfig: JSONValue {
        .object([
            "name": .string(GateTools.serverName),
            "command": .string("/bin/sh"),
            "args": .array([.string("-c"), .string(Self.shimScript), .string(directory.path)]),
            "env": .array([]),
        ])
    }

    public init(server: MCPGateServer, directory: URL? = nil) throws {
        self.server = server
        let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        // Short path: FIFO paths have no sun_path limit, but keep it tidy.
        self.directory = directory ?? base.appendingPathComponent("planner-mcp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        for name in ["in", "out"] {
            let path = self.directory.appendingPathComponent(name).path
            unlink(path)
            guard mkfifo(path, 0o600) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                              userInfo: [NSLocalizedDescriptionKey: "mkfifo \(path): \(String(cString: strerror(errno)))"])
            }
        }
        signal(SIGPIPE, SIG_IGN)
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "planner-mcp-fifo"
        thread.start()
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func acceptLoop() {
        let inPath = directory.appendingPathComponent("in").path
        let outPath = directory.appendingPathComponent("out").path
        while !isStopped {
            // Both opens block until the shim opens the other end.
            let inFd = open(inPath, O_RDONLY)
            if inFd < 0 || isStopped { if inFd >= 0 { close(inFd) }; break }
            let outFd = open(outPath, O_WRONLY)
            if outFd < 0 || isStopped { close(inFd); if outFd >= 0 { close(outFd) }; break }
            let connection = FifoConnection(outFd: outFd)
            lock.withLock { current = connection }
            let buffer = LineBuffer()
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(inFd, &chunk, chunk.count)
                if n <= 0 { break }
                for line in buffer.append(Data(chunk[0..<n])) where !line.isEmpty {
                    let server = self.server
                    Task.detached {
                        if let response = await server.handle(line: line) { connection.write(response) }
                    }
                }
            }
            close(inFd)
            connection.close()
            lock.withLock { current = nil }
        }
    }

    public func stop() {
        let alreadyStopped = lock.withLock { () -> Bool in
            defer { stopped = true }
            return stopped
        }
        guard !alreadyStopped else { return }
        lock.withLock { current }?.close()
        // Unblock an accept loop waiting in open(in, O_RDONLY).
        let fd = open(directory.appendingPathComponent("in").path, O_WRONLY | O_NONBLOCK)
        if fd >= 0 { close(fd) }
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { stop() }
}

/// The write side of one shim connection. Responses for calls that were
/// still open when the shim went away are dropped.
final class FifoConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32

    init(outFd: Int32) { fd = outFd }

    func write(_ line: String) {
        lock.withLock {
            guard fd >= 0 else { return }
            var data = Array(line.utf8)
            data.append(0x0A)
            var offset = 0
            while offset < data.count {
                let n = data[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n <= 0 { return }
                offset += n
            }
        }
    }

    func close() {
        lock.withLock {
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }
}

// MARK: - Streamable HTTP on 127.0.0.1

/// MCP Streamable HTTP, the minimum: POST one JSON-RPC message, get one
/// `application/json` response (requests) or 202 (notifications). GET (the
/// optional server-to-client SSE stream) answers 405, which the spec allows.
/// One request per connection (`Connection: close`).
public final class MCPHTTPTransport: MCPGateTransport, @unchecked Sendable {
    let server: MCPGateServer
    let listener: NWListener
    let queue = DispatchQueue(label: "planner-mcp-http")
    public private(set) var port: UInt16 = 0
    /// A per-session secret in the path, so another local process can't
    /// guess the endpoint.
    let token = UUID().uuidString

    public var transportName: String { "Streamable HTTP" }

    public var url: String { "http://127.0.0.1:\(port)/mcp/\(token)" }

    public var acpServerConfig: JSONValue {
        .object(["type": .string("http"), "name": .string(GateTools.serverName),
                 "url": .string(url), "headers": .array([])])
    }

    public init(server: MCPGateServer, timeout: TimeInterval = 3) throws {
        self.server = server
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)

        // Wait for .ready (port known) or .failed (e.g. EPERM in a sandbox).
        let ready = DispatchSemaphore(value: 0)
        let outcome = Outcome()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: outcome.set(nil); ready.signal()
            case .failed(let e): outcome.set(e); ready.signal()
            case .waiting(let e): outcome.set(e); ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        if ready.wait(timeout: .now() + timeout) == .timedOut {
            listener.cancel()
            throw NSError(domain: "MCPHTTPTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "listener timed out"])
        }
        if let error = outcome.error {
            listener.cancel()
            throw error
        }
        port = listener.port?.rawValue ?? 0
    }

    final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Error?
        private var set = false
        func set(_ e: Error?) { lock.withLock { if !set { value = e; set = true } } }
        var error: Error? { lock.withLock { value } }
    }

    public func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(parsing: buffer) {
                self.respond(to: request, on: connection)
            } else if done || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard request.path == "/mcp/\(token)" else { return send(connection, status: "404 Not Found") }
        switch request.method {
        case "POST":
            let line = String(decoding: request.body, as: UTF8.self)
            let server = self.server
            Task.detached {
                if let response = await server.handle(line: line) {
                    self.send(connection, status: "200 OK", contentType: "application/json", body: Data(response.utf8))
                } else {
                    self.send(connection, status: "202 Accepted")
                }
            }
        case "DELETE":
            send(connection, status: "200 OK")
        default:
            send(connection, status: "405 Method Not Allowed", extra: "Allow: POST\r\n")
        }
    }

    private func send(_ connection: NWConnection, status: String, contentType: String? = nil,
                      body: Data = Data(), extra: String = "") {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n" + extra
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    /// Returns nil until the head and the full Content-Length body are in.
    init?(parsing data: Data) {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<headEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased() == "content-length" {
                length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        method = String(parts[0])
        path = String(parts[1])
        body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
    }
}

import Foundation

/// How to start an agent process. Kept as data so other ACP agents (Gemini
/// CLI, Codex adapters, ...) can be swapped in from settings.
public struct AgentLaunch: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String] = [:]

    public init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    /// Zed's Claude Code adapter, now published by the ACP org.
    public static let defaultCommand = "npx -y @agentclientprotocol/claude-agent-acp"

    /// Runs `command` through a login shell, so a GUI app launched from
    /// Finder still sees the user's PATH (npx from mise/nvm/homebrew).
    public static func shell(_ command: String) -> AgentLaunch {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return AgentLaunch(executable: shell, arguments: ["-lc", command])
    }
}

public enum ACPError: Error, CustomStringConvertible, Sendable {
    case notStarted
    case processExited(Int32, stderr: String)
    case rpc(code: Int, message: String)

    public var description: String {
        switch self {
        case .notStarted: return "agent process is not running"
        case .processExited(let code, let stderr):
            return "agent exited with status \(code)" + (stderr.isEmpty ? "" : ": \(stderr.suffix(500))")
        case .rpc(let code, let message): return "agent error \(code): \(message)"
        }
    }
}

/// Things the agent sends that are not responses to our requests.
public enum ACPEvent: Sendable {
    case sessionUpdate(sessionId: String, update: SessionUpdate)
    case permissionRequest(PermissionRequest)
    case stderr(String)
    case exited(Int32)
}

/// A JSON-RPC 2.0 client over a child process's stdio, newline-delimited,
/// as ACP specifies. One client = one agent process.
public actor ACPClient {
    public let launch: AgentLaunch
    public let cwd: URL
    public nonisolated let events: AsyncStream<ACPEvent>
    private let eventSink: AsyncStream<ACPEvent>.Continuation

    private var process: Process?
    private var stdin: FileHandle?
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var stderrTail = ""
    private var exitStatus: Int32?

    public init(launch: AgentLaunch, cwd: URL) {
        self.launch = launch
        self.cwd = cwd
        (events, eventSink) = AsyncStream.makeStream(of: ACPEvent.self)
    }

    // MARK: Lifecycle

    public func start() throws {
        // Writing to a dead agent's stdin must be an error, not a SIGPIPE
        // that kills the whole app.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment.merging(launch.environment) { $1 }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { await self?.didExit(status) }
        }
        try process.run()
        self.process = process
        self.stdin = inPipe.fileHandleForWriting

        // FileHandle.bytes.lines stalled on pipes in testing (no lines
        // delivered until EOF), so read with readabilityHandler and split
        // lines ourselves.
        let outLines = Self.lines(from: outPipe.fileHandleForReading)
        let errLines = Self.lines(from: errPipe.fileHandleForReading)
        Task.detached { [weak self] in
            for await line in outLines { await self?.handle(line: line) }
        }
        Task.detached { [weak self] in
            for await line in errLines { await self?.handle(stderr: line) }
        }
    }

    /// Newline-delimited lines from a pipe, in order, ending at EOF.
    static func lines(from handle: FileHandle) -> AsyncStream<String> {
        let (stream, sink) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
        let buffer = LineBuffer()
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                if let rest = buffer.flush() { sink.yield(rest) }
                sink.finish()
                return
            }
            for line in buffer.append(data) { sink.yield(line) }
        }
        return stream
    }

    public func stop() {
        process?.terminate()
    }

    private func didExit(_ status: Int32) {
        exitStatus = status
        let failure = ACPError.processExited(status, stderr: stderrTail)
        for (_, c) in pending { c.resume(throwing: failure) }
        pending.removeAll()
        stdin = nil
        eventSink.yield(.exited(status))
        eventSink.finish()
    }

    // MARK: ACP methods

    @discardableResult
    public func initialize() async throws -> InitializeResult {
        try await request("initialize", InitializeParams()).decode(as: InitializeResult.self)
    }

    public func newSession(cwd: URL) async throws -> String {
        try await request("session/new", NewSessionParams(cwd: cwd.path)).decode(as: NewSessionResult.self).sessionId
    }

    /// Sends one prompt turn. Returns the stop reason once the agent ends the
    /// turn (end_turn, max_tokens, refusal, cancelled, ...). Updates arrive on
    /// `events` while this is suspended.
    public func prompt(sessionId: String, text: String) async throws -> String {
        let params = PromptParams(sessionId: sessionId, prompt: [TextBlock(text: text)])
        return try await request("session/prompt", params).decode(as: PromptResult.self).stopReason
    }

    public func cancel(sessionId: String) throws {
        try send(["jsonrpc": .string("2.0"), "method": .string("session/cancel"),
                  "params": try JSONValue.from(SessionIdParams(sessionId: sessionId))])
    }

    /// Answers a `session/request_permission`. `nil` means cancelled.
    public func respond(to request: PermissionRequest, optionId: String?) throws {
        let outcome: JSONValue = optionId.map {
            .object(["outcome": .string("selected"), "optionId": .string($0)])
        } ?? .object(["outcome": .string("cancelled")])
        try send(["jsonrpc": .string("2.0"), "id": request.rpcId, "result": .object(["outcome": outcome])])
    }

    // MARK: JSON-RPC plumbing

    private func request(_ method: String, _ params: some Encodable) async throws -> JSONValue {
        guard stdin != nil else {
            if let exitStatus { throw ACPError.processExited(exitStatus, stderr: stderrTail) }
            throw ACPError.notStarted
        }
        let id = nextId
        nextId += 1
        let message: [String: JSONValue] = [
            "jsonrpc": .string("2.0"), "id": .int(id), "method": .string(method),
            "params": try JSONValue.from(params),
        ]
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(message) } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func send(_ message: [String: JSONValue]) throws {
        guard let stdin else { throw ACPError.notStarted }
        var data = try JSONEncoder().encode(JSONValue.object(message))
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    private struct Incoming: Decodable {
        let id: JSONValue?
        let method: String?
        let params: JSONValue?
        let result: JSONValue?
        let error: RPCErrorBody?
    }

    private struct RPCErrorBody: Decodable {
        let code: Int
        let message: String
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONDecoder().decode(Incoming.self, from: data) else {
            eventSink.yield(.stderr("unparseable line from agent: \(line.prefix(200))"))
            return
        }
        if let method = msg.method {
            handleAgentCall(method: method, id: msg.id, params: msg.params ?? .null)
        } else if case .int(let id)? = msg.id, let continuation = pending.removeValue(forKey: id) {
            if let error = msg.error {
                continuation.resume(throwing: ACPError.rpc(code: error.code, message: error.message))
            } else {
                continuation.resume(returning: msg.result ?? .null)
            }
        }
    }

    private func handleAgentCall(method: String, id: JSONValue?, params: JSONValue) {
        switch method {
        case "session/update":
            let sessionId = params["sessionId"]?.stringValue ?? ""
            eventSink.yield(.sessionUpdate(sessionId: sessionId, update: SessionUpdate(json: params["update"] ?? .null)))
        case "session/request_permission":
            guard let id else { return }
            let toolCall = params["toolCall"]
            let request = PermissionRequest(
                rpcId: id,
                sessionId: params["sessionId"]?.stringValue ?? "",
                toolCallId: toolCall?["toolCallId"]?.stringValue ?? "",
                title: toolCall?["title"]?.stringValue ?? "Permission requested",
                options: (try? params["options"]?.decode(as: [PermissionOption].self)) ?? []
            )
            eventSink.yield(.permissionRequest(request))
        default:
            // fs/* and terminal/* are not advertised in our capabilities.
            if let id {
                try? send(["jsonrpc": .string("2.0"), "id": id,
                           "error": .object(["code": .int(-32601), "message": .string("Method not found: \(method)")])])
            }
        }
    }

    private func handle(stderr line: String) {
        stderrTail = String((stderrTail + line + "\n").suffix(4000))
        eventSink.yield(.stderr(line))
    }
}

/// Accumulates bytes and hands back complete lines. readabilityHandler runs
/// on one serial queue per handle, the lock is belt and braces.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

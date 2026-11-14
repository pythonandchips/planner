import Foundation
import Observation

public enum SessionStatus: Equatable, Sendable {
    case starting
    case working
    case awaitingPermission
    /// A gate tool call or an elicitation is open: the agent is blocked
    /// mid-turn on a form.
    case awaitingAnswer
    case awaitingInput
    case failed(String)
    case exited

    public var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .awaitingPermission: return "Needs permission"
        case .awaitingAnswer: return "Awaiting answer"
        case .awaitingInput: return "Awaiting input"
        case .failed: return "Failed"
        case .exited: return "Exited"
        }
    }

    /// True when the user has to do something before the agent can continue.
    public var needsUser: Bool {
        self == .awaitingPermission || self == .awaitingAnswer || self == .awaitingInput
    }
}

public struct TranscriptItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case user(String)
        case agent(String)
        case thought(String)
        case tool(ToolCallInfo)
        case permission(PermissionRequest, chosen: PermissionOption?)
        /// A planner gate tool call (MCP), open until `answer` is set.
        case gate(GatePrompt, answer: GateAnswer?)
        /// An `elicitation/create` form (AskUserQuestion), open until answered.
        case elicitation(ElicitationRequest, response: ElicitationResponse?)
        case plan([PlanEntry])
        case notice(String)
    }

    public let id: Int
    public var kind: Kind

    /// Tool rows the UI skips because a form shows the same thing.
    public var isShadowedTool: Bool {
        guard case .tool(let info) = kind else { return false }
        return info.isPlannerGate || info.toolName == "AskUserQuestion"
    }
}

/// One agent conversation: owns an ACPClient (one agent process) and a gate
/// MCP server, turns their events into a transcript, and tracks whether the
/// agent is waiting on the user. Lives on the main actor so SwiftUI can
/// observe it directly.
@MainActor
@Observable
public final class AgentSession: Identifiable {
    public let id = UUID()
    public let title: String
    public let cwd: URL
    public let launch: AgentLaunch
    /// Extra `_meta` for session/new, merged over the gate defaults.
    public let sessionMeta: JSONValue?
    public let gatesEnabled: Bool

    public private(set) var status: SessionStatus = .starting
    public private(set) var transcript: [TranscriptItem] = []
    public private(set) var stderrLog: [String] = []
    public private(set) var acpSessionId: String?
    public private(set) var lastStopReason: String?
    /// Set while a session/prompt is in flight.
    public private(set) var turnInFlight = false
    /// Which transport the gate MCP server ended up on.
    public private(set) var gateTransportName: String?

    @ObservationIgnored private var client: ACPClient?
    @ObservationIgnored private var nextItemId = 0
    @ObservationIgnored private var toolIndex: [String: Int] = [:]
    @ObservationIgnored private var openPermissions: [JSONValue: Int] = [:]
    @ObservationIgnored private var openGates: [Int: (index: Int, continuation: CheckedContinuation<GateAnswer, Never>)] = [:]
    @ObservationIgnored private var openElicitations: [JSONValue: Int] = [:]
    @ObservationIgnored private var nextGateId = 1
    @ObservationIgnored private var gateTransport: MCPGateTransport?

    public init(title: String, cwd: URL, launch: AgentLaunch, gatesEnabled: Bool = true, sessionMeta: JSONValue? = nil) {
        self.title = title
        self.cwd = cwd
        self.launch = launch
        self.gatesEnabled = gatesEnabled
        self.sessionMeta = sessionMeta
    }

    /// `_meta` for session/new: lets the gate tools run without a
    /// permission prompt, plus anything the caller passed.
    nonisolated public static func meta(gates: Bool, extra: JSONValue?) -> JSONValue? {
        var options = extra?["claudeCode"]?["options"]?.objectValue ?? [:]
        if gates {
            var allowed = options["allowedTools"]?.arrayValue ?? []
            allowed.append(.string(GateTools.allowedToolsPattern))
            options["allowedTools"] = .array(allowed)
        }
        if options.isEmpty { return extra }
        var meta = extra?.objectValue ?? [:]
        var claude = meta["claudeCode"]?.objectValue ?? [:]
        claude["options"] = .object(options)
        meta["claudeCode"] = .object(claude)
        return .object(meta)
    }

    /// The agent's last message, if the turn ended and the message reads as
    /// a question. Fallback for agents that ask in plain text instead of
    /// calling a gate tool.
    public var pendingQuestion: String? {
        guard status == .awaitingInput else { return nil }
        guard let last = transcript.last(where: {
            if case .agent = $0.kind { return true }
            if case .user = $0.kind { return true }
            if case .gate = $0.kind { return true }
            if case .elicitation = $0.kind { return true }
            return false
        }), case .agent(let text) = last.kind else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("?") ? trimmed : nil
    }

    public var openPermissionRequests: [PermissionRequest] {
        openPermissions.values.sorted().compactMap { index in
            if case .permission(let request, nil) = transcript[index].kind { return request }
            return nil
        }
    }

    public var openGatePrompts: [GatePrompt] {
        openGates.values.map(\.index).sorted().compactMap { index in
            if case .gate(let prompt, nil) = transcript[index].kind { return prompt }
            return nil
        }
    }

    public var openElicitationRequests: [ElicitationRequest] {
        openElicitations.values.sorted().compactMap { index in
            if case .elicitation(let request, nil) = transcript[index].kind { return request }
            return nil
        }
    }

    // MARK: Actions

    public func start(prompt: String) {
        let client = ACPClient(launch: launch, cwd: cwd)
        self.client = client
        Task {
            do {
                try await client.start()
                consume(client.events)
                try await client.initialize()
                var servers: [JSONValue] = []
                if gatesEnabled {
                    let server = MCPGateServer { [weak self] kind in
                        await self?.openGate(kind) ?? .cancelled
                    }
                    let (transport, note) = MCPGateHost.start(server: server)
                    gateTransport = transport
                    gateTransportName = transport.transportName
                    if let note { stderrLog.append("planner-desk: \(note)") }
                    if transport.acpServerConfig != .null { servers.append(transport.acpServerConfig) }
                }
                acpSessionId = try await client.newSession(
                    cwd: cwd, mcpServers: servers, meta: Self.meta(gates: gatesEnabled, extra: sessionMeta))
                await runTurn(prompt)
            } catch {
                fail(error)
            }
        }
    }

    /// Sends the user's reply as the next prompt turn.
    public func reply(_ text: String) {
        guard !turnInFlight, acpSessionId != nil else { return }
        Task { await runTurn(text) }
    }

    public func choose(_ option: PermissionOption?, for request: PermissionRequest) {
        guard let index = openPermissions.removeValue(forKey: request.rpcId) else { return }
        transcript[index].kind = .permission(request, chosen: option)
        refreshStatus()
        Task { try? await client?.respond(to: request, optionId: option?.optionId) }
    }

    /// Answers an open gate; the blocked MCP tools/call returns with it.
    public func answer(_ prompt: GatePrompt, with answer: GateAnswer) {
        guard let open = openGates.removeValue(forKey: prompt.id) else { return }
        transcript[open.index].kind = .gate(prompt, answer: answer)
        refreshStatus()
        open.continuation.resume(returning: answer)
    }

    /// Answers an open `elicitation/create`.
    public func respond(to request: ElicitationRequest, with response: ElicitationResponse) {
        guard let index = openElicitations.removeValue(forKey: request.rpcId) else { return }
        transcript[index].kind = .elicitation(request, response: response)
        refreshStatus()
        Task { try? await client?.respond(to: request, with: response) }
    }

    public func cancelTurn() {
        guard let client, let sessionId = acpSessionId else { return }
        // The spec says pending permission requests must be answered "cancelled".
        for request in openPermissionRequests { choose(nil, for: request) }
        for request in openElicitationRequests { respond(to: request, with: .cancel) }
        for prompt in openGatePrompts { answer(prompt, with: .cancelled) }
        Task { try? await client.cancel(sessionId: sessionId) }
    }

    public func stop() {
        for prompt in openGatePrompts { answer(prompt, with: .cancelled) }
        gateTransport?.stop()
        Task { await client?.stop() }
    }

    // MARK: Internals

    /// Called by the gate MCP server (off the main actor) for each
    /// tools/call; suspends until `answer` is called.
    func openGate(_ kind: GateKind) async -> GateAnswer {
        await withCheckedContinuation { continuation in
            let prompt = GatePrompt(id: nextGateId, kind: kind)
            nextGateId += 1
            let index = append(.gate(prompt, answer: nil))
            openGates[prompt.id] = (index, continuation)
            refreshStatus()
        }
    }

    /// Permission outranks a form; a form outranks "working".
    private func refreshStatus() {
        switch status {
        case .failed, .exited: return
        default: break
        }
        if !openPermissions.isEmpty { status = .awaitingPermission }
        else if !openGates.isEmpty || !openElicitations.isEmpty { status = .awaitingAnswer }
        else if turnInFlight { status = .working }
        else if acpSessionId != nil { status = .awaitingInput }
    }

    private func runTurn(_ text: String) async {
        guard let client, let sessionId = acpSessionId else { return }
        append(.user(text))
        turnInFlight = true
        refreshStatus()
        do {
            let stop = try await client.prompt(sessionId: sessionId, text: text)
            lastStopReason = stop
            turnInFlight = false
            if stop != "end_turn" { append(.notice("Turn ended: \(stop)")) }
            refreshStatus()
        } catch {
            turnInFlight = false
            fail(error)
        }
    }

    private func consume(_ events: AsyncStream<ACPEvent>) {
        Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    func handle(_ event: ACPEvent) {
        switch event {
        case .sessionUpdate(_, let update):
            apply(update)
        case .permissionRequest(let request):
            openPermissions[request.rpcId] = append(.permission(request, chosen: nil))
            refreshStatus()
        case .elicitation(let request):
            openElicitations[request.rpcId] = append(.elicitation(request, response: nil))
            refreshStatus()
        case .requestCancelled(let rid):
            // The agent withdrew the request: close the form without answering.
            if let index = openElicitations.removeValue(forKey: rid),
               case .elicitation(let r, _) = transcript[index].kind {
                transcript[index].kind = .elicitation(r, response: .cancel)
            }
            if let index = openPermissions.removeValue(forKey: rid),
               case .permission(let r, _) = transcript[index].kind {
                transcript[index].kind = .permission(r, chosen: nil)
            }
            refreshStatus()
        case .stderr(let line):
            stderrLog.append(line)
            if stderrLog.count > 500 { stderrLog.removeFirst(stderrLog.count - 500) }
        case .exited(let code):
            for prompt in openGatePrompts { answer(prompt, with: .cancelled) }
            gateTransport?.stop()
            if case .failed = status { return }
            status = code == 0 ? .exited : .failed("agent exited with status \(code)")
        }
    }

    private func apply(_ update: SessionUpdate) {
        switch update {
        case .agentMessageChunk(let text):
            appendText(text, as: { .agent($0) }, matching: { if case .agent(let t) = $0 { return t }; return nil })
        case .agentThoughtChunk(let text):
            appendText(text, as: { .thought($0) }, matching: { if case .thought(let t) = $0 { return t }; return nil })
        case .userMessageChunk:
            break // echo of our own prompt; we already show it
        case .toolCall(let info):
            toolIndex[info.toolCallId] = append(.tool(info))
        case .toolCallUpdate(let info):
            guard let index = toolIndex[info.toolCallId], case .tool(var existing) = transcript[index].kind else {
                toolIndex[info.toolCallId] = append(.tool(info))
                return
            }
            existing.title = info.title ?? existing.title
            existing.kind = info.kind ?? existing.kind
            existing.status = info.status ?? existing.status
            existing.detail = info.detail ?? existing.detail
            existing.toolName = info.toolName ?? existing.toolName
            transcript[index].kind = .tool(existing)
        case .plan(let entries):
            if let index = transcript.lastIndex(where: { if case .plan = $0.kind { return true }; return false }) {
                transcript[index].kind = .plan(entries)
            } else {
                append(.plan(entries))
            }
        case .other:
            break
        }
    }

    /// Streams chunks into the last item when it is the same kind, so a
    /// message is one transcript row rather than one row per chunk.
    private func appendText(_ text: String, as make: (String) -> TranscriptItem.Kind,
                            matching existing: (TranscriptItem.Kind) -> String?) {
        if let last = transcript.indices.last, let current = existing(transcript[last].kind) {
            transcript[last].kind = make(current + text)
        } else {
            append(make(text))
        }
    }

    @discardableResult
    private func append(_ kind: TranscriptItem.Kind) -> Int {
        transcript.append(TranscriptItem(id: nextItemId, kind: kind))
        nextItemId += 1
        return transcript.count - 1
    }

    private func fail(_ error: Error) {
        let message = (error as? ACPError)?.description ?? error.localizedDescription
        append(.notice(message))
        status = .failed(message)
    }
}

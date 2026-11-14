import Foundation
import Observation

public enum SessionStatus: Equatable, Sendable {
    case starting
    case working
    case awaitingPermission
    case awaitingInput
    case failed(String)
    case exited

    public var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .awaitingPermission: return "Needs permission"
        case .awaitingInput: return "Awaiting input"
        case .failed: return "Failed"
        case .exited: return "Exited"
        }
    }

    /// True when the user has to do something before the agent can continue.
    public var needsUser: Bool { self == .awaitingPermission || self == .awaitingInput }
}

public struct TranscriptItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case user(String)
        case agent(String)
        case thought(String)
        case tool(ToolCallInfo)
        case permission(PermissionRequest, chosen: PermissionOption?)
        case plan([PlanEntry])
        case notice(String)
    }

    public let id: Int
    public var kind: Kind
}

/// One agent conversation: owns an ACPClient (one agent process), turns its
/// events into a transcript, and tracks whether the agent is waiting on the
/// user. Lives on the main actor so SwiftUI can observe it directly.
@MainActor
@Observable
public final class AgentSession: Identifiable {
    public let id = UUID()
    public let title: String
    public let cwd: URL
    public let launch: AgentLaunch

    public private(set) var status: SessionStatus = .starting
    public private(set) var transcript: [TranscriptItem] = []
    public private(set) var stderrLog: [String] = []
    public private(set) var acpSessionId: String?
    public private(set) var lastStopReason: String?
    /// Set while a session/prompt is in flight.
    public private(set) var turnInFlight = false

    @ObservationIgnored private var client: ACPClient?
    @ObservationIgnored private var nextItemId = 0
    @ObservationIgnored private var toolIndex: [String: Int] = [:]
    @ObservationIgnored private var openPermissions: [JSONValue: Int] = [:]

    public init(title: String, cwd: URL, launch: AgentLaunch) {
        self.title = title
        self.cwd = cwd
        self.launch = launch
    }

    /// The agent's last message, if the turn ended and the message reads as
    /// a question. ACP has no "question" message; Claude asks in plain text
    /// and ends its turn, so this is a heuristic for the UI to highlight.
    public var pendingQuestion: String? {
        guard status == .awaitingInput else { return nil }
        guard let last = transcript.last(where: {
            if case .agent = $0.kind { return true }
            if case .user = $0.kind { return true }
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

    // MARK: Actions

    public func start(prompt: String) {
        let client = ACPClient(launch: launch, cwd: cwd)
        self.client = client
        Task {
            do {
                try await client.start()
                consume(client.events)
                try await client.initialize()
                acpSessionId = try await client.newSession(cwd: cwd)
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
        if openPermissions.isEmpty, status == .awaitingPermission { status = .working }
        Task { try? await client?.respond(to: request, optionId: option?.optionId) }
    }

    public func cancelTurn() {
        guard let client, let sessionId = acpSessionId else { return }
        // The spec says pending permission requests must be answered "cancelled".
        for request in openPermissionRequests { choose(nil, for: request) }
        Task { try? await client.cancel(sessionId: sessionId) }
    }

    public func stop() {
        Task { await client?.stop() }
    }

    // MARK: Internals

    private func runTurn(_ text: String) async {
        guard let client, let sessionId = acpSessionId else { return }
        append(.user(text))
        turnInFlight = true
        status = .working
        do {
            let stop = try await client.prompt(sessionId: sessionId, text: text)
            lastStopReason = stop
            turnInFlight = false
            if stop != "end_turn" { append(.notice("Turn ended: \(stop)")) }
            if status != .exited { status = .awaitingInput }
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
            status = .awaitingPermission
        case .stderr(let line):
            stderrLog.append(line)
            if stderrLog.count > 500 { stderrLog.removeFirst(stderrLog.count - 500) }
        case .exited(let code):
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

import Foundation
import Testing
@testable import PlannerCore

let mockAgentPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("mock-agent/mock_acp_agent.py").path

let mockLaunch = AgentLaunch(executable: "/usr/bin/env", arguments: ["python3", mockAgentPath])

/// Polls a main-actor condition; SwiftUI-free stand-in for "the view updated".
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw CancellationError() }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@Suite struct ACPClientTests {
    @Test func rawClientStreamsUpdatesAndPermission() async throws {
        let cwd = URL(fileURLWithPath: "/")
        let client = ACPClient(launch: mockLaunch, cwd: cwd)
        try await client.start()
        let initResult = try await client.initialize()
        #expect(initResult.protocolVersion == 1)
        let sessionId = try await client.newSession(cwd: cwd)
        #expect(sessionId == "sess_1")

        // Collect events and answer the permission request as it arrives.
        let collector = Task { () -> [SessionUpdate] in
            var updates: [SessionUpdate] = []
            for await event in client.events {
                switch event {
                case .sessionUpdate(_, let u): updates.append(u)
                case .permissionRequest(let request):
                    #expect(request.options.map(\.kind) == ["allow_once", "allow_always", "reject_once"])
                    try? await client.respond(to: request, optionId: "allow-once")
                default: break
                }
                if case .agentMessageChunk(let t) = updates.last, t.hasSuffix("A or B?") { break }
            }
            return updates
        }
        let stop = try await client.prompt(sessionId: sessionId, text: "hello")
        #expect(stop == "end_turn")
        let updates = await collector.value
        #expect(updates.contains(.toolCall(ToolCallInfo(toolCallId: "call_1", title: "Edit docs/plans/notes.md",
                                                         kind: "edit", status: "pending", detail: nil))))
        #expect(updates.contains {
            if case .toolCallUpdate(let i) = $0 { return i.status == "completed" && i.detail == "Wrote 3 lines" }
            return false
        })
        await client.stop()
    }

    @Test func failsCleanlyWhenAgentCommandIsMissing() async throws {
        let client = ACPClient(launch: AgentLaunch(executable: "/usr/bin/false", arguments: []),
                               cwd: URL(fileURLWithPath: "/"))
        try await client.start()
        await #expect(throws: ACPError.self) { try await client.initialize() }
    }

    @Test func writingAfterTheAgentDiedThrowsInsteadOfSIGPIPE() async throws {
        let client = ACPClient(launch: AgentLaunch(executable: "/bin/sh", arguments: ["-c", "exec 0<&-; exit 0"]),
                               cwd: URL(fileURLWithPath: "/"))
        try await client.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        await #expect(throws: ACPError.self) { try await client.initialize() }
    }
}

@Suite @MainActor struct AgentSessionTests {
    @Test func fullTurnWithPermissionQuestionAndReply() async throws {
        let session = AgentSession(title: "explore", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        session.start(prompt: "Explore ITERATION-001.md")

        try await waitUntil { session.status == .awaitingPermission }
        let request = try #require(session.openPermissionRequests.first)
        #expect(request.title == "Edit docs/plans/notes.md")
        session.choose(request.options[0], for: request)

        try await waitUntil { session.status == .awaitingInput }
        #expect(session.pendingQuestion?.hasSuffix("Which approach do you prefer: A or B?") == true)
        #expect(session.openPermissionRequests.isEmpty)

        // Chunks are coalesced into one agent row per contiguous stream.
        let agentTexts = session.transcript.compactMap { item -> String? in
            if case .agent(let t) = item.kind { return t }
            return nil
        }
        #expect(agentTexts == ["I'll look at the plan folder first.\n\n",
                               "Done editing. Which approach do you prefer: A or B?"])
        let tool = session.transcript.compactMap { item -> ToolCallInfo? in
            if case .tool(let t) = item.kind { return t }
            return nil
        }.first
        #expect(tool?.status == "completed")

        session.reply("A")
        try await waitUntil { session.status == .working }
        try await waitUntil { session.status == .awaitingInput }
        if case .agent(let last)? = session.transcript.last?.kind {
            #expect(last == "You said: A. All done.")
        } else {
            Issue.record("expected the agent's answer last")
        }
        #expect(session.pendingQuestion == nil)
        session.stop()
    }

    @Test func rejectingPermissionFailsTheTool() async throws {
        let session = AgentSession(title: "plan", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        session.start(prompt: "Plan")
        try await waitUntil { session.status == .awaitingPermission }
        let request = try #require(session.openPermissionRequests.first)
        session.choose(request.options.first { !$0.isAllow }, for: request)
        try await waitUntil { session.status == .awaitingInput }
        let statuses = session.transcript.compactMap { item -> String? in
            if case .tool(let t) = item.kind { return t.status }
            return nil
        }
        #expect(statuses == ["failed"])
        session.stop()
    }

    @Test func twoSessionsRunConcurrently() async throws {
        let a = AgentSession(title: "explore", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        let b = AgentSession(title: "run", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        a.start(prompt: "one")
        b.start(prompt: "two")
        try await waitUntil { a.status == .awaitingPermission && b.status == .awaitingPermission }
        // Answer b first: the sessions are independent.
        b.choose(b.openPermissionRequests[0].options[0], for: b.openPermissionRequests[0])
        try await waitUntil { b.status == .awaitingInput }
        #expect(a.status == .awaitingPermission)
        a.choose(a.openPermissionRequests[0].options[0], for: a.openPermissionRequests[0])
        try await waitUntil { a.status == .awaitingInput }
        a.stop()
        b.stop()
    }

    @Test func agentExitIsReported() async throws {
        let session = AgentSession(title: "bad", cwd: URL(fileURLWithPath: "/"),
                                   launch: AgentLaunch(executable: "/bin/sh", arguments: ["-c", "echo boom >&2; exit 3"]))
        session.start(prompt: "x")
        try await waitUntil {
            if case .failed = session.status { return true }
            return false
        }
        #expect(session.stderrLog.contains("boom") || session.transcript.contains {
            if case .notice(let n) = $0.kind { return n.contains("status 3") }
            return false
        })
    }
}

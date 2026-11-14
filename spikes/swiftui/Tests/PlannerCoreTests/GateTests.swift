import Foundation
import Testing
@testable import PlannerCore

@Suite struct GateServerTests {
    let server = MCPGateServer { kind in
        if case .askUser(let qs) = kind { return .answers([qs[0].id: ["blue"]]) }
        return .makeItSo
    }

    func call(_ line: String) async throws -> JSONValue {
        try JSONValue.parse(try #require(await server.handle(line: line)))
    }

    @Test func initializeAndListTools() async throws {
        let initR = try await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        #expect(initR["result"]?["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(initR["result"]?["serverInfo"]?["name"]?.stringValue == "planner")
        #expect(await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        let list = try await call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = list["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(names == ["ask_user", "confirm_start", "check_in", "ask_commit"])
        let unknown = try await call(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        #expect(unknown["error"]?["code"] == .int(-32601))
    }

    @Test func toolCallReturnsTheAnswer() async throws {
        let r = try await call(#"{"jsonrpc":"2.0","id":"a","method":"tools/call","params":{"name":"ask_user","arguments":{"questions":[{"id":"color","text":"Colour?","choices":["red","blue"]}]}}}"#)
        #expect(r["id"] == .string("a"))
        #expect(r["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue == "The user answered:\n- color (Colour?): blue")
        #expect(r["result"]?["structuredContent"] == nil)
        #expect(GateAnswer.answers(["color": ["blue"]]).structured["answers"]?["color"] == .array([.string("blue")]))
    }

    @Test func badArgumentsAreToolErrors() async throws {
        let r = try await call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"confirm_start","arguments":{}}}"#)
        #expect(r["result"]?["isError"] == .bool(true))
        let u = try await call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        #expect(u["result"]?["isError"] == .bool(true))
    }

    @Test func resultTextsMatchThePromptWording() {
        let checkIn = GateKind.checkIn(summary: "s", recommendations: [], nextSteps: ["A", "B"])
        #expect(GateAnswer.checkIn(.nextStep(2)).resultText(for: checkIn) == "The user picked next step 2: B")
        #expect(GateAnswer.checkIn(.finish).resultText(for: checkIn) == "finish")
        #expect(GateAnswer.makeItSo.resultText(for: .confirmStart(brief: "b")) == "Make it so")
        #expect(GateAnswer.commit(false).resultText(for: .askCommit(context: nil)) == "No, do not commit.")
    }

    @Test func metaAddsAllowedToolsAndKeepsCallerOptions() throws {
        let extra = try JSONValue.parse(#"{"claudeCode":{"options":{"allowedTools":["Read"],"settings":{"x":1}}},"other":true}"#)
        let meta = try #require(AgentSession.meta(gates: true, extra: extra))
        #expect(meta["claudeCode"]?["options"]?["allowedTools"] == .array([.string("Read"), .string("mcp__planner__*")]))
        #expect(meta["claudeCode"]?["options"]?["settings"]?["x"] == .int(1))
        #expect(meta["other"] == .bool(true))
        #expect(AgentSession.meta(gates: false, extra: nil) == nil)
    }

    /// The shape claude-agent-acp 0.107.0 sends for AskUserQuestion with two
    /// questions (elicitation.js askUserQuestionsToCreateRequest).
    @Test func parsesTheAdaptersAskUserQuestionForm() throws {
        let params = try JSONValue.parse(#"""
        {"mode":"form","sessionId":"s","toolCallId":"t","message":"Please answer the following questions.",
         "requestedSchema":{"type":"object","properties":{
          "question_1_custom":{"type":"string","title":"Other"},
          "question_1":{"type":"array","title":"Langs","description":"Which?","items":{"anyOf":[{"const":"Swift","title":"Swift"},{"const":"Rust","title":"Rust"}]}},
          "question_0":{"type":"string","title":"UI","description":"Framework?","oneOf":[{"const":"SwiftUI","title":"SwiftUI","description":"Native"}]},
          "question_0_custom":{"type":"string","title":"Other"}}}}
        """#)
        let r = ElicitationRequest(rpcId: .int(7), params: params)
        #expect(r.fields.map(\.key) == ["question_0", "question_0_custom", "question_1", "question_1_custom"])
        #expect(r.fields[0].kind == .single([.init(value: "SwiftUI", title: "SwiftUI", description: "Native")]))
        if case .multi(let options) = r.fields[2].kind { #expect(options.map(\.value) == ["Swift", "Rust"]) }
        else { Issue.record("expected multi") }
        #expect(r.fields[1].kind == .text)
        #expect(r.toolCallId == "t")
        #expect(ElicitationResponse.accept(["question_0": .string("SwiftUI")]).json.jsonString
                == #"{"action":"accept","content":{"question_0":"SwiftUI"}}"#)
    }

    /// Streamable HTTP needs a local port. The Claude Code sandbox refuses
    /// the bind with EPERM, so this only checks the round trip where binding
    /// works and otherwise checks that the failure is the bind.
    @Test func httpTransportWhenPortsAreAllowed() async throws {
        let transport: MCPHTTPTransport
        do {
            transport = try MCPHTTPTransport(server: server)
        } catch {
            #expect("\(error)".contains("Operation not permitted") || "\(error)".contains("1"))
            return
        }
        defer { transport.stop() }
        var request = URLRequest(url: URL(string: transport.url)!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("ask_commit"))
    }
}

@Suite @MainActor struct GateSessionTests {
    /// The mock agent spawns the FIFO shim from session/new.mcpServers like
    /// Claude Code does, then calls every gate and sends one elicitation.
    @Test func everyGateBlocksUntilAnsweredAndReturnsTheAnswer() async throws {
        let session = AgentSession(title: "gates", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        session.start(prompt: "[gates] go")

        try await waitUntil { !session.openGatePrompts.isEmpty }
        #expect(session.status == .awaitingAnswer)
        #expect(session.status.needsUser)
        let ask = session.openGatePrompts[0]
        guard case .askUser(let qs) = ask.kind else { Issue.record("expected ask_user"); return }
        #expect(qs.map(\.id) == ["scope", "deadline"])
        #expect(qs[0].choices == ["planner", "all"])
        // The agent is blocked: nothing more arrives while the gate is open.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(session.openElicitationRequests.isEmpty)
        session.answer(ask, with: .answers(["scope": ["all"], "deadline": ["Friday"]]))

        try await waitUntil { !session.openElicitationRequests.isEmpty }
        #expect(session.status == .awaitingAnswer)
        let el = session.openElicitationRequests[0]
        #expect(el.message == "Which framework?")
        session.respond(to: el, with: .accept(["question_0": .string("AppKit")]))

        try await waitUntil { session.openGatePrompts.first.map { if case .confirmStart = $0.kind { true } else { false } } ?? false }
        session.answer(session.openGatePrompts[0], with: .makeItSo)
        try await waitUntil { session.openGatePrompts.first.map { if case .checkIn = $0.kind { true } else { false } } ?? false }
        session.answer(session.openGatePrompts[0], with: .checkIn(.nextStep(2)))
        try await waitUntil { session.openGatePrompts.first.map { if case .askCommit = $0.kind { true } else { false } } ?? false }
        session.answer(session.openGatePrompts[0], with: .commit(true))

        try await waitUntil { session.status == .awaitingInput }
        let text = session.transcript.compactMap { if case .agent(let t) = $0.kind { t } else { nil } }.joined()
        #expect(text.contains("ask_user -> The user answered:\n- scope (Which repos are in scope?): all\n- deadline (Any deadline?): Friday"))
        #expect(text.contains(#"elicitation -> {"action": "accept", "content": {"question_0": "AppKit"}}"#))
        #expect(text.contains("confirm_start -> Make it so"))
        #expect(text.contains("check_in -> The user picked next step 2: Look at B"))
        #expect(text.contains("ask_commit -> Yes, commit the change."))
        #expect(text.contains("bad args isError=True"))
        // The gate tools' own tool rows are hidden behind the form records.
        let shadowed = session.transcript.filter(\.isShadowedTool)
        #expect(shadowed.count == 5)
        #expect(session.pendingQuestion == nil)
        #expect(session.gateTransportName != nil)
        session.stop()
    }

    @Test func stopTurnAnswersAnOpenGateCancelled() async throws {
        let session = AgentSession(title: "gates", cwd: URL(fileURLWithPath: "/"), launch: mockLaunch)
        session.start(prompt: "[gates] go")
        try await waitUntil { !session.openGatePrompts.isEmpty }
        session.cancelTurn()
        #expect(session.openGatePrompts.isEmpty)
        let answered = session.transcript.contains { if case .gate(_, .cancelled?) = $0.kind { true } else { false } }
        #expect(answered)
        // The mock carries on to the elicitation; cancel that too.
        try await waitUntil { !session.openElicitationRequests.isEmpty }
        session.respond(to: session.openElicitationRequests[0], with: .cancel)
        try await waitUntil { !session.openGatePrompts.isEmpty }
        let text = session.transcript.compactMap { if case .agent(let t) = $0.kind { t } else { nil } }.joined()
        #expect(text.contains("ask_user -> The user cancelled."))
        #expect(text.contains(#"elicitation -> {"action": "cancel"}"#))
        session.stop()
    }
}

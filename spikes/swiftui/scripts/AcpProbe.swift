// Headless check of PlannerCore's ACP client and gate MCP server against a
// real agent. Build and run with:
//   scripts/swiftc-build.sh probe ["agent command"] [prompt]
// Without a prompt it only does initialize + session/new (no model call).
//
// Environment:
//   PROBE_DELAY  seconds to wait before answering a gate or elicitation (default 1)
//   PROBE_META   JSON merged into session/new _meta (e.g. claudeCode.options.settings)
//   PROBE_MODE   if set, session/set_config_option {configId: "mode", value: $PROBE_MODE}
//   PROBE_NO_GATES=1  do not pass the gate MCP server
//   PROBE_PERMISSION  optionId kind to pick: allow_once (default) or reject_once
// Every ACP and MCP line is printed with a timestamp, as `acp->`, `acp<-`,
// `mcp<-`, `mcp->`.
import Foundation
import PlannerCore

let started = Date()
func stamp() -> String { String(format: "%7.2fs", Date().timeIntervalSince(started)) }
func log(_ s: String) {
    print("[\(stamp())] \(s)")
    fflush(stdout)
}

@main struct AcpProbe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let env = ProcessInfo.processInfo.environment
        let command = args.first ?? AgentLaunch.defaultCommand
        let prompt = args.count > 1 ? args[1] : nil
        let delay = Double(env["PROBE_DELAY"] ?? "1") ?? 1
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let client = ACPClient(launch: .shell(command), cwd: cwd) { dir, line in log("acp\(dir) \(line)") }
        do {
            try await client.start()
            let events = Task {
                for await event in client.events {
                    switch event {
                    case .stderr(let line): log("stderr: \(line)")
                    case .sessionUpdate: break // already in the acp<- trace
                    case .permissionRequest(let request):
                        log("PERMISSION title=\(request.title) options=\(request.options.map { "\($0.optionId)/\($0.kind)/\($0.name)" })")
                        let want = env["PROBE_PERMISSION"] ?? "allow_once"
                        let pick = request.options.first { $0.kind == want } ?? request.options.first
                        try? await client.respond(to: request, optionId: pick?.optionId)
                    case .elicitation(let request):
                        log("ELICITATION message=\(request.message) fields=\(request.fields.map { "\($0.key):\($0.kind)" })")
                        log("waiting \(delay)s before answering the elicitation")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                        var content: [String: JSONValue] = [:]
                        for field in request.fields {
                            switch field.kind {
                            case .single(let options): if let o = options.first { content[field.key] = .string(o.value) }
                            case .multi(let options): content[field.key] = .array(options.prefix(1).map { .string($0.value) })
                            default: break
                            }
                        }
                        try? await client.respond(to: request, with: .accept(content))
                    case .requestCancelled(let id): log("CANCEL_REQUEST id=\(id)")
                    case .exited(let code): log("exited: \(code)")
                    }
                }
            }
            let initResult = try await client.initialize()
            log("initialize ok: protocolVersion=\(initResult.protocolVersion)")

            var servers: [JSONValue] = []
            var transport: MCPGateTransport?
            if env["PROBE_NO_GATES"] != "1" {
                let server = MCPGateServer(trace: { dir, line in log("\(dir) \(line)") }) { kind in
                    log("GATE OPEN \(kind)")
                    log("waiting \(delay)s before answering the gate")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                    let answer: GateAnswer
                    switch kind {
                    case .askUser(let questions):
                        answer = .answers(Dictionary(uniqueKeysWithValues: questions.map {
                            ($0.id, [$0.choices.first ?? "probe free-text answer"])
                        }))
                    case .confirmStart: answer = .makeItSo
                    case .checkIn: answer = .checkIn(.finish)
                    case .askCommit: answer = .commit(false)
                    }
                    log("GATE ANSWER \(answer.summary)")
                    return answer
                }
                let (t, note) = MCPGateHost.start(server: server)
                transport = t
                log("gate transport: \(t.transportName)\(note.map { " (\($0))" } ?? "")")
                servers.append(t.acpServerConfig)
            }
            let extra = try env["PROBE_META"].map { try JSONValue.parse($0) }
            let meta = AgentSession.meta(gates: !servers.isEmpty, extra: extra)
            let sessionId = try await client.newSession(cwd: cwd, mcpServers: servers, meta: meta)
            log("session/new ok: \(sessionId)")
            if let mode = env["PROBE_MODE"] {
                let r = try await client.call("session/set_config_option", params: .object([
                    "sessionId": .string(sessionId), "configId": .string("mode"), "value": .string(mode)]))
                log("set mode \(mode): \(r.jsonString.prefix(300))")
            }
            if let prompt {
                let stop = try await client.prompt(sessionId: sessionId, text: prompt)
                log("stopReason: \(stop)")
            }
            transport?.stop()
            await client.stop()
            try? await Task.sleep(nanoseconds: 300_000_000)
            events.cancel()
        } catch {
            log("probe failed: \(error)")
            await client.stop()
            exit(1)
        }
    }
}

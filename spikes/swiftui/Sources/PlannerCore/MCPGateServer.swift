import Foundation

/// A minimal MCP server (JSON-RPC 2.0) exposing planner's gate tools:
/// initialize, ping, tools/list, tools/call. Transport-agnostic: a transport
/// hands it one message and writes back whatever it returns. `tools/call`
/// suspends on `onGate` until the user answers, so transports must handle
/// each message in its own task.
public final class MCPGateServer: Sendable {
    public typealias GateHandler = @Sendable (GateKind) async -> GateAnswer
    public typealias Trace = @Sendable (_ direction: String, _ line: String) -> Void

    static let knownVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]

    let onGate: GateHandler
    let trace: Trace?

    public init(trace: Trace? = nil, onGate: @escaping GateHandler) {
        self.onGate = onGate
        self.trace = trace
    }

    /// Handles one JSON-RPC message. Returns the response line, or nil for
    /// notifications and responses.
    public func handle(line: String) async -> String? {
        trace?("mcp<-", line)
        guard let msg = try? JSONValue.parse(line) else {
            return reply(.null, error: (-32700, "Parse error"))
        }
        let id = msg["id"]
        guard let method = msg["method"]?.stringValue else { return nil } // a response; we send no requests
        guard let id else { return nil } // notifications/initialized, notifications/cancelled, ...
        let params = msg["params"] ?? .null
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.stringValue ?? ""
            return reply(id, result: .object([
                "protocolVersion": .string(Self.knownVersions.contains(asked) ? asked : "2025-06-18"),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string(GateTools.serverName), "version": .string("0.0.1")]),
                "instructions": .string("Planner's GUI. Use these tools whenever you need the user: they block until the user answers in the app."),
            ]))
        case "ping":
            return reply(id, result: .object([:]))
        case "tools/list":
            return reply(id, result: .object(["tools": GateTools.definitions]))
        case "tools/call":
            let name = params["name"]?.stringValue ?? ""
            let kind: GateKind
            do {
                kind = try GateTools.parse(name: name, arguments: params["arguments"] ?? .object([:]))
            } catch {
                // Tool errors go back as isError results so the model can retry.
                return reply(id, result: .object([
                    "content": .array([.object(["type": .string("text"), "text": .string("\(error)")])]),
                    "isError": .bool(true),
                ]))
            }
            let answer = await onGate(kind)
            // Text only. With `structuredContent` present, Claude Code
            // 2.1.323 gave the model the JSON (`{"start":true}`) instead of
            // the text ("Make it so"), which the prompts' wording relies on.
            return reply(id, result: .object([
                "content": .array([.object(["type": .string("text"), "text": .string(answer.resultText(for: kind))])]),
                "isError": .bool(false),
            ]))
        default:
            return reply(id, error: (-32601, "Method not found: \(method)"))
        }
    }

    private func reply(_ id: JSONValue, result: JSONValue? = nil, error: (Int, String)? = nil) -> String {
        var msg: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": id]
        if let error {
            msg["error"] = .object(["code": .int(error.0), "message": .string(error.1)])
        } else {
            msg["result"] = result ?? .null
        }
        let line = JSONValue.object(msg).jsonString
        trace?("mcp->", line)
        return line
    }
}

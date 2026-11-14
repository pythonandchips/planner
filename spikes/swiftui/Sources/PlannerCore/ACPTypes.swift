import Foundation

// The subset of the Agent Client Protocol (https://agentclientprotocol.com)
// the spike needs. Hand-rolled: there is no official Swift SDK, and the
// community ones are young; this file is about 150 lines.

public struct PermissionOption: Codable, Hashable, Sendable, Identifiable {
    public let optionId: String
    public let name: String
    /// allow_once, allow_always, reject_once, reject_always
    public let kind: String
    public var id: String { optionId }
    public var isAllow: Bool { kind.hasPrefix("allow") }

    public init(optionId: String, name: String, kind: String) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }
}

/// A `session/request_permission` call from the agent. The agent is blocked
/// until the client answers it.
public struct PermissionRequest: Hashable, Sendable, Identifiable {
    public let rpcId: JSONValue
    public let sessionId: String
    public let toolCallId: String
    public let title: String
    public let options: [PermissionOption]
    public var id: JSONValue { rpcId }
}

public struct ToolCallInfo: Hashable, Sendable {
    public var toolCallId: String
    public var title: String?
    public var kind: String?
    /// pending, in_progress, completed, failed
    public var status: String?
    public var detail: String?
}

public struct PlanEntry: Hashable, Sendable, Codable {
    public let content: String
    public let status: String?
    public let priority: String?
}

public enum SessionUpdate: Hashable, Sendable {
    case agentMessageChunk(String)
    case agentThoughtChunk(String)
    case userMessageChunk(String)
    case toolCall(ToolCallInfo)
    case toolCallUpdate(ToolCallInfo)
    case plan([PlanEntry])
    case other(String)

    /// Parses the `update` field of a `session/update` notification.
    public init(json u: JSONValue) {
        let kind = u["sessionUpdate"]?.stringValue ?? "unknown"
        switch kind {
        case "agent_message_chunk": self = .agentMessageChunk(Self.text(of: u["content"]))
        case "agent_thought_chunk": self = .agentThoughtChunk(Self.text(of: u["content"]))
        case "user_message_chunk": self = .userMessageChunk(Self.text(of: u["content"]))
        case "tool_call", "tool_call_update":
            let info = ToolCallInfo(
                toolCallId: u["toolCallId"]?.stringValue ?? "?",
                title: u["title"]?.stringValue,
                kind: u["kind"]?.stringValue,
                status: u["status"]?.stringValue,
                detail: Self.toolDetail(u["content"])
            )
            self = kind == "tool_call" ? .toolCall(info) : .toolCallUpdate(info)
        case "plan":
            self = .plan((try? u["entries"]?.decode(as: [PlanEntry].self)) ?? [])
        default: self = .other(kind)
        }
    }

    static func text(of block: JSONValue?) -> String {
        guard let block else { return "" }
        if block["type"]?.stringValue == "text" { return block["text"]?.stringValue ?? "" }
        if let uri = block["uri"]?.stringValue { return "[\(uri)]" }
        return "[\(block["type"]?.stringValue ?? "content")]"
    }

    static func toolDetail(_ content: JSONValue?) -> String? {
        guard let items = content?.arrayValue, !items.isEmpty else { return nil }
        let parts = items.map { item -> String in
            switch item["type"]?.stringValue {
            case "content": return text(of: item["content"])
            case "diff": return "diff: \(item["path"]?.stringValue ?? "?")"
            case "terminal": return "terminal: \(item["terminalId"]?.stringValue ?? "?")"
            default: return ""
            }
        }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

// MARK: - Request params / results

struct InitializeParams: Encodable {
    struct FS: Encodable { let readTextFile = false; let writeTextFile = false }
    struct Caps: Encodable { let fs = FS(); let terminal = false }
    struct Info: Encodable { let name = "planner-desk"; let version = "0.0.1" }
    let protocolVersion = 1
    let clientCapabilities = Caps()
    let clientInfo = Info()
}

public struct InitializeResult: Decodable, Sendable {
    public let protocolVersion: Int
    public let agentCapabilities: JSONValue?
    public let authMethods: JSONValue?
}

struct NewSessionParams: Encodable {
    let cwd: String
    let mcpServers: [JSONValue] = []
}

struct NewSessionResult: Decodable { let sessionId: String }

struct TextBlock: Encodable {
    let type = "text"
    let text: String
}

struct PromptParams: Encodable {
    let sessionId: String
    let prompt: [TextBlock]
}

struct PromptResult: Decodable { let stopReason: String }

struct SessionIdParams: Encodable { let sessionId: String }

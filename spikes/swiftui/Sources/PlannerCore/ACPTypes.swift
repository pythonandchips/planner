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
    /// The Claude adapter's `_meta.claudeCode.toolName`, e.g.
    /// `mcp__planner__ask_user` or `AskUserQuestion`.
    public var toolName: String? = nil

    /// Planner's own gate tools render as forms, not as tool rows.
    public var isPlannerGate: Bool {
        (toolName ?? "").hasPrefix("mcp__\(GateTools.serverName)__")
            || GateTools.names.contains { (title ?? "").contains("mcp__\(GateTools.serverName)__\($0)") }
    }
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
                detail: Self.toolDetail(u["content"]),
                toolName: u["_meta"]?["claudeCode"]?["toolName"]?.stringValue
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
    struct Empty: Encodable {}
    /// `form: {}` advertises form elicitation. The Claude adapter only
    /// enables AskUserQuestion (as `elicitation/create`) when it is present.
    struct Elicitation: Encodable { let form = Empty() }
    struct Caps: Encodable { let fs = FS(); let terminal = false; let elicitation = Elicitation() }
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
    let mcpServers: [JSONValue]
    let _meta: JSONValue?
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

// MARK: - Elicitation (elicitation/create, form mode)

/// One field of an elicitation form, from `requestedSchema.properties`.
public struct ElicitationField: Hashable, Sendable, Identifiable {
    public struct Option: Hashable, Sendable, Identifiable {
        public let value: String
        public let title: String
        public let description: String?
        public var id: String { value }
    }

    public enum Kind: Hashable, Sendable {
        case single([Option])
        case multi([Option])
        case text
        case bool
        case number
    }

    public let key: String
    public let title: String?
    public let description: String?
    public let kind: Kind
    public let required: Bool
    public var id: String { key }
}

/// An `elicitation/create` request in form mode. The agent is blocked until
/// the client answers accept (with content), decline or cancel.
public struct ElicitationRequest: Hashable, Sendable, Identifiable {
    public let rpcId: JSONValue
    public let sessionId: String
    public let toolCallId: String?
    public let mode: String
    public let message: String
    public let fields: [ElicitationField]
    public var id: JSONValue { rpcId }

    public init(rpcId: JSONValue, params p: JSONValue) {
        self.rpcId = rpcId
        sessionId = p["sessionId"]?.stringValue ?? ""
        toolCallId = p["toolCallId"]?.stringValue
        mode = p["mode"]?.stringValue ?? "form"
        message = p["message"]?.stringValue ?? ""
        let schema = p["requestedSchema"]
        let required = Set(schema?["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        let props = schema?["properties"]?.objectValue ?? [:]
        // JSON object order is not kept by the decoder; the adapter's keys
        // (question_0, question_0_custom, question_1, ...) sort naturally.
        fields = props.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key in
            let s = props[key]!
            func options(_ list: JSONValue?) -> [ElicitationField.Option] {
                (list?.arrayValue ?? []).map {
                    let value = $0["const"]?.stringValue ?? $0.stringValue ?? ""
                    return .init(value: value, title: $0["title"]?.stringValue ?? value,
                                 description: $0["description"]?.stringValue)
                }
            }
            let kind: ElicitationField.Kind
            switch s["type"]?.stringValue {
            case "array":
                let items = s["items"]
                kind = .multi(options(items?["anyOf"] ?? items?["enum"]))
            case "boolean": kind = .bool
            case "number", "integer": kind = .number
            default:
                if let one = s["oneOf"] { kind = .single(options(one)) }
                else if let e = s["enum"] { kind = .single(options(e)) }
                else { kind = .text }
            }
            return ElicitationField(key: key, title: s["title"]?.stringValue,
                                    description: s["description"]?.stringValue,
                                    kind: kind, required: required.contains(key))
        }
    }
}

public enum ElicitationResponse: Hashable, Sendable {
    case accept([String: JSONValue])
    case decline
    case cancel

    public var json: JSONValue {
        switch self {
        case .accept(let content): return .object(["action": .string("accept"), "content": .object(content)])
        case .decline: return .object(["action": .string("decline")])
        case .cancel: return .object(["action": .string("cancel")])
        }
    }
}

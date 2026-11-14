import Foundation

// Planner's "gates": the points where a prompt stops and waits for the user.
// The app hosts an MCP server (see MCPGateServer) that exposes one tool per
// gate. A tool call blocks until the user answers in a native form, and the
// answer goes back to the agent as the tool result. This replaces guessing
// from "the turn ended and the last message has a ?".

public struct GateQuestion: Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    /// Empty means free text.
    public let choices: [String]
    public let multi: Bool

    public init(id: String, text: String, choices: [String] = [], multi: Bool = false) {
        self.id = id
        self.text = text
        self.choices = choices
        self.multi = multi
    }
}

public enum GateKind: Hashable, Sendable {
    /// explore/plan step "ask the user about all of them together".
    case askUser(questions: [GateQuestion])
    /// explore_deep's `Reply "Make it so" to start the unattended work.`
    case confirmStart(brief: String)
    /// _explore_check_in: Summary, Recommendations, numbered Next steps.
    case checkIn(summary: String, recommendations: [String], nextSteps: [String])
    /// plan step 4: "should this plan's change be committed?"
    case askCommit(context: String?)

    public var label: String {
        switch self {
        case .askUser: return "Questions"
        case .confirmStart: return "Ready to start"
        case .checkIn: return "Check-in"
        case .askCommit: return "Commit?"
        }
    }
}

/// One open gate: a blocked `tools/call`.
public struct GatePrompt: Hashable, Sendable, Identifiable {
    public let id: Int
    public let kind: GateKind
    public init(id: Int, kind: GateKind) {
        self.id = id
        self.kind = kind
    }
}

public enum CheckInChoice: Hashable, Sendable {
    case nextStep(Int)      // 1-based, as numbered in the check-in
    case focus(String)      // "name an aspect to focus on"
    case keepGoing          // "say continue"
    case finish             // "say finish"
}

public enum GateAnswer: Hashable, Sendable {
    /// Question id -> chosen values (one for single choice or free text).
    case answers([String: [String]])
    case makeItSo
    case clarifyMore(String)
    case checkIn(CheckInChoice)
    case commit(Bool)
    /// The user stopped the turn or closed the session.
    case cancelled

    /// The tool result text the model reads. Written as plain sentences
    /// so the prompt's own wording ("Make it so", "finish") still applies.
    public func resultText(for kind: GateKind) -> String {
        switch (self, kind) {
        case (.answers(let answers), .askUser(let questions)):
            let lines = questions.map { q -> String in
                let a = answers[q.id] ?? []
                return "- \(q.id) (\(q.text)): \(a.isEmpty ? "(no answer)" : a.joined(separator: ", "))"
            }
            return "The user answered:\n" + lines.joined(separator: "\n")
        case (.makeItSo, _):
            return "Make it so"
        case (.clarifyMore(let note), _):
            return "The user wants to clarify more before starting. Their reply: \(note.isEmpty ? "(none)" : note)"
        case (.checkIn(.nextStep(let n)), .checkIn(_, _, let steps)):
            let text = steps.indices.contains(n - 1) ? steps[n - 1] : "?"
            return "The user picked next step \(n): \(text)"
        case (.checkIn(.focus(let aspect)), _):
            return "The user wants you to focus on: \(aspect)"
        case (.checkIn(.keepGoing), _):
            return "continue"
        case (.checkIn(.finish), _):
            return "finish"
        case (.commit(let yes), _):
            return yes ? "Yes, commit the change." : "No, do not commit."
        case (.cancelled, _):
            return "The user cancelled. Stop and wait for them."
        default:
            return "(unexpected answer)"
        }
    }

    public var structured: JSONValue {
        switch self {
        case .answers(let a): return .object(["answers": .object(a.mapValues { .array($0.map(JSONValue.string)) })])
        case .makeItSo: return .object(["start": .bool(true)])
        case .clarifyMore(let note): return .object(["start": .bool(false), "note": .string(note)])
        case .checkIn(.nextStep(let n)): return .object(["choice": .string("next_step"), "step": .int(n)])
        case .checkIn(.focus(let s)): return .object(["choice": .string("focus"), "focus": .string(s)])
        case .checkIn(.keepGoing): return .object(["choice": .string("continue")])
        case .checkIn(.finish): return .object(["choice": .string("finish")])
        case .commit(let yes): return .object(["commit": .bool(yes)])
        case .cancelled: return .object(["cancelled": .bool(true)])
        }
    }

    /// Short line for the transcript once the gate is closed.
    public var summary: String {
        switch self {
        case .answers(let a): return a.keys.sorted().map { "\($0): \(a[$0]!.joined(separator: ", "))" }.joined(separator: "; ")
        case .makeItSo: return "Make it so"
        case .clarifyMore(let note): return "Clarify more: \(note)"
        case .checkIn(.nextStep(let n)): return "Next step \(n)"
        case .checkIn(.focus(let s)): return "Focus on: \(s)"
        case .checkIn(.keepGoing): return "Continue"
        case .checkIn(.finish): return "Finish"
        case .commit(let yes): return yes ? "Commit: yes" : "Commit: no"
        case .cancelled: return "Cancelled"
        }
    }
}

/// The MCP tool definitions and argument parsing for the gates.
public enum GateTools {
    public static let serverName = "planner"
    /// Claude Code names MCP tools mcp__<server>__<tool>.
    public static let allowedToolsPattern = "mcp__planner__*"
    public static let names = ["ask_user", "confirm_start", "check_in", "ask_commit"]

    public static let definitions: JSONValue = try! JSONValue.parse(#"""
    [
      {"name": "ask_user",
       "description": "Ask the user one or more clarifying questions at once and wait for the answers. Use this instead of asking in plain text. Give each question a short id; offer choices when the answer is one of a few options. Returns the user's answer to each question.",
       "inputSchema": {"type": "object", "required": ["questions"], "properties": {
         "questions": {"type": "array", "minItems": 1, "items": {"type": "object", "required": ["id", "text"], "properties": {
           "id": {"type": "string", "description": "Short stable id, e.g. q1 or scope"},
           "text": {"type": "string", "description": "The question"},
           "choices": {"type": "array", "items": {"type": "string"}, "description": "Options to pick from. Omit for a free-text answer."},
           "multi": {"type": "boolean", "description": "True if several choices may be picked"}}}}}}},
      {"name": "confirm_start",
       "description": "Show the clarified brief and wait for the user to say \"Make it so\" before starting unattended work. Returns \"Make it so\" to start, or the user's further clarification.",
       "inputSchema": {"type": "object", "required": ["brief"], "properties": {
         "brief": {"type": "string", "description": "The clarified brief, restated in a few lines of markdown"}}}},
      {"name": "check_in",
       "description": "Check in with the user after a round of exploration. Shows the summary, recommendations and 2-4 numbered next steps, and waits. Returns the picked next step, an aspect to focus on, \"continue\", or \"finish\".",
       "inputSchema": {"type": "object", "required": ["summary", "next_steps"], "properties": {
         "summary": {"type": "string"},
         "recommendations": {"type": "array", "items": {"type": "string"}, "description": "One line each, with its (finding N) reference"},
         "next_steps": {"type": "array", "items": {"type": "string"}, "minItems": 1}}}},
      {"name": "ask_commit",
       "description": "Ask the user whether this plan's change should be committed. Returns yes or no.",
       "inputSchema": {"type": "object", "properties": {
         "context": {"type": "string", "description": "Optional: what would be committed"}}}}
    ]
    """#)

    public enum ParseError: Error, CustomStringConvertible {
        case unknownTool(String)
        case invalid(String)
        public var description: String {
            switch self {
            case .unknownTool(let n): return "Unknown tool: \(n)"
            case .invalid(let m): return "Invalid arguments: \(m)"
            }
        }
    }

    public static func parse(name: String, arguments a: JSONValue) throws -> GateKind {
        func strings(_ v: JSONValue?) -> [String] { v?.arrayValue?.compactMap(\.stringValue) ?? [] }
        switch name {
        case "ask_user":
            guard let items = a["questions"]?.arrayValue, !items.isEmpty else { throw ParseError.invalid("questions must be a non-empty array") }
            let questions = items.enumerated().map { i, q in
                GateQuestion(id: q["id"]?.stringValue ?? "q\(i + 1)",
                             text: q["text"]?.stringValue ?? q["question"]?.stringValue ?? "",
                             choices: strings(q["choices"]),
                             multi: q["multi"]?.boolValue ?? false)
            }
            return .askUser(questions: questions)
        case "confirm_start":
            guard let brief = a["brief"]?.stringValue else { throw ParseError.invalid("brief is required") }
            return .confirmStart(brief: brief)
        case "check_in":
            let steps = strings(a["next_steps"])
            guard let summary = a["summary"]?.stringValue, !steps.isEmpty else {
                throw ParseError.invalid("summary and next_steps are required")
            }
            return .checkIn(summary: summary, recommendations: strings(a["recommendations"]), nextSteps: steps)
        case "ask_commit":
            return .askCommit(context: a["context"]?.stringValue)
        default:
            throw ParseError.unknownTool(name)
        }
    }
}

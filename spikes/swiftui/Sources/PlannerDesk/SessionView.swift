import PlannerCore
import SwiftUI

struct SessionView: View {
    let session: AgentSession
    @State private var reply = ""
    @FocusState private var replyFocused: Bool
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let request = session.openPermissionRequests.first {
                PermissionBar(request: request, session: session)
            } else {
                OpenFormPanel(session: session)
            }
            Divider()
            replyBox
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.cwd.path)
        .toolbar {
            ToolbarItem { StatusBadge(status: session.status) }
            ToolbarItem {
                Button { session.cancelTurn() } label: { Label("Stop Turn", systemImage: "stop.circle") }
                    .disabled(!session.turnInFlight)
                    .keyboardShortcut(".", modifiers: .command)
            }
            ToolbarItem {
                Toggle(isOn: $showLog) { Label("Agent Log", systemImage: "terminal") }
            }
        }
        .inspector(isPresented: $showLog) {
            ScrollView {
                Text(session.stderrLog.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .inspectorColumnWidth(min: 200, ideal: 320)
        }
        .onChange(of: session.status) { _, status in
            if status == .awaitingInput { replyFocused = true }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.transcript.filter { !$0.isShadowedTool }) { item in
                        TranscriptRow(item: item, session: session).id(item.id)
                    }
                    if session.status == .working || session.status == .starting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(session.status == .starting ? "Starting agent…" : "Working…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: session.transcript.last) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var replyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = session.pendingQuestion {
                // The agent ended its turn on a question: make that the thing
                // the eye lands on, right above where the answer goes.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "questionmark.bubble.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The agent is waiting for your answer").font(.caption.weight(.semibold))
                        Text(lastParagraph(question)).lineLimit(4)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $reply, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($replyFocused)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .disabled(!canReply)
                Button("Send", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canReply || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    private var canReply: Bool { session.status == .awaitingInput }

    private var placeholder: String {
        switch session.status {
        case .awaitingInput: return "Reply to the agent (⌘↩ to send)"
        case .awaitingPermission: return "Answer the permission request above first"
        case .awaitingAnswer: return "Answer the form above; the agent is waiting on it"
        case .failed, .exited: return "Session ended"
        default: return "The agent is working…"
        }
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.reply(text)
        reply = ""
    }

    private func lastParagraph(_ text: String) -> String {
        text.components(separatedBy: "\n\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
    }
}

/// Pinned above the reply box so a blocked agent is never scrolled out of view.
struct PermissionBar: View {
    let request: PermissionRequest
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permission needed").font(.caption.weight(.semibold))
                Text(request.title).lineLimit(2)
            }
            Spacer()
            PermissionButtons(request: request, session: session)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}

struct PermissionButtons: View {
    let request: PermissionRequest
    let session: AgentSession

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(request.options.enumerated()), id: \.element.optionId) { index, option in
                let button = Button(option.name) { session.choose(option, for: request) }
                if option.kind == "allow_once" {
                    button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else if option.isAllow {
                    button.buttonStyle(.bordered)
                } else {
                    button.buttonStyle(.bordered).keyboardShortcut(index == request.options.count - 1 ? .cancelAction : nil)
                }
            }
        }
    }
}

struct TranscriptRow: View {
    let item: TranscriptItem
    let session: AgentSession

    var body: some View {
        switch item.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        case .agent(let text):
            MarkdownView(text)
        case .thought(let text):
            DisclosureGroup("Thinking") {
                Text(text).italic().foregroundStyle(.secondary).textSelection(.enabled)
            }
            .foregroundStyle(.secondary)
        case .tool(let info):
            ToolCallRow(info: info)
        case .permission(let request, let chosen):
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label(request.title, systemImage: "hand.raised")
                    if let chosen {
                        Text("You chose: \(chosen.name)").font(.caption).foregroundStyle(.secondary)
                    } else if request.options.isEmpty {
                        Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                    } else {
                        PermissionButtons(request: request, session: session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .gate(let prompt, let answer):
            FormRecordRow(title: prompt.kind.label, detail: prompt.kind.recordDetail, answer: answer?.summary)
        case .elicitation(let request, let response):
            FormRecordRow(title: "Question", detail: request.message, answer: response?.summary)
        case .plan(let entries):
            GroupBox("Plan") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Label(entry.content, systemImage: entry.status == "completed" ? "checkmark.circle.fill"
                              : entry.status == "in_progress" ? "circle.dotted" : "circle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .notice(let text):
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}

struct ToolCallRow: View {
    let info: ToolCallInfo
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(info.title ?? info.toolCallId).font(.callout).lineLimit(1)
                Spacer()
                Text(info.status ?? "pending")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            if let detail = info.detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .onTapGesture { expanded.toggle() }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var icon: String {
        switch info.kind {
        case "read": return "doc.text"
        case "edit": return "pencil"
        case "delete": return "trash"
        case "move": return "arrow.right.doc.on.clipboard"
        case "search": return "magnifyingglass"
        case "execute": return "terminal"
        case "think": return "brain"
        case "fetch": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }

    private var statusColor: Color {
        switch info.status {
        case "completed": return .green
        case "failed": return .red
        case "in_progress": return .blue
        default: return .secondary
        }
    }
}

struct NewSessionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var draft: SessionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Agent Session").font(.title3.bold())
            Form {
                Picker("Mode", selection: $draft.mode) {
                    ForEach(SessionMode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Plan folder", selection: $draft.folder) {
                    Text("None").tag(PlanFolder?.none)
                    ForEach(state.repos) { repo in
                        Section(repo.name) {
                            ForEach(repo.folders) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                }
                LabeledContent("Agent", value: state.agentCommand)
                    .font(.system(.caption, design: .monospaced))
            }
            .onChange(of: draft.mode) { draft.prompt = AppState.prompt(for: draft.mode, folder: draft.folder) }
            .onChange(of: draft.folder) { draft.prompt = AppState.prompt(for: draft.mode, folder: draft.folder) }
            Text("Prompt").font(.headline)
            TextEditor(text: $draft.prompt)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") {
                    state.start(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

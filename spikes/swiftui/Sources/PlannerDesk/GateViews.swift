import PlannerCore
import SwiftUI

// Native forms for planner's gates (MCP tool calls that block until the user
// answers) and for ACP elicitation/create (Claude's AskUserQuestion). The open
// one is pinned above the reply box, so it can't scroll away; the transcript
// keeps a one-line record of what was asked and answered.

/// The pinned panel: the first open gate or elicitation, if any.
struct OpenFormPanel: View {
    let session: AgentSession

    var body: some View {
        if let prompt = session.openGatePrompts.first {
            panel(title: prompt.kind.label, icon: "questionmark.bubble.fill") {
                GateForm(prompt: prompt, session: session).id(prompt.id)
            }
        } else if let request = session.openElicitationRequests.first {
            panel(title: "The agent asks", icon: "list.bullet.rectangle.fill") {
                ElicitationForm(request: request, session: session).id(request.rpcId)
            }
        }
    }

    private func panel(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.blue)
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.blue.opacity(0.08))
    }
}

struct GateForm: View {
    let prompt: GatePrompt
    let session: AgentSession

    var body: some View {
        switch prompt.kind {
        case .askUser(let questions):
            AskUserForm(questions: questions) { session.answer(prompt, with: .answers($0)) }
        case .confirmStart(let brief):
            ConfirmStartForm(brief: brief) { session.answer(prompt, with: $0) }
        case .checkIn(let summary, let recommendations, let nextSteps):
            CheckInForm(summary: summary, recommendations: recommendations, nextSteps: nextSteps) {
                session.answer(prompt, with: .checkIn($0))
            }
        case .askCommit(let context):
            VStack(alignment: .leading, spacing: 8) {
                Text("Should this plan's change be committed once it is made and verified?")
                if let context { MarkdownView(context).foregroundStyle(.secondary) }
                HStack {
                    Button("No, leave it uncommitted") { session.answer(prompt, with: .commit(false)) }
                        .keyboardShortcut(.cancelAction)
                    Button("Yes, commit") { session.answer(prompt, with: .commit(true)) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// ask_user: every question at once, each with a picker or a text field.
struct AskUserForm: View {
    let questions: [GateQuestion]
    let submit: ([String: [String]]) -> Void
    @State private var picks: [String: Set<String>] = [:]
    @State private var texts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.element.id) { index, q in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(q.text)").font(.body.weight(.medium))
                    if q.choices.isEmpty {
                        TextField("Your answer", text: binding(texts: q.id), axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    } else if q.multi {
                        ForEach(q.choices, id: \.self) { choice in
                            Toggle(choice, isOn: binding(pick: choice, in: q.id, multi: true))
                                .toggleStyle(.checkbox)
                        }
                        TextField("Other (optional)", text: binding(texts: q.id)).textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: binding(single: q.id)) {
                            ForEach(q.choices, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.radioGroup).labelsHidden()
                        TextField("Or type your own answer", text: binding(texts: q.id)).textFieldStyle(.roundedBorder)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Send answers") { submit(collected) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var collected: [String: [String]] {
        var out: [String: [String]] = [:]
        for q in questions {
            var values = q.choices.filter { picks[q.id, default: []].contains($0) }
            let text = texts[q.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // A typed answer replaces a single pick and adds to a multi pick.
                if q.multi || q.choices.isEmpty { values.append(text) } else { values = [text] }
            }
            out[q.id] = values
        }
        return out
    }

    private func binding(texts id: String) -> Binding<String> {
        Binding(get: { texts[id, default: ""] }, set: { texts[id] = $0 })
    }

    private func binding(single id: String) -> Binding<String> {
        Binding(get: { picks[id]?.first ?? "" }, set: { picks[id] = [$0] })
    }

    private func binding(pick choice: String, in id: String, multi: Bool) -> Binding<Bool> {
        Binding(get: { picks[id, default: []].contains(choice) },
                set: { on in
                    if on { picks[id, default: []].insert(choice) } else { picks[id, default: []].remove(choice) }
                })
    }
}

/// explore_deep's gate: restated brief, a primary "Make it so", or clarify.
struct ConfirmStartForm: View {
    let brief: String
    let submit: (GateAnswer) -> Void
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox { MarkdownView(brief).frame(maxWidth: .infinity, alignment: .leading) }
            Text("Starting runs the rest unattended.").font(.caption).foregroundStyle(.secondary)
            TextField("Anything to clarify first?", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...5)
            HStack {
                Spacer()
                Button("Clarify more") { submit(.clarifyMore(note)) }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Make it so") { submit(.makeItSo) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// _explore_check_in: summary, recommendations, one button per next step.
struct CheckInForm: View {
    let summary: String
    let recommendations: [String]
    let nextSteps: [String]
    let submit: (CheckInChoice) -> Void
    @State private var focus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkdownView(summary)
            if !recommendations.isEmpty {
                Text("Recommendations").font(.subheadline.weight(.semibold))
                ForEach(recommendations, id: \.self) { Label($0, systemImage: "lightbulb").font(.callout) }
            }
            Text("Next steps").font(.subheadline.weight(.semibold))
            ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                Button { submit(.nextStep(index + 1)) } label: {
                    HStack {
                        Text("\(index + 1)").font(.callout.monospacedDigit().weight(.bold)).frame(width: 18)
                        Text(step).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(KeyEquivalent(Character("\(min(index + 1, 9))")), modifiers: .command)
            }
            HStack {
                TextField("Or name an aspect to focus on", text: $focus).textFieldStyle(.roundedBorder)
                    .onSubmit { if !focus.isEmpty { submit(.focus(focus)) } }
                Button("Focus") { submit(.focus(focus)) }.disabled(focus.isEmpty)
            }
            HStack {
                Spacer()
                Button("Continue") { submit(.keepGoing) }
                Button("Finish") { submit(.finish) }.buttonStyle(.borderedProminent)
            }
        }
    }
}

/// elicitation/create in form mode, rendered from its JSON schema.
struct ElicitationForm: View {
    let request: ElicitationRequest
    let session: AgentSession
    @State private var values: [String: JSONValue] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !request.message.isEmpty { Text(request.message).font(.body.weight(.medium)) }
            ForEach(request.fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    if let title = field.title { Text(title).font(.subheadline.weight(.semibold)) }
                    if let d = field.description { Text(d).font(.caption).foregroundStyle(.secondary) }
                    control(for: field)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { session.respond(to: request, with: .cancel) }.keyboardShortcut(.cancelAction)
                Button("Decline") { session.respond(to: request, with: .decline) }
                Button("Submit") { session.respond(to: request, with: .accept(values)) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(request.fields.contains { $0.required && values[$0.key] == nil })
            }
        }
    }

    @ViewBuilder private func control(for field: ElicitationField) -> some View {
        switch field.kind {
        case .single(let options):
            Picker("", selection: Binding(get: { values[field.key]?.stringValue ?? "" },
                                          set: { values[field.key] = .string($0) })) {
                ForEach(options) { o in
                    VStack(alignment: .leading) {
                        Text(o.title)
                        if let d = o.description { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }.tag(o.value)
                }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        case .multi(let options):
            ForEach(options) { o in
                Toggle(o.title, isOn: Binding(
                    get: { values[field.key]?.arrayValue?.contains(.string(o.value)) ?? false },
                    set: { on in
                        var list = values[field.key]?.arrayValue ?? []
                        if on { list.append(.string(o.value)) } else { list.removeAll { $0 == .string(o.value) } }
                        values[field.key] = .array(list)
                    }))
                .toggleStyle(.checkbox)
            }
        case .bool:
            Toggle("", isOn: Binding(get: { values[field.key]?.boolValue ?? false },
                                     set: { values[field.key] = .bool($0) })).labelsHidden()
        case .text, .number:
            TextField("", text: Binding(
                get: { values[field.key]?.stringValue ?? "" },
                set: { text in
                    if text.isEmpty { values[field.key] = nil }
                    else if field.kind == .number, let d = Double(text) { values[field.key] = .double(d) }
                    else { values[field.key] = .string(text) }
                }))
            .textFieldStyle(.roundedBorder)
        }
    }
}

/// The transcript's record of a gate or elicitation.
struct FormRecordRow: View {
    let title: String
    let detail: String?
    let answer: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: answer == nil ? "questionmark.bubble" : "checkmark.bubble")
                if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(4) }
                Text(answer.map { "You answered: \($0)" } ?? "Waiting for your answer below")
                    .font(.caption).foregroundStyle(answer == nil ? .blue : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension GateKind {
    var recordDetail: String {
        switch self {
        case .askUser(let qs): return qs.map(\.text).joined(separator: "\n")
        case .confirmStart(let brief): return brief
        case .checkIn(let summary, _, _): return summary
        case .askCommit(let context): return context ?? "Commit the plan's change?"
        }
    }
}

extension ElicitationResponse {
    var summary: String {
        switch self {
        case .accept(let content):
            return content.keys.sorted().compactMap { key in
                let v = content[key]!
                let text = v.stringValue ?? v.arrayValue?.compactMap(\.stringValue).joined(separator: ", ") ?? v.jsonString
                return text.isEmpty ? nil : text
            }.joined(separator: "; ")
        case .decline: return "Declined"
        case .cancel: return "Cancelled"
        }
    }
}

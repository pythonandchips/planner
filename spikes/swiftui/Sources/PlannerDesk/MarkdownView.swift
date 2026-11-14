import PlannerCore
import SwiftUI

/// Renders markdown with block layout from MarkdownBlocks and inline styling
/// from AttributedString(markdown:). No external package.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    init(_ source: String) {
        blocks = MarkdownBlocks.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary)
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.tertiary).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(.callout, design: .monospaced)).padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .table(let rows):
            // Tables as monospaced text: SwiftUI's Grid could lay them out,
            // but column sizing with wrapped text needs more work than a spike.
            Text(rows.joined(separator: "\n")).font(.system(.callout, design: .monospaced))
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline
        }
    }
}

struct FileDetailView: View {
    let file: PlanFile
    let folder: PlanFolder?
    @Environment(AppState.self) private var state

    @State private var text = ""
    @State private var saved = ""
    @State private var editing = false
    @State private var error: String?

    private var dirty: Bool { text != saved }

    var body: some View {
        Group {
            if editing {
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                ScrollView {
                    MarkdownView(text)
                        .padding(24)
                        .frame(maxWidth: 820, alignment: .leading)
                }
            }
        }
        .navigationTitle(file.name + (dirty ? " — Edited" : ""))
        .navigationSubtitle(folder?.name ?? "")
        .toolbar {
            if file.isEditable {
                ToolbarItem {
                    Picker("Mode", selection: $editing) {
                        Text("Preview").tag(false)
                        Text("Edit").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Button("Save", action: save)
                        .keyboardShortcut("s")
                        .disabled(!dirty)
                }
                ToolbarItem {
                    Menu {
                        ForEach(SessionMode.allCases) { mode in
                            Button(mode.rawValue.capitalized) { state.beginDraft(mode: mode, folder: folder) }
                        }
                    } label: {
                        Label("Start Session", systemImage: "play")
                    }
                }
            }
        }
        .alert("Could not save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task(id: file.url) { load() }
    }

    private func load() {
        text = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
        saved = text
    }

    private func save() {
        do {
            try text.write(to: file.url, atomically: true, encoding: .utf8)
            saved = text
        } catch {
            self.error = error.localizedDescription
        }
    }
}

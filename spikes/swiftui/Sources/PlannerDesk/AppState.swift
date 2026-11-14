import AppKit
import Observation
import PlannerCore

enum SidebarItem: Hashable {
    case file(URL)
    case session(UUID)
}

enum SessionMode: String, CaseIterable, Identifiable {
    case explore, deep, plan, run, chat
    var id: String { rawValue }
}

/// What the New Session sheet edits before a session starts.
struct SessionDraft: Identifiable {
    let id = UUID()
    var mode: SessionMode
    var folder: PlanFolder?
    var prompt: String
}

@MainActor
@Observable
final class AppState {
    var parentFolder: URL?
    var repos: [PlanRepo] = []
    var sessions: [AgentSession] = []
    var selection: SidebarItem?
    var expandedFolders: Set<URL> = []
    var draft: SessionDraft?

    static let agentCommandKey = "agentCommand"

    var agentCommand: String {
        UserDefaults.standard.string(forKey: Self.agentCommandKey) ?? AgentLaunch.defaultCommand
    }

    var allFolders: [PlanFolder] { repos.flatMap(\.folders) }

    var sessionsNeedingUser: Int { sessions.filter { $0.status.needsUser }.count }

    init(arguments: [String] = CommandLine.arguments) {
        // First non-flag argument is the parent folder; otherwise reopen the last one.
        if let path = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            open(URL(fileURLWithPath: path).standardizedFileURL)
        } else if let last = UserDefaults.standard.string(forKey: "lastParentFolder") {
            open(URL(fileURLWithPath: last))
        }
    }

    func open(_ url: URL) {
        parentFolder = url
        UserDefaults.standard.set(url.path, forKey: "lastParentFolder")
        refresh()
        // Expand the newest plan folder in each repo.
        expandedFolders.formUnion(repos.compactMap { $0.folders.first?.url })
    }

    func refresh() {
        guard let parentFolder else { return }
        repos = PlanDiscovery.discover(parent: parentFolder)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        panel.message = "Choose the folder that holds your repos"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func folder(containing file: URL) -> PlanFolder? {
        allFolders.first { $0.url == file.deletingLastPathComponent() }
    }

    func session(_ id: UUID) -> AgentSession? { sessions.first { $0.id == id } }

    // MARK: Sessions

    func beginDraft(mode: SessionMode = .explore, folder: PlanFolder? = nil) {
        let folder = folder ?? selectedFolder ?? allFolders.first
        draft = SessionDraft(mode: mode, folder: folder, prompt: Self.prompt(for: mode, folder: folder))
    }

    var selectedFolder: PlanFolder? {
        if case .file(let url)? = selection { return folder(containing: url) }
        return nil
    }

    func start(_ draft: SessionDraft) {
        let cwd = draft.folder?.repoURL ?? parentFolder ?? FileManager.default.homeDirectoryForCurrentUser
        let title = "\(draft.mode.rawValue) · \(draft.folder?.name ?? cwd.lastPathComponent)"
        let session = AgentSession(title: title, cwd: cwd, launch: .shell(agentCommand))
        sessions.append(session)
        selection = .session(session.id)
        session.start(prompt: draft.prompt)
    }

    func close(_ session: AgentSession) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if selection == .session(session.id) { selection = nil }
    }

    /// Writes an empty next ITERATION file and selects it for editing.
    func newIteration(in folder: PlanFolder) {
        let url = folder.nextIterationURL
        let template = "# \(url.deletingPathExtension().lastPathComponent)\n\n## Goal\n\n## Questions\n\n"
        try? template.write(to: url, atomically: true, encoding: .utf8)
        refresh()
        expandedFolders.insert(folder.url)
        selection = .file(url)
    }

    /// spikes/swiftui/prompts: gate-aware variants of planner's explore,
    /// deep explore and plan prompts. Found from the source path, which is
    /// fine for a spike run from its checkout.
    static let promptsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("prompts")

    /// Renders a prompt variant ({{placeholders}}), or falls back to the
    /// short stand-ins below.
    static func prompt(for mode: SessionMode, folder: PlanFolder?) -> String {
        guard let folder else { return "" }
        let rel = "docs/plans/\(folder.name)"
        let iteration = folder.files.last { $0.kind == .iteration }?.name ?? "ITERATION-001.md"
        let n = iteration.replacingOccurrences(of: "ITERATION-", with: "").replacingOccurrences(of: ".md", with: "")
        let file = ["explore": "explore.md", "deep": "explore_deep.md", "plan": "plan.md"][mode.rawValue]
        if let file, var text = try? String(contentsOf: promptsDir.appendingPathComponent(file), encoding: .utf8) {
            let values = ["folder": rel, "iteration_file": "\(rel)/\(iteration)",
                          "findings_file": "\(rel)/FINDINGS-\(n).md", "plan_file": "\(rel)/PLAN-\(n).md",
                          "toc_file": "\(rel)/TABLE-OF-CONTENT.md"]
            for (key, value) in values { text = text.replacingOccurrences(of: "{{\(key)}}", with: value) }
            return text
        }
        switch mode {
        case .explore, .deep:
            return "Read \(rel)/\(iteration). Explore the codebase to answer its open questions and write what you find to \(rel)/FINDINGS-\(n).md. If anything in the iteration is unclear, stop and ask me."
        case .plan:
            return "Read \(rel)/\(iteration) and \(rel)/FINDINGS-\(n).md, then write an implementation plan to \(rel)/PLAN-\(n).md. Ask me before making decisions the iteration leaves open."
        case .run:
            return "Implement \(rel)/PLAN-\(n).md step by step. Run the tests as you go."
        case .chat:
            return ""
        }
    }
}

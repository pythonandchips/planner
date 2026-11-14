import PlannerCore
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } detail: {
            switch state.selection {
            case .file(let url)?:
                FileDetailView(file: PlanFile(url: url), folder: state.folder(containing: url))
                    .id(url)
            case .session(let id)?:
                if let session = state.session(id) {
                    SessionView(session: session).id(id)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { state.showOpenPanel() } label: { Label("Open Folder", systemImage: "folder") }
                Button { state.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { state.beginDraft() } label: { Label("New Session", systemImage: "plus.bubble") }
                    .disabled(state.parentFolder == nil)
            }
        }
        .sheet(item: $state.draft) { draft in
            NewSessionSheet(draft: draft)
        }
    }

    @ViewBuilder private var placeholder: some View {
        if state.parentFolder == nil {
            ContentUnavailableView {
                Label("No folder open", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Open the folder that holds your repos to see their plans.")
            } actions: {
                Button("Open Folder…") { state.showOpenPanel() }.buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("Select a plan file or session", systemImage: "sidebar.left")
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            if !state.sessions.isEmpty {
                Section("Sessions") {
                    ForEach(state.sessions) { session in
                        SessionRow(session: session)
                            .tag(SidebarItem.session(session.id))
                            .contextMenu {
                                Button("Close Session") { state.close(session) }
                            }
                    }
                }
            }
            ForEach(state.repos) { repo in
                Section(repo.name) {
                    ForEach(repo.folders) { folder in
                        DisclosureGroup(isExpanded: expanded(folder)) {
                            ForEach(folder.files) { file in
                                Label(file.name, systemImage: icon(for: file.kind))
                                    .tag(SidebarItem.file(file.url))
                            }
                        } label: {
                            Label(folder.name, systemImage: "folder")
                                .lineLimit(1)
                                .help(folder.url.path)
                                .contextMenu { folderMenu(folder) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.parentFolder != nil && state.repos.isEmpty {
                ContentUnavailableView("No docs/plans folders", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    @ViewBuilder private func folderMenu(_ folder: PlanFolder) -> some View {
        Button("New Iteration File") { state.newIteration(in: folder) }
        Divider()
        ForEach(SessionMode.allCases) { mode in
            Button("\(mode.rawValue.capitalized)…") { state.beginDraft(mode: mode, folder: folder) }
        }
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
    }

    private func expanded(_ folder: PlanFolder) -> Binding<Bool> {
        Binding(
            get: { state.expandedFolders.contains(folder.url) },
            set: { open in
                if open { state.expandedFolders.insert(folder.url) } else { state.expandedFolders.remove(folder.url) }
            }
        )
    }

    private func icon(for kind: PlanFile.Kind) -> String {
        switch kind {
        case .iteration: return "pencil.and.list.clipboard"
        case .findings: return "magnifyingglass"
        case .plan: return "list.number"
        case .review: return "checkmark.seal"
        case .other: return "doc.text"
        }
    }
}

struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).lineLimit(1)
                Text(session.cwd.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            StatusBadge(status: session.status)
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .working || status == .starting {
                ProgressView().controlSize(.mini)
            }
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .starting, .working: return .blue
        case .awaitingPermission: return .orange
        case .awaitingAnswer: return .purple
        case .awaitingInput: return .green
        case .failed: return .red
        case .exited: return .secondary
        }
    }
}

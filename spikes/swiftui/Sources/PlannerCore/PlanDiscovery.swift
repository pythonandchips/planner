import Foundation

/// A file inside a plan folder (ITERATION-001.md, FINDINGS-001.md, ...).
public struct PlanFile: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case iteration = "ITERATION", findings = "FINDINGS", plan = "PLAN", review = "REVIEW", other
    }

    public let url: URL
    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL) { self.url = url }

    public var kind: Kind {
        let prefix = name.split(separator: "-").first.map(String.init) ?? ""
        return Kind(rawValue: prefix) ?? .other
    }

    /// The NNN in ITERATION-NNN.md, if there is one.
    public var number: Int? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let last = stem.split(separator: "-").last else { return nil }
        return Int(last)
    }

    public var isEditable: Bool { kind == .iteration }
}

/// One docs/plans/<timestamp>-<name>/ folder.
public struct PlanFolder: Hashable, Identifiable, Sendable {
    public let url: URL
    public let repoURL: URL
    public let files: [PlanFile]
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var repoName: String { repoURL.lastPathComponent }

    /// The next free ITERATION-NNN.md path in this folder.
    public var nextIterationURL: URL {
        let next = (files.filter { $0.kind == .iteration }.compactMap(\.number).max() ?? 0) + 1
        return url.appendingPathComponent(String(format: "ITERATION-%03d.md", next))
    }
}

/// A repo (the parent itself or an immediate child) that has plan folders.
public struct PlanRepo: Hashable, Identifiable, Sendable {
    public let url: URL
    public let folders: [PlanFolder]
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
}

public enum PlanDiscovery {
    /// Finds `docs/plans/*/` under `parent` and under each immediate child of
    /// `parent`. Repos without plan folders are left out. Plan folders are
    /// newest first (their names start with a timestamp).
    public static func discover(parent: URL, fileManager: FileManager = .default) -> [PlanRepo] {
        var candidates = [parent]
        if let children = try? fileManager.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) {
            candidates += children.filter(isDirectory).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return candidates.compactMap { repo in
            let folders = planFolders(in: repo, fileManager: fileManager)
            return folders.isEmpty ? nil : PlanRepo(url: repo, folders: folders)
        }
    }

    static func planFolders(in repo: URL, fileManager: FileManager) -> [PlanFolder] {
        let plansDir = repo.appendingPathComponent("docs/plans", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: plansDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter(isDirectory)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { PlanFolder(url: $0, repoURL: repo, files: files(in: $0, fileManager: fileManager)) }
    }

    static func files(in folder: URL, fileManager: FileManager) -> [PlanFile] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let order = Dictionary(uniqueKeysWithValues: PlanFile.Kind.allCases.enumerated().map { ($1, $0) })
        return entries.filter { !isDirectory($0) && $0.pathExtension.lowercased() == "md" }
            .map(PlanFile.init(url:))
            .sorted { a, b in
                // Group by iteration number, then ITERATION, FINDINGS, PLAN, REVIEW.
                let (na, nb) = (a.number ?? Int.max, b.number ?? Int.max)
                if na != nb { return na < nb }
                if a.kind != b.kind { return order[a.kind]! < order[b.kind]! }
                return a.name < b.name
            }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

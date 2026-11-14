import Foundation
import Testing
@testable import PlannerCore

/// A scratch directory. Honours PLANNER_TEST_TMP because NSTemporaryDirectory
/// is not writable in some sandboxes.
func makeScratchDir(_ name: String) throws -> URL {
    let base = ProcessInfo.processInfo.environment["PLANNER_TEST_TMP"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func touch(_ root: URL, _ path: String, _ text: String = "# x\n") throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: false, encoding: .utf8)
}

@Suite struct PlanDiscoveryTests {
    @Test func findsPlanFoldersInParentAndChildRepos() throws {
        let root = try makeScratchDir("discovery")
        defer { try? FileManager.default.removeItem(at: root) }

        try touch(root, "docs/plans/202601010000-root-plan/ITERATION-001.md")
        try touch(root, "repo-a/docs/plans/202610271216-older/ITERATION-001.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/REVIEW-001.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/PLAN-001.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/ITERATION-002.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/FINDINGS-001.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/ITERATION-001.md")
        try touch(root, "repo-a/docs/plans/202610301244-newer/notes.txt")
        try touch(root, "repo-b/README.md") // no plans: left out
        try touch(root, "repo-c/nested/deeper/docs/plans/x/ITERATION-001.md") // too deep: left out

        let repos = PlanDiscovery.discover(parent: root)

        #expect(repos.map(\.name) == [root.lastPathComponent, "repo-a"])
        let repoA = try #require(repos.last)
        #expect(repoA.folders.map(\.name) == ["202610301244-newer", "202610271216-older"])
        #expect(repoA.folders[0].files.map(\.name) == [
            "ITERATION-001.md", "FINDINGS-001.md", "PLAN-001.md", "REVIEW-001.md", "ITERATION-002.md",
        ])
        #expect(repoA.folders[0].files.first?.isEditable == true)
        #expect(repoA.folders[0].files[1].isEditable == false)
        #expect(repoA.folders[0].nextIterationURL.lastPathComponent == "ITERATION-003.md")
    }

    @Test func emptyParentHasNoRepos() throws {
        let root = try makeScratchDir("empty")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PlanDiscovery.discover(parent: root).isEmpty)
    }
}

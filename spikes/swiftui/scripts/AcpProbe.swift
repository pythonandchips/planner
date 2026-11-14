// Headless check of PlannerCore's ACP client against a real agent.
// Build and run with: scripts/swiftc-build.sh probe ["agent command"] [prompt]
// Without a prompt it only does initialize + session/new (no model call).
import Foundation
import PlannerCore

@main struct AcpProbe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? AgentLaunch.defaultCommand
        let prompt = args.count > 1 ? args[1] : nil
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let client = ACPClient(launch: .shell(command), cwd: cwd)
        let started = Date()
        do {
            try await client.start()
            let events = Task {
                for await event in client.events {
                    switch event {
                    case .stderr(let line): print("stderr:", line)
                    case .sessionUpdate(_, let update): print("update:", update)
                    case .permissionRequest(let request):
                        print("permission:", request.title, request.options.map(\.name))
                        try? await client.respond(to: request, optionId: nil)
                    case .exited(let code): print("exited:", code)
                    }
                }
            }
            let initResult = try await client.initialize()
            print("initialize ok after \(Int(Date().timeIntervalSince(started) * 1000)) ms: protocolVersion=\(initResult.protocolVersion)")
            print("agentCapabilities:", initResult.agentCapabilities.map { String(describing: $0) } ?? "nil")
            print("authMethods:", initResult.authMethods.map { String(describing: $0) } ?? "nil")
            let sessionId = try await client.newSession(cwd: cwd)
            print("session/new ok: \(sessionId)")
            if let prompt {
                let stop = try await client.prompt(sessionId: sessionId, text: prompt)
                print("stopReason:", stop)
            }
            await client.stop()
            try? await Task.sleep(nanoseconds: 300_000_000)
            events.cancel()
        } catch {
            print("probe failed:", error)
            await client.stop()
            exit(1)
        }
    }
}

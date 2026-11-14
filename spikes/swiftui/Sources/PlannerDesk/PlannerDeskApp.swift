import AppKit
import PlannerCore
import SwiftUI

@main
struct PlannerDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("Planner") {
            ContentView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 560)
                .onChange(of: state.sessionsNeedingUser) { _, count in
                    NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { state.beginDraft() }
                    .keyboardShortcut("n")
                Button("Open Folder…") { state.showOpenPanel() }
                    .keyboardShortcut("o")
                Button("Refresh Plans") { state.refresh() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable is not an .app bundle; without this it starts
        // as a background process with no Dock icon and no key window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @AppStorage(AppState.agentCommandKey) private var agentCommand = AgentLaunch.defaultCommand

    var body: some View {
        Form {
            Section {
                TextField("Agent command", text: $agentCommand, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                Text("Any ACP agent works. It runs through your login shell, so PATH from your shell profile applies. New sessions use the new command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to Claude Code adapter") { agentCommand = AgentLaunch.defaultCommand }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}

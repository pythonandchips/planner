# PlannerDesk: SwiftUI spike

A throwaway SwiftUI macOS app that tests SwiftUI as the GUI for planner. It
opens a parent folder of repos, lists every `docs/plans/*/` folder, renders
and edits ITERATION files, and runs several agent sessions side by side over
the Agent Client Protocol (ACP).

No external packages. Only Foundation, Observation, SwiftUI and AppKit.

## Run it

```sh
cd spikes/swiftui
swift run PlannerDesk ~/dev            # or with no argument, then ⌘O
swift test                             # tests for plan discovery, markdown, ACP client
```

If SwiftPM can't write to the per-user temp dir (for example in the Claude
Code sandbox, where it fails with "You don't have permission to save the file
output-file-map.json"), use the swiftc script instead. It builds the same
sources without SwiftPM:

```sh
scripts/swiftc-build.sh test           # builds and runs the swift-testing suite
scripts/swiftc-build.sh app            # .build/swiftc/PlannerDesk
scripts/swiftc-build.sh release        # .build/swiftc/PlannerDesk-release
scripts/swiftc-build.sh probe "<agent command>" ["prompt"]   # headless ACP check
```

The agent command is set in Settings (⌘,). It defaults to
`npx -y @agentclientprotocol/claude-agent-acp`, Zed's Claude Code adapter.
That package was renamed from `@zed-industries/claude-code-acp`, and npm had
version 0.107.0 when this was written. The command runs through `$SHELL -lc`,
so a Finder-launched app still gets the PATH from your shell profile (npx
from mise, nvm or Homebrew). Any other ACP agent can be swapped in the same
way. To try the UI with no network, point it at the mock agent:

```
python3 /path/to/spikes/swiftui/mock-agent/mock_acp_agent.py
```

## Layout

| Path | What |
|---|---|
| `Sources/PlannerCore/PlanDiscovery.swift` | Finds `docs/plans/*/` in the parent and in each immediate child. Plan folders are listed newest first. Files are sorted by iteration number, then ITERATION, FINDINGS, PLAN, REVIEW. |
| `Sources/PlannerCore/ACPClient.swift` | An actor that runs JSON-RPC 2.0 over a child process's stdio: `Process`, a `readabilityHandler` line splitter, `CheckedContinuation` for each request id, and an `AsyncStream<ACPEvent>` for notifications and agent→client requests. |
| `Sources/PlannerCore/ACPTypes.swift` | Hand-rolled Codable for the ACP subset used here: initialize, session/new, session/prompt, session/cancel, session/update, and session/request_permission. |
| `Sources/PlannerCore/AgentSession.swift` | A `@MainActor @Observable` model for one session. It turns events into a transcript, merges streamed chunks into one row, and tracks status: Starting, Working, Needs permission, Awaiting input, Failed, Exited. |
| `Sources/PlannerCore/MarkdownBlocks.swift` | A small block-level markdown splitter: headings, lists, code fences, quotes, tables, rules. |
| `Sources/PlannerDesk/*` | The SwiftUI app: NavigationSplitView, sidebar, file preview and editor, session view, new-session sheet, settings. |
| `mock-agent/mock_acp_agent.py` | A fake ACP agent. It streams chunks, a thought, a plan, and a tool call, then requests permission and ends the turn with a question. |
| `scripts/AcpProbe.swift` | A headless client used to check the real adapter. |

## What works (verified)

- **Tests, 10 passing in 4 suites** (`scripts/swiftc-build.sh test`). They cover:
  - plan discovery against a temp tree: the parent repo, child repos, a repo with no plans, and a plan folder too deep to count;
  - markdown block splitting;
  - the raw ACP client against the mock agent, checking the streamed updates and the permission options;
  - a full session: Needs permission → allow → Awaiting input, with the question detected, chunks merged into rows, and the tool marked completed; then a reply, a second turn, and Awaiting input again;
  - rejecting a permission, which marks the tool failed;
  - two sessions running at once and answered in the opposite order;
  - an agent that exits during startup, which marks the session failed with its stderr;
  - writing to an agent that has died, which throws an error instead of raising SIGPIPE.
- **Real adapter, headless**: `@agentclientprotocol/claude-agent-acp` 0.107.0 through `scripts/AcpProbe.swift`. initialize took about 3.7–4.8 s with a cold npx. session/new worked. The prompt "Reply with the single word: pong" streamed `agent_message_chunk("pong")` and returned `stopReason: end_turn`. The adapter also sends `available_commands_update`, `session_info_update` and `usage_update`, which the spike ignores. They would be useful for a token and cost display.
- **The app compiles in Swift 6 language mode with strict concurrency, with no warnings.** The binary starts and stays up. **The window has not been seen.** The sandbox this was built in blocks the WindowServer and Launch Services, so every claim about the UI below comes from the code, not from looking at the app.

## How the app handles agent questions and permissions

- **Permission** (`session/request_permission`):
  - The session's badge turns orange ("Needs permission"), and the Dock icon shows a count of sessions waiting on you.
  - The request appears in the transcript as a card with one button per option, and again in a bar pinned above the reply box, so it can't scroll out of view.
  - "Allow once" is the default button (↩) and the last reject option is the cancel button (Esc).
  - After you choose, the card is replaced by "You chose: X".
  - "Stop turn" (⌘.) answers any open requests with `cancelled`, as the spec requires.
- **Questions**: ACP has no message type for a question. Claude asks in plain text and ends its turn. When the turn ends, the session goes to "Awaiting input" (green badge) and the reply box takes focus. If the agent's last message contains a `?`, its last paragraph is shown in a green callout, "The agent is waiting for your answer", right above the reply box. ⌘↩ sends the reply as the next `session/prompt`.

## What did not work or was left out

- **SwiftPM in the sandbox.** `swift build` failed on Foundation atomic writes. The sandbox denies the per-user temp dir, and `FileManager.url(for: .itemReplacementDirectory, ...)` fails, so `scripts/swiftc-build.sh` exists as a workaround. **`swift build` and `swift test` have not been run under SwiftPM.** The same sources and flags build with swiftc.
- **swift-testing with Command Line Tools only.** The installed CLT ships `_Testing_Foundation.framework` without its `Modules` directory, so `import Testing` together with `import Foundation` fails. `-Xfrontend -disable-cross-import-overlays` fixes it, and it is set in Package.swift. The macro plugin path also has to be passed to swiftc by hand.
- **`FileHandle.bytes.lines` on a pipe stalled.** The first raw-client test hung with no lines delivered. Switching to `readabilityHandler` plus a hand-written line buffer fixed it. I did not dig into the root cause. For a real app, assume pipe reading is something you own and test.
- **Running through `exec` in the shell** broke commands that start with environment assignments, such as `FOO=1 npx ...`. The command is now passed to `-lc` as is.
- **Left out:**
  - an fs/terminal client: we advertise `fs: false, terminal: false`, so the agent does its own file IO;
  - session/load and resume;
  - authentication methods;
  - images;
  - modes and model picking;
  - watching the folder (there is a Refresh button, ⌘R);
  - the real planner prompts: the explore/plan/run prompts are simple stand-ins for `lib/planner/prompts/*.erb`;
  - killing agents on quit: an agent exits when its stdin closes; `Process.terminate` is only called on close.
- The real adapter printed `EMFILE: too many open files, watch` while watching `~/.claude/settings.json`. That is probably the sandbox, but watch for it with many sessions at once.

## Numbers

Measured on an Apple Silicon Mac with Swift 6.2.4 (Command Line Tools), using `scripts/swiftc-build.sh`, so SwiftPM's numbers will be a bit different.

| | |
|---|---|
| Clean debug build of core + app (module cache cold) | ~20–24 s |
| Debug rebuild of the app (core and module cache warm) | ~8 s |
| Clean core + tests, build and run | ~28 s (tests take 0.4 s) |
| Clean release build (`-O -wmo`) | ~47 s |
| Release binary, stripped | **667 KB**. It links only system frameworks; SwiftUI and the Swift runtime are part of the OS. |
| Code | ~1,750 lines of Swift in Sources (about 925 in PlannerCore, 840 in the UI), ~250 lines of tests, 150 lines of Python for the mock |

## UX assessment of SwiftUI for this app

**Native feel: the strongest of the options, at no cost.**
- NavigationSplitView gives a sidebar with real source-list styling, collapsible columns and the system toolbar.
- `.inspector` gives the agent-log pane. `ContentUnavailableView` covers empty states.
- Context menus, menu-bar commands with shortcuts, Settings (⌘,), sheets, segmented pickers, focus handling and the Dock badge all take a line or two each.
- Light and dark mode, accent colour, VoiceOver labels and keyboard navigation in the sidebar all come for free.
- The other two candidates draw their own controls. Here everything is AppKit underneath.

**Text editing: adequate for ITERATION files, weak for anything more.**
- `TextEditor` is a plain NSTextView. Undo, spell check and services all work. System find is available through `.findNavigator`, which is not wired up yet.
- It has no line numbers, no markdown syntax highlighting and no control over the caret or selection. Cursor and selection APIs only arrived in macOS 15 (`TextSelection`), and they are limited.
- A good editor means wrapping NSTextView with `NSViewRepresentable`, about 100–200 lines, or adopting a package such as STTextView or CodeEditSourceEditor. That is the first AppKit fallback I'd expect to need.

**Markdown: not covered by the platform.**
- `AttributedString(markdown:)` only gives inline styling inside `Text`. Block structure (headings, lists, code blocks, tables) is ignored by `Text`, so I wrote a block splitter (110 lines) that maps each block to a view.
- That is fine for plan files. Tables come out as monospaced text, and nested lists and HTML are not handled.
- For full GitHub Flavored Markdown, use swift-markdown-ui (I believe it is now in maintenance, with "Textual" by the same author as its successor) or apple/swift-markdown with a custom renderer. Each adds a dependency.
- Text selection only works within one block. You can't drag-select across paragraphs, because each block is its own `Text`. Readers will notice this. Fixing it means rendering into one NSTextView (an NSAttributedString built from the markdown), which is the AppKit fallback again.

**Long transcripts: the main risk.**
- The transcript is a `LazyVStack` in a `ScrollView`. Each streamed chunk changes `transcript`, which invalidates the ForEach, and the growing agent message re-parses its markdown on every chunk. That is O(n²) over a long reply.
- It is fine for a few hundred rows. For multi-hour `run` sessions with thousands of tool calls I'd expect stutter. `LazyVStack` row heights are estimated, so scroll jumps and `scrollTo` landing in the wrong place are known SwiftUI issues on macOS.
- Mitigations:
  - make each row its own `@Observable` object, so only the streaming row invalidates;
  - throttle chunk application to about 30 Hz;
  - render the finished part of a message once;
  - if it still stutters, move the transcript to `List` (NSTableView-backed, so it recycles rows) or to an NSTextView or NSCollectionView via `NSViewRepresentable`.
- Auto-scroll currently always jumps to the bottom. "Stick to the bottom unless the user scrolled up" needs `onScrollGeometryChange`, which is macOS 15 only.

**AppKit fallbacks expected:**
- a better editor (NSTextView);
- cross-paragraph selection in the rendered markdown and transcript;
- possibly a high-volume transcript view;
- activation policy for a SwiftPM executable: `NSApp.setActivationPolicy(.regular)` is needed or the app gets no Dock icon or key window, and a real build would ship as an .app bundle anyway;
- user notifications (UNUserNotificationCenter) for "session needs you", which need a bundle identifier, so an .app.

**Concurrency:** Swift 6 strict concurrency fits this design well.
- The ACP connection is an actor, the session models are `@MainActor @Observable`, and events flow through an `AsyncStream`. The compiler caught real mistakes and there are no data-race warnings.
- The rough spots were `Process`, `Pipe` and `FileHandle`: callback-based APIs that need bridging, plus the `bytes.lines` stall above.

**Xcode requirement:** none for this spike. It builds with the Command Line Tools and SwiftPM, or with plain swiftc. Shipping a real app would want Xcode, or at least a script that wraps the binary in an .app bundle, for:
- an .app bundle with an Info.plist and an icon;
- code signing and notarisation;
- SwiftUI previews;
- Instruments, to profile the transcript.

The CLT's swift-testing install was also partly broken (see above), which Xcode would avoid.

**Verdict:** SwiftUI gives the best native macOS feel for the least code. The sidebar, sheets, menus, settings, badges and keyboard handling are all native, with no work. ACP plumbing in Swift concurrency is clean and small, with no SDK needed. The weak spots are rich text: rendering markdown, selecting across blocks, a capable editor, and a very long streaming transcript. Each has a known AppKit fallback, but the fallbacks are where the time will go.

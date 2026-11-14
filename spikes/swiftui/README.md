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
scripts/swiftc-build.sh core           # just PlannerCore (also builds what the probe links)
scripts/probe-gates.sh gates|flow|permission   # real-adapter probes, see "Gates" below
```

In the Claude Code sandbox `~/.npm` is not writable, so run the probes with
`AGENT="npm_config_cache=$TMPDIR/npm-cache npx -y @agentclientprotocol/claude-agent-acp"`.

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
| `Sources/PlannerCore/Gates.swift` | Planner's gates as data: `GateKind` (ask_user, confirm_start, check_in, ask_commit), `GateAnswer`, the MCP tool definitions with JSON schemas, argument parsing, and the result text the model reads. |
| `Sources/PlannerCore/MCPGateServer.swift` | A minimal MCP server (initialize, ping, tools/list, tools/call). `tools/call` suspends until the user answers. It doesn't depend on the transport. |
| `Sources/PlannerCore/MCPTransports.swift` | Two transports. `MCPHTTPTransport`: Streamable HTTP on 127.0.0.1 with NWListener and a secret path. `MCPFifoTransport`: a stdio shim, `/bin/sh -c 'cat <"$0/out" & exec cat >"$0/in"'`, relaying over two FIFOs. `MCPGateHost.start` tries HTTP first and falls back to FIFOs. |
| `Sources/PlannerDesk/GateViews.swift` | The native forms: ask_user, confirm_start, check_in, ask_commit, and a schema-driven `elicitation/create` form, plus the transcript record rows. |
| `prompts/*.md` | Short gate-aware versions of planner's explore, deep explore and plan prompts, with `{{placeholders}}`. The New Session sheet renders them. |
| `mock-agent/mock_acp_agent.py` | A fake ACP agent. It streams chunks, a thought, a plan, and a tool call, then requests permission and ends the turn with a question. With `[gates]` in the prompt it acts as an MCP client instead: it spawns the stdio server from `session/new.mcpServers` as Claude Code does, calls every gate, and sends one AskUserQuestion-shaped `elicitation/create`. |
| `scripts/AcpProbe.swift`, `scripts/probe-gates.sh` | A headless client that hosts the gate server, answers gates and elicitations after `PROBE_DELAY` seconds, and prints every ACP and MCP line with a timestamp. |
| `probe-logs/real-adapter-*.log` | Trimmed traces from the real adapter: auth, commands, thoughts and usage lines removed, email redacted. |

## What works (verified)

- **Tests, 19 passing in 6 suites** (`scripts/swiftc-build.sh test`, run 3 times in a row on desktop-view-004). The 9 new ones cover:
  - the gate server: initialize, tools/list, unknown methods, tool results, bad arguments returned as `isError`;
  - result wording and the `_meta` merge;
  - parsing the adapter's AskUserQuestion elicitation schema;
  - the HTTP transport, which returns early on EPERM;
  - a full session against the mock over the real FIFO shim. Each gate blocks the agent until answered (nothing else arrives meanwhile), the status is Awaiting answer, the elicitation is answered, the exact result text reaches the agent, the gate tool rows are hidden, and the session returns to Awaiting input;
  - Stop turn answering an open gate `cancelled` and an elicitation `cancel`.

  The original ones cover:
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
- **Questions, the fallback heuristic**: ACP has no message type for a question. An agent that asks in plain text ends its turn. The session goes to "Awaiting input" (green badge) and the reply box takes focus. If the agent's last message contains a `?`, its last paragraph is shown in a green callout above the reply box. ⌘↩ sends the reply as the next `session/prompt`. This now only applies when the agent did not use a gate tool.

## Gates: planner's questions as native forms (desktop-view-004)

Two mechanisms, both built and tested:

**(D) A gate MCP server hosted by the app.** Each session gets its own server, passed in `session/new.mcpServers`. `_meta.claudeCode.options.allowedTools: ["mcp__planner__*"]` lets its tools run without a permission prompt. The tools:

| Tool | Planner gate | Form | Result text the model reads |
|---|---|---|---|
| `ask_user{questions:[{id,text,choices?,multi?}]}` | explore/plan "ask about all of them together" | Every question at once: radio group, checkboxes (multi) or a text field. Each choice question also has an "Or type your own answer" field. "Send answers" (⌘↩). | `The user answered:\n- id (text): answer` |
| `confirm_start{brief}` | explore_deep `Reply "Make it so"` | The brief rendered as markdown. **Make it so** is the default (↩) button. "Clarify more" is enabled once a note is typed. | `Make it so` or `The user wants to clarify more ... <note>` |
| `check_in{summary,recommendations[],next_steps[]}` | `_explore_check_in` | A card with the summary and the recommendations (lightbulb icon). There is one button per numbered next step (⌘1…⌘4), a "focus on" field, Continue and Finish. | `The user picked next step N: …`, `The user wants you to focus on: …`, `continue`, `finish` |
| `ask_commit{context?}` | plan step 4 | "Yes, commit" (↩) / "No, leave it uncommitted" (Esc) | `Yes, commit the change.` / `No, do not commit.` |

While a call is open, the session status is **Awaiting answer** (purple badge). The status counts toward the Dock badge, and the form is pinned above the reply box. A permission request outranks a form (`AgentSession.refreshStatus`). The answer is the `tools/call` result. The transcript keeps a record row ("You answered: …"). The adapter's own `tool_call` rows for gate tools and for AskUserQuestion are hidden (`TranscriptItem.isShadowedTool`, keyed on `_meta.claudeCode.toolName`). Stop turn answers open gates with `cancelled`.

**(C) Built-in AskUserQuestion over ACP elicitation.** `initialize` now advertises `clientCapabilities.elicitation.form: {}`, and the adapter then turns AskUserQuestion into `elicitation/create`. `ElicitationRequest` parses `requestedSchema` (string `oneOf`, array `anyOf`, text, boolean, number) into a form with Submit (accept + content), Decline and Cancel. `$/cancel_request` closes the form unanswered.

**Prompt variants** (`prompts/`) tell the agent never to ask in plain text and to call the matching tool at each gate.

### Real adapter results (claude-agent-acp 0.107.0, Claude Code 2.1.323)

From `probe-logs/real-adapter-gates.log`, with a 75 s answer delay:
- **Local port binding is blocked in this sandbox.** NWListener failed with `POSIXErrorCode(rawValue: 1): Operation not permitted`. Unix domain sockets fail the same way. FIFOs work, so every real run used the FIFO stdio shim. The HTTP transport compiles, but it has only been checked as far as "fails with EPERM and falls back". Its round-trip test returns early when binding is refused.
- Claude Code first sends `server/discover` (MCP protocol `2026-07-28`). We answer -32601, and it falls back to `initialize` with protocolVersion `2025-11-25`, then `tools/list`. This happens during `session/new`, about 3 s after it is sent.
- The MCP tools are **deferred**. The model first calls `ToolSearch` with `select:mcp__planner__ask_user`, which adds about 1–2 s. The client sees that as a normal tool_call.
- **ask_user blocked for 79.8 s and returned fine** (open at 14.04 s, answered at 93.88 s). The `tools/call` carried `_meta: {"claudecode/toolUseId": …, "progressToken": 2}`. While it was open, the adapter sent `tool_call_update` with `status: in_progress` and `_meta.claudeCode.toolResponse.elapsedTimeSeconds: 30`, then `60`. There was no timeout, and we sent no progress notifications.
- Tool call updates the client sees for a gate:
  1. `tool_call` (title `mcp__planner__ask_user`, `kind: other`, `rawInput: {}`, pending);
  2. `tool_call_update` with the full `rawInput`;
  3. the 30 s and 60 s keepalive updates;
  4. `tool_call_update` with `toolResponse`;
  5. `status: completed` with `content`.
- **AskUserQuestion → `elicitation/create` worked and blocked for 79.8 s.** The request was `{"mode":"form","toolCallId":…,"message":"Which framework?","requestedSchema":{"properties":{"question_0":{"type":"string","title":"Framework","oneOf":[{"const":"SwiftUI","description":…},…]},"question_0_custom":{"type":"string","title":"Other",…}}}}`. Our reply was `{"action":"accept","content":{"question_0":"SwiftUI"}}`. The tool result was `Your questions have been answered: "Which framework?"="SwiftUI"`. No keepalive updates were sent while the elicitation was open. The tool_call title is "Asking for your input", then the question.
- **`structuredContent` hides the text.** The first run returned both `content` text and `structuredContent`, and the adapter showed the model the structured JSON as the tool result. For `confirm_start` that would have been `{"start":true}` instead of `Make it so`. The server now returns text only. `probe-logs/real-adapter-flow.log` confirms it: confirm_start → check_in → ask_commit, and the model's final line was `confirm_start: "Make it so" | check_in: "finish" | ask_commit: "No, do not commit."`
- The adapter warned `canUseTool will not be invoked for: mcp__planner__*` on stderr. This is expected: allowedTools pre-approves the gate tools, so no permission prompt appeared for them.

From `probe-logs/real-adapter-permission.log`, a **real `session/request_permission`**. The run passed `_meta.claudeCode.options.settings.permissions.ask: ["Bash(touch:*)","Bash(touch *)"]` and switched the mode from the user's default `auto` to `default` with `session/set_config_option {configId:"mode", value:"default"}`, which answered with `current_mode_update`. Then `touch probe-file.txt` produced:
`{"toolCall":{"toolCallId":…,"name":"Bash","rawInput":{"command":"touch probe-file.txt","description":"Create probe file"},"title":"touch probe-file.txt","kind":"execute",…},"options":[{"optionId":"allow-once","name":"Yes","kind":"allow_once"},{"optionId":"reject","name":"No","kind":"reject_once"}]}`.
There are only two options and no "always allow". The adapter drops persistent options when an ask rule matched (`noPersistentRule`, acp-agent.js ~6620). The existing permission bar handles this without changes.

### UX assessment: D vs C vs the heuristic

- **Heuristic (turn ended + `?`)**
  - The agent has already ended its turn, so the answer costs a whole new `session/prompt`.
  - Nothing is structured: numbered next steps, "Make it so" and yes/no all become free text that the user types.
  - It fires falsely on rhetorical questions and misses questions without a `?`.
  - It is fine as a fallback, and it's the only thing that works with agents that ignore the tools.
- **C, AskUserQuestion via elicitation**
  - It needs no server, it's Claude's own tool, and the model uses it readily.
  - It handles multiple questions, option descriptions, multi-select and an "Other" box per question.
  - It is generic. There is no semantic "Make it so" gate, no check-in card, and no commit question. Each would be a single-choice question, and the client couldn't tell a check-in from any other question to give it a distinct layout or status.
  - It is Claude-specific today: Codex and pi have no AskUserQuestion.
  - The schema comes in as a JSON object, whose key order a Swift decoder loses. We sort `question_N` naturally.
  - Elicitation is still marked unstable in the ACP schema.
- **D, gate MCP server**
  - It gives the best UX for planner's own gates. Each gate gets a purpose-built form, a distinct status, keyboard defaults (↩ = Make it so, ⌘1–4 = next steps), and a result phrased in the prompt's own words.
  - It works with any ACP agent that supports MCP servers, which is the seam for Codex and pi.
  - It blocks mid-turn, so the agent keeps its context and turn. 80 s waits were fine.
  - Costs:
    - a server per session;
    - a transport that has to work wherever the app runs: HTTP needs a bindable port, and in this sandbox only the FIFO shim worked;
    - deferred tool loading adds a ToolSearch step;
    - the prompt has to insist on the tools: "never ask in plain text".
  - We didn't measure how long a gate can stay open. The adapter's keepalives suggest long waits are expected. Hours-long waits (the user away from the desk) are still unverified.
- **Recommendation:**
  - Use D for planner's four gates.
  - Keep C enabled for ad-hoc questions the model asks on its own. Rendering it costs about 70 lines.
  - Keep the heuristic as the last resort.

  In the app all three share the same pinned panel, so the user sees one consistent "the agent is waiting on this form" pattern.

## What did not work or was left out

- **Gates (desktop-view-004):**
  - The HTTP MCP transport is unverified end to end, because the sandbox refuses every bind with EPERM. In a normal (unsandboxed) build it should be preferred, since it needs no FIFOs or shell. A sandboxed App Store build would need the `com.apple.security.network.server` entitlement.
  - **The forms have not been seen.** WindowServer is blocked here, so like the rest of the UI they are checked by compiling and by the session-model tests only.
  - `npx` failed on `~/.npm` (EPERM in the sandbox), so the probes reused an adapter already cached in `$TMPDIR/npm-cache`.
  - The user's claude.ai MCP connectors (mcp-proxy.anthropic.com, mcp.miro.com) were denied network access during the probes. They are unrelated and didn't affect the runs.
  - The first fix needed after the real run was dropping `structuredContent` (see Gates).
  - A pre-existing race showed up once: writing to an agent that had already exited threw an `NSError` (EPIPE) instead of an `ACPError`. `send` now wraps it.
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
  - the real planner prompts: explore, deep and plan now use the shortened gate-aware variants in `prompts/`, not `lib/planner/prompts/*.erb`, and run is still a one-line stand-in. A full explore or plan session on a real plan folder has not been run through the app, only the gate tools via the probe;
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

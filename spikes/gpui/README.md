# GPUI spike: planner desktop view

A throwaway spike, used to judge GPUI (Zed's UI framework) for a native macOS planner GUI.
It is a standalone Cargo project that does not touch planner's Ruby code.

## Run it

Rust is installed through Homebrew's keg-only `rustup` (`brew install rustup`, then
`rustup toolchain install stable`). You do not need Xcode: the build worked with only the
Command Line Tools, and `xcrun metal` is absent.

```sh
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
cd spikes/gpui
cargo run --release -- ~/dev/my-projects            # parent folder holding several repos
cargo run --release -- ~/dev/my-projects --agent "python3 $PWD/mock_agent.py"   # offline demo
MOCK_AGENT_DELAY=0.3 cargo run -- . --agent "python3 $PWD/mock_agent.py"        # slow streaming
cargo test                                            # 9 tests, see below
cargo run --example oneshot -- "<agent command>" "<prompt>"   # headless ACP check
```

The agent command defaults to `npx -y @agentclientprotocol/claude-agent-acp`. It can be
changed with `--agent` or `PLANNER_AGENT_COMMAND`. Zed's old packages,
`@zed-industries/claude-code-acp` (last version 0.16.2) and
`@zed-industries/claude-agent-acp` (last version 0.23.1), are deprecated on npm with the
message "renamed to @agentclientprotocol/claude-agent-acp". The new package was at 0.107.0
on 2026-11-14.

## What it does

The window has three columns:

- **Sidebar.** Lists the plan folders under `<parent>/docs/plans/*/` and
  `<parent>/<child>/docs/plans/*/`, grouped by repo, with their `.md` files. A plan folder
  that has live sessions shows an "N live" tag. Below that is the session list. Each session
  shows a status tag: starting, working, needs permission, awaiting input, closed or failed.
- **File pane.** Shows the selected file as rendered markdown (gpui-component `TextView`).
  The **Edit** button swaps in a multi-line `Textarea`, and **Save** writes the file.
  **New iteration** creates the next `ITERATION-NNN.md` from a template and opens it for
  editing.
- **Session pane.**
  - An optional extra-instructions input, and **Explore**, **Plan** and **Run** buttons.
    Each button starts a new ACP session in the repo folder. The prompt names the plan
    folder and the selected or latest iteration file.
  - The transcript shows:
    - user prompts
    - streamed agent text, rendered as markdown
    - thoughts
    - tool calls, with a status tag that changes as `tool_call_update`s arrive
    - permission cards
  - When a turn ends, the session becomes **awaiting input**. The last agent message gets a
    green border and the label "The agent is waiting for your reply". The reply box is
    enabled, and Cmd+Enter or **Send reply** sends the next `session/prompt`.
  - A `session/request_permission` becomes a card with one button per option. allow_once is
    primary, allow_always is plain, and reject options are red. There is also a Cancel
    button. After you answer, the card shows "You chose: ...".
  - **Stop** sends `session/cancel`. **Close** ends the agent process.

Several sessions can run at once. Each session has its own agent process and thread, and
events are pumped into the UI with `cx.spawn`.

## Code layout

| File | Purpose |
|---|---|
| `src/plans.rs` | Plan-folder discovery and the next-iteration path. Pure std, with unit tests. |
| `src/acp.rs` | A UI-agnostic ACP client built on `agent-client-protocol` 5.3 (`Client.v1()`). `start_session(cmd, cwd, prompt)` returns a `SessionHandle` (prompt, cancel, close) and a channel of `SessionEvent`s. A permission request carries a reply channel. |
| `src/ui.rs` | The GPUI view (`PlannerApp`). |
| `src/main.rs` | Argument parsing and the window. |
| `mock_agent.py` | A small ACP agent. On its first prompt it streams chunks, starts a tool call, asks permission, finishes or fails the tool call, and ends the turn with a question. On later prompts it echoes the reply. |
| `tests/acp_mock.rs` | Tests the ACP client against the mock: streaming, permission allow/reject/cancel, a second prompt, two concurrent sessions, and a bad command. |
| `tests/ui.rs` | Headless GPUI tests through `gpui_kit::test`. They click a sidebar file, click Explore and Plan to run two sessions, click the "Allow once" permission button, type a reply and click Send, switch session and click Reject. Then they create a new iteration, type into the editor and click Save. |

## Results

| | |
|---|---|
| Tests | 9 pass (3 unit, 4 ACP-against-mock, 2 headless UI) |
| Clean debug build (all deps) | 57 s wall, 264 s CPU, Apple Silicon |
| Clean release build | 1 min 38 s wall, 658 s CPU |
| Incremental debug rebuild after touching `ui.rs` | 5 s |
| Release binary (`strip = true`) | 20.9 MB (20,915,680 bytes), one self-contained executable |
| Crates compiled | 424. `cargo tree -e normal` lists 406 unique packages; `Cargo.lock` has 872 entries, including optional or other-platform crates |
| `target/` size | 7.6 GB, with debug, release and test builds |
| Real adapter | Works. `oneshot` against `npx -y @agentclientprotocol/claude-agent-acp` streamed "pong", then tool calls (`Write hello.txt`, `rm -f hello.txt`) with title and status updates, then `end_turn`. |

### What did not work or was not verified

- **I never saw the window.** Running the binary inside the agent sandbox panics at startup,
  because `+[NSPasteboard generalPasteboard]` returns NULL when the sandbox blocks the
  pasteboard XPC service. The headless `gpui_kit::test` tests are what show that layout,
  clicks, focus and input work. Visual polish (spacing, colours, how markdown looks) is
  unverified. Run `cargo run --release -- <parent>` yourself to see it.
- **A real `session/request_permission` was not seen.** The adapter applies the user's
  Claude Code permission settings, and this machine auto-allowed both Write and Bash. Only
  the mock exercises the permission UI. To see real prompts, set Claude Code's permission
  mode to default (ask). A later version could call `session/set_mode`.
- **Adding gpui-kit's `test-support` feature broke the lockfile.** `gpui-fast` 0.1.14 pins
  `taffy = "=0.15.0"` and other exact versions, which clashed with the existing lock (taffy
  0.15.1). Pinning taffy just hit the next exact pin (`unicode-properties`). The fix was to
  delete `Cargo.lock` and re-resolve.
- **Headless tests with a real agent thread need `cx.executor().allow_parking()`.** Without
  it, GPUI's deterministic test scheduler fails with "Detected activity on thread
  acp-session ... Your test is not deterministic".
- **Small API traps:**
  - the `.when()` builder needs `use gpui_kit::prelude::FluentBuilder`
  - `.disabled()` needs `component::Disableable`
  - `use gpui_kit::*` in a test file shadows `#[test]`, which fails with "recursion limit
    reached while expanding #[test]"
  - `Textarea` has no `.id()`, unlike `Input`, so I wrapped it in a `div().id(..)`
  - plain divs are invisible to the test harness unless you call `.test_support()`
- **A UX bug the UI test caught.** Entering edit mode did not focus the editor, so typed
  text went nowhere. It is fixed with `state.focus(window, cx)`.
- **Spike shortcuts:**
  - each session spawns its own agent process; ACP allows many sessions per process
  - no `session/load` or resume after restart
  - no file watching, so the sidebar needs **Refresh**
  - the Explore, Plan and Run prompts are invented here, not planner's real prompt templates

## UX assessment of GPUI (with gpui-component / gpui-kit)

**Dev experience.**
- Writing the UI is fast once you know the idioms. Views are Rust structs with
  `render(&mut self, window, cx)`, using Tailwind-like builder styling (`.p_2().gap_2()
  .border_b_1()`).
- State is plain fields, and `cx.notify()` triggers a re-render.
- Async fits well. `cx.spawn(async move |this, cx| this.update(cx, ..))` pumps a channel
  from a background ACP thread straight into the view, and the `agent-client-protocol`
  crate is runtime-neutral (smol/futures), so no tokio is needed.
- The UI compiled on the second attempt, after two missing trait imports. It produced no
  warnings and ran correctly the first time under the headless test harness.
- Compile times are acceptable: about 5 s incremental and about 1 min clean.
- The main cost is the borrow checker inside `render`. You collect child elements before
  borrowing `self` mutably, clone the theme, and use `move` closures carrying indices.

**Widgets.** gpui-component is broad: Button (variants, sizes), Input, Textarea, Editor
(code editor with tree-sitter), TextView (markdown and HTML), Tag/Badge, Sidebar, Resizable
panels, Dock, Table, Tree, List, virtual lists, Dialog, Sheet, Popover, Notification and
Tooltip. For this app nothing essential was missing. These are absent, or I didn't find them:
- a ready-made chat or transcript component (there is `message`/`message_scroller`, which I
  did not try)
- native macOS controls; everything is custom-drawn, so it looks like Zed, not AppKit
- system-standard text behaviour in places, such as the macOS services menu and spell check

**Text input.**
- Input, Textarea and Editor are good: multi-line, auto-grow, placeholder, Cmd+Enter
  (`InputEvent::PressEnter { secondary }`), undo, selection and IME.
- Gotcha: a new `TextareaState` is not focused, so you have to call `focus`.

**Markdown.**
- `TextView::markdown(id, text)` renders headings, bold, lists and code blocks out of the
  box, with theme-aware styling.
- Streaming works by re-rendering it with the growing string. The real adapter sends many
  small chunks (5–20 characters), so a long transcript re-parses often. I did not
  benchmark it.

**Scrolling.**
- `div().id(..).overflow_y_scroll().track_scroll(&handle)` plus
  `handle.scroll_to_bottom()` gives an auto-following transcript.
- No virtualisation unless you use `uniform_list` or `virtual_list`. A long transcript
  would need it.

**Docs.**
- Thin. GPUI itself has almost no prose docs; you learn from Zed's source and from
  gpui-component's examples and doc comments.
- The gpui-kit README has a hello world, and `tests/ui.rs` in the gpui-kit crate was the
  most useful reference.
- I found most APIs by grepping `~/.cargo/registry/src` (`InputState` really lives in
  `gpui-base`, re-exported through `gpui_component::input`).

**API churn.** High, and this is the biggest risk.
- The crates.io `gpui` is stuck at 0.2.2 (October 2025). gpui-component no longer uses it.
  Instead it depends on `gpui-pre =0.3.12`, a weekly snapshot of Zed's gpui (described as
  "snapshot of zed@d2a4fb6") published by the gpui-component maintainer.
- gpui-component shipped 0.7.2 → 0.9.1 in four weeks (2026-10-12 → 2026-11-09), and split
  into gpui-kit, gpui-base and gpui-component along the way.
- `agent-client-protocol` went 3.6 → 5.3 in under three weeks, and v5's API (`Client.v1()`
  builders, `connect_with`, `on_receive_request!()` macros) is completely different from
  the 0.x API that most blog posts show.
- Exact `=` pins across the gpui crates make adding features fragile, as the lockfile
  problem above shows.
- Expect to pin versions and spend time on every upgrade.

**Verdict for planner.**
- GPUI can build the experience the brief describes: dense, fast, keyboard-friendly panes,
  live streaming transcripts, inline permission cards and a clear "awaiting input" state.
  Its headless UI test harness is a real advantage, since it let me verify the
  question-and-permission flow by clicking through it without a display.
- It gives up native macOS look and feel, and it has thin docs and heavy churn.
- It suits a team happy to live in Rust and track Zed. A team that wants AppKit-native
  controls and stable APIs should look at SwiftUI.

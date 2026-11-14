# FINDINGS-001 — A deep, mostly unattended mode for `planner explore`

## Summary

A `--deep` switch on `planner explore` fits the app. It follows the `--print` pattern on `planner run`. It changes only the explore command, the agent's `explore` call, a new prompt template, specs and docs. The findings file, table of contents and `planner plan` are unaffected. The session stays interactive. The agent clarifies the brief with the user, then works without input for a soft 90 minutes. It hands the deeper work and every implementation to subagents, each with `isolation: worktree`. Running the further exploration as subagents is a real benefit: it is the only way to get several isolated implementations in parallel. It also keeps the main conversation small, and permission prompts still reach the user. Subagents run in the background by default and still keep `Bash`, `Edit`, `Write`, `WebFetch` and `WebSearch`. Each spike works on a branch named `<plan-folder-without-timestamp>-<NNN>`, numbered from the first free number. Pushes of exactly those branches are pre-approved. A push the system blocks is reported and left in place, and the findings end with cleanup commands. The Claude Code sandbox is what makes the unattended phase both possible and safe. With `autoAllowBashIfSandboxed`, spike commands such as `git commit` and test runs go ahead without prompts, inside a filesystem and network boundary with no outside hosts. Content-scoped `ask` rules still force a prompt for dependency installs. An unsandboxed rerun of an approved install is the one other prompt. The push runs outside the sandbox, because macOS cannot push over SSH from inside it. `WebSearch` and `WebFetch` are not shell commands, so the sandbox does not limit them, and they keep working. MCP tools and claude.ai connectors are removed. The draft flags in finding 10 have no open documentation questions. Finding 11 lists what to try out while building. Finding 12 orders the work into five iterations, each one shippable on its own: a refactor first, then research-only deep mode with its security baseline, then spikes in worktrees, then pushes and cleanup, then optional follow-ups.

## Recommendations

- Add `--deep` to `planner explore` rather than a new command, with its own template sharing partials with the current one. (findings 1, 2)
- Run the further exploration and every implementation as a custom `spike` subagent, defined by planner through `--agents`, with `isolation: worktree`. (findings 3, 4)
- Have the main agent always spawn spikes with subagent type `spike`, and also pass `isolation: "worktree"` on the call. A named spawn while agent teams are on would otherwise run in the main checkout. (findings 3, 11)
- Pass `worktree.baseRef: "head"` through `--settings` so spike worktrees contain the plan folder and any unpushed work. (finding 4)
- Work out the branch prefix in Ruby, by stripping the leading `YYYYMMDDHHMM-` from the plan folder name. Have the main agent number spikes from the first free `<NNN>` across local and remote branches. (findings 2, 5)
- Pre-approve and exclude from the sandbox exactly `git push -u origin <prefix>-*`, run as its own plain Bash call. Set `GIT_TERMINAL_PROMPT=0` through `--settings` `env`, not as a command prefix, so the allow rule still matches. (findings 5, 8, 11)
- End the deep findings with a Branches table and a Cleanup block. The agent never removes worktrees or branches itself. (finding 5)
- Turn on the sandbox for deep sessions with `autoAllowBashIfSandboxed: true`, `allowUnsandboxedCommands: true` and an empty network allowlist. Keep `WebFetch` as a bare allow rule, never `WebFetch(domain:*)`. (finding 8)
- Gate dependency installs with content-scoped `ask` rules such as `Bash(bundle install *)`. These also match the bare command and any leading env assignment. The prompt allows an unsandboxed rerun only for an install the user approved. (findings 6, 8, 11)
- Remove MCP tools with `--disallowedTools=mcp__*` and `disableClaudeAiConnectors: true`. This matters more in deep mode, because background subagents "keep every MCP tool" the parent has. A later iteration could do the same for plain `explore`. (findings 1, 8, 11)
- Have the main agent record a start time with `date` at "go", and stop starting new work at 90 minutes. (finding 7)
- Check early that the project's test runner works in the macOS sandbox. Python process pools have failed there in this repo's own runs. (findings 8, 11)
- Add `.claude/worktrees/` to `.gitignore` in the plan that introduces worktrees. (findings 4, 12)
- Write the next briefs in the order in finding 12, starting with the partials refactor as `ITERATION-002.md`. Use the draft flags in finding 10 and fold the hands-on checks from finding 11 into each iteration's manual verification. (findings 9, 10, 11, 12)

## Questions

1. How can explore questions be clarified with the agent and then given more leeway to find information without the user's input?
2. How can it produce working spikes or example code, including several implementations, using worktrees?
3. How can web search be allowed in a secure way?
4. What iterative build plan should change the command?
5. Would a `--deep` switch on `explore` work, and how would it affect the current design of the app?
6. Could the further exploration be a subagent call, and would that be a benefit?
7. Branch naming, push approval, what happens when a push is blocked, and cleanup.
8. Security around the web tools: MCP removal and sandboxing `Bash`.
9. The open checks in the draft flags: `Agent` in `--tools`, whether the spike gets `Bash`, the bare `bundle install` match, and the env-prefix push match.
10. A draft order for the implementation.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Session shape | One interactive session: clarify, then work unattended |
| Worktrees | Subagents manage them. Respect any worktree-focused skill added in the future |
| What is kept from a spike | Its branch. Every branch name is listed in the findings and pushed to the remote if permissions allow |
| Web security level | Option (a): `WebSearch`, plus `WebFetch` to any domain, as explore has today |
| Dependencies | Spikes cannot install dependencies on their own and must ask permission. This is the one exception to working unattended |
| Output | A normal findings file |
| Limits | A soft 90-minute time limit |
| Branch name | The plan folder name without its timestamp, plus `-<NNN>` for each worktree, for example `longer-unintended-explore-sessions-001` |
| Branch numbering | From the first free number |
| Push approval | Pre-approved |
| Push blocked by system permissions | Report it. Don't clean up the worktree or branch |
| Cleanup | Write the cleanup commands in the final findings file |
| MCP in deep mode | Removed: `--disallowedTools=mcp__*` plus `disableClaudeAiConnectors: true` |
| Sandbox | On, with `autoAllowBashIfSandboxed: true` |
| Commands the sandbox blocks | `allowUnsandboxedCommands: true`, so the user is asked about an unsandboxed rerun |
| Push and the sandbox | `git push -u origin <prefix>-*` is excluded from the sandbox, matching the pre-approved rule |
| Sandbox network allowlist | Empty. `WebSearch` and `WebFetch` must still work, and they do (finding 8) |

## Findings

### 1. Today's explore is read-only by construction

- The agent call fixes the tools: `EXPLORE_TOOLS = 'Read,Grep,Glob,Write,WebFetch'` and `--allowedTools=Edit(findings),Edit(toc),WebFetch` (`lib/planner/agents/claude.rb:15`, `:38-41`).
- The prompt forbids repository changes and anything beyond reading: "Do not modify repository files", "Use read-only exploration only", "You cannot search the web" (`lib/planner/prompts/explore.md.erb:16-20`, `:44-51`).
- WebFetch only, with no WebSearch, was a deliberate decision of the earlier explore plan (`docs/plans/202610291422-add-explore-task-to-planner/PLAN-002.md:15`). The conversation loop lives only in the prompt (`.../PLAN-005.md:18`).
- `--tools` limits built-in tools only. The CLI reference says: "The flag doesn't affect MCP tools; to deny those too, use `--disallowedTools "mcp__*"`" (https://code.claude.com/docs/en/cli-reference.md). This explore session shows it: it was started with explore's `--tools` but still has Google Drive, Gmail and Claude Docs MCP tools.

Deep mode needs every one of these relaxed, which is why it needs its own tool set and its own wording.

### 2. What a `--deep` switch would change

`--deep` follows the pattern of `--print` on `planner run`: a boolean in `OptionParser` that changes what the command does (`lib/planner/commands/run.rb:42-52`).

| Part | Change |
| --- | --- |
| `Commands::Explore#parse` (`lib/planner/commands/explore.rb:53-59`) | Return `[model, deep]`, with `opts.on('--deep')`. `-d` is free on explore, but `planner new` already uses `-d` for `--dir` (`lib/planner/commands/new.rb:34`), so a long-only flag avoids confusion |
| `Commands::Explore` | New `branch_prefix(folder)`: `File.basename(folder).sub(/\A\d{12}-/, '')`. The timestamp format comes from `strftime('%Y%m%d%H%M')` in `new.rb:45-46`. A folder not made by `planner new` keeps its whole name |
| `Commands::Explore#prompt` (`:43-50`) | Choose the template by `deep`. Pass `branch_prefix` to the deep template |
| Prompt | New `explore_deep.md.erb`. Findings structure, Check-in, Stats, Table of contents and Summary for the user are the same as today. Move them into partials, as `_table_of_content.md.erb` already is (`lib/planner/prompts/`). Rules, Steps, the intro and a Branches section differ |
| `Agents::Claude#explore` (`lib/planner/agents/claude.rb:38-41`) | Add `deep:` and `branch_prefix:` (or a separate `#explore_deep`). Deep mode builds the flags in finding 10. The interface comment at `:5-7` is the contract every agent must meet, so update it |
| `spec/spec_helper.rb:26-28` `FakeAgent#explore` | Record `deep` and `branch_prefix` |
| Specs | `explore_spec.rb` gains a `--deep` group, including the prefix for a stamped and an unstamped folder. Its current examples stay valid for the default mode, for example the assertion that the prompt includes "You cannot search the" (`spec/planner/commands/explore_spec.rb:164-167`). `claude_spec.rb:41-48` gains a deep example asserting the full argv |
| `CLI::USAGE` (`lib/planner/cli.rb:22`), README (`README.md:21`), GLOSSARY | Document `[--deep]` |
| Unchanged | Findings file naming and suffixes (`explore.rb:31-41`), `TableOfContent`, `planner plan`, `toc`, `summarise` |

A separate template is better than `<% if deep %>` blocks. More than half of the Rules and Steps differ, and summarise shows that conditional ERB needs `trim_mode: '-'` (`lib/planner/commands/summarise.rb:65`). A new command such as `planner spike` would duplicate the findings-file logic and the docs, for no gain.

```mermaid
flowchart LR
  cli["planner explore --deep ITERATION-001.md"] --> cmd["Commands::Explore<br/>parse -> deep<br/>branch_prefix(folder)"]
  cmd --> tpl["explore_deep.md.erb<br/>+ shared partials"]
  cmd --> agent["Agents::Claude#explore(deep: true, branch_prefix:)"]
  agent --> claude["claude --tools / --allowedTools / --disallowedTools<br/>--settings {env, worktree, permissions, sandbox, connectors}<br/>--agents {spike}"]
```

### 3. Running the further exploration as subagents is a benefit

All from https://code.claude.com/docs/en/sub-agents.md unless noted:

- **Parallel implementations need it.** Worktree isolation is per subagent ("Set to `worktree` to run the subagent in a temporary git worktree"). The main session can only be in one worktree at a time. Up to 20 subagents run at once by default.
- **Context.** Each subagent "runs in its own context window". "The parent doesn't see the subagent's intermediate tool calls or outputs, only that final result" (https://code.claude.com/docs/en/tools-reference.md, Agent tool behavior). The main conversation keeps the clarified brief, the decisions and the findings file, rather than logs and diffs.
- **Prompts still reach the user.** For background subagents, "Claude Code surfaces the prompt in your main session and names the subagent that is asking." This is the route for the dependency exception (finding 6).
- **The tools a spike needs survive the background.** Subagents start in the background by default. A background subagent keeps "only these built-in tools: `Read`, `Grep`, `Glob`, `LSP`, `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, …, `EnterWorktree`, `ExitWorktree`, …". Every tool the spike definition lists is in that set (finding 10).
- **Same sandbox.** "Subagents run in the same process as the parent session and use the same sandbox configuration" (https://code.claude.com/docs/en/sandboxing.md, Scope).
- **Future worktree skill.** The `skills` field preloads named skills into the subagent ("The full content of each listed skill is injected into the subagent's context at startup"). Planner can add a worktree skill to the `spike` definition once one exists in `lib/planner/skills` (`lib/planner/skill_catalog.rb:12-18`).
- **Defined by planner, not the repo.** `--agents` takes JSON with `prompt`, `description`, `tools`, `model`, `isolation`, `skills`, `maxTurns` and other fields (https://code.claude.com/docs/en/cli-reference.md). No `.claude/agents/` file is needed in the user's project.

Costs and limits:

- Subagents cannot use `AskUserQuestion`; it is in the filter "applies to every subagent, even when listed in `tools`". Only the main agent clarifies and checks in.
- They start fresh: "It doesn't see your conversation history". The main agent must pass the brief, the decisions, the spike's goal and its branch name in the task message.
- The 200-search limit per session covers subagents too (https://code.claude.com/docs/en/tools-reference.md#session-search-limit).
- Don't name it `Explore`: a built-in subagent already has that name. The read-only research subagents in build step 1 can simply be the built-in `Explore` agent.
- With agent teams on, a spawn that carries a `name` "launches as a teammate". "An `isolation` value in the subagent's frontmatter doesn't prevent it, and the teammate then runs in the main session's working directory." "Passing `isolation` on the call itself does prevent that." The prompt should therefore have the main agent pass `isolation: "worktree"` on every spike call, as well as setting it in the definition.

```mermaid
sequenceDiagram
  participant U as User
  participant M as Main agent
  participant S1 as spike -001 (worktree, sandboxed)
  participant S2 as spike -002 (worktree, sandboxed)
  U->>M: planner explore --deep
  M->>U: clarifying questions
  U->>M: answers, "go"
  M->>M: date (start clock), first free NNNs
  par
    M->>S1: Agent(spike, isolation: worktree): brief + decisions + approach A + branch prefix-001
    M->>S2: Agent(spike, isolation: worktree): brief + decisions + approach B + branch prefix-002
  end
  S1-->>U: ask: bundle add … (ask rule)
  U-->>S1: approve
  S1-->>U: ask: rerun unsandboxed?
  U-->>S1: approve / deny
  S1-->>M: summary, worktree path, branch, commit
  S2-->>M: summary, worktree path, branch, commit
  M->>M: git push -u origin each branch (pre-approved, unsandboxed)
  M->>M: write FINDINGS incl. Branches + Cleanup
  M->>U: check-in
```

### 4. Worktrees: what Claude Code does, and the base-branch trap

From https://code.claude.com/docs/en/worktrees.md:

- A subagent worktree is "removed automatically when the subagent finishes without changes". "A worktree with changes stays on disk until the periodic sweep" can remove it without losing work. The sweep keeps worktrees with "changed or untracked files, or unpushed commits". A spike always commits, so its worktree is never removed straight away. A spike whose push was blocked keeps its unpushed commits, so the sweep leaves it alone, which matches the "don't clean up" decision.
- **Base branch.** Worktrees branch from "the repository's default branch on the remote" unless `worktree.baseRef` is `"head"`. With the default, a spike would not see the unpushed `ITERATION-*.md` or any local work. Pass `{"worktree":{"baseRef":"head"}}` through `--settings`, which overrides for one session only (cli-reference `--settings`).
- **Isolation is enforced.** Edits to the main checkout, commands run there, and git redirected into it are refused. A `cp` or a shell redirect into the main checkout is not ("None of them tracks which files a shell command writes"). The sandbox's write limits apply on top of these checks.
- **Sandbox and git in worktrees.** "When the working directory is a linked git worktree, the sandbox also allows writes to the main repository's shared `.git` directory so commands such as `git commit` can update refs and the index. Writes to `hooks/` and `config` inside that directory remain denied" (sandboxing.md). `.claude/worktrees/` is not on the sandbox's protected list, which names `.claude` settings, skills, agents, commands and hooks. So spikes can write there. I inferred this rather than read it.
- "Interactive runs require workspace trust." The user has already used `claude` in their repos, so this is not an issue.
- The docs advise adding `.claude/worktrees/` to `.gitignore`. This repo's `.gitignore` has only `/pkg/`, `/.rspec_status` and `/coverage/` (`.gitignore:1-3`).
- `permissions.blockWritesOutsideWorkingDirectories` removes the worktree tools. Worth knowing if a user's settings set it.
- The worktree directory name is chosen by Claude Code, not planner. The spike must report its own path, for example from `git rev-parse --show-toplevel`, so the cleanup commands can name it.

### 5. Branches, pushing and cleanup

**Naming.** The prefix is the plan folder name without its timestamp. For this folder that is `202611141235-longer-unintended-explore-sessions` → `longer-unintended-explore-sessions`. Each spike gets `<prefix>-<NNN>`. Planner works out the prefix in Ruby (finding 2), and the main agent gives each spike its branch name in the task message. The spike runs `git switch -c <branch>` as its first command. When a worktree is on a branch other than its own, Claude Code's removal "keeps that other branch and its commits" (worktrees.md), so the branch outlives the worktree.

**Numbering.** From the first free number. Before "go", the main agent runs `git branch --list '<prefix>-*'` and `git ls-remote --heads origin '<prefix>-*'`. Both are read-only, and the second needs the network, so make it its own call. Numbering starts at the lowest `<NNN>` used by neither, so a second deep run or a later iteration never reuses a branch. If `ls-remote` fails, number from local branches only and say so in the findings.

**Pushing.** Pre-approve exactly `Bash(git push -u origin <prefix>-*)` in `--allowedTools`, rather than a wider `Bash(git push *)`. Exclude the same pattern from the sandbox (finding 8). Rules are checked "deny, then ask, then allow" (https://code.claude.com/docs/en/permissions.md), so a user or managed `deny` or `ask` rule on `git push` still wins. That is the "blocked by system permission" case.

Set `GIT_TERMINAL_PROMPT=0` through `--settings` `"env"`, not as a prefix on the command. Claude Code strips a leading assignment only for "certain known-safe environment variables", and "An allow rule won't match past an assignment of any other variable" (permissions.md, Bash). A prefixed push could therefore lose its pre-approval. Set in `env`, it applies to every git call in the session, so a push that would ask for credentials fails fast instead of hanging. The spikes don't do network git, so nothing else is affected.

Ways a push can fail:

| Cause | What the agent sees |
| --- | --- |
| A deny rule in user or managed settings | Tool call refused |
| The command is not the exact plain form (`cd … &&`, `git -C`, a substitution), so it stays sandboxed | SSH push fails in the macOS sandbox (finding 8) |
| Git needs a password or passphrase | Fails at once because of `GIT_TERMINAL_PROMPT=0` |
| No `origin`, or the remote rejects the branch | Git error |

The main agent pushes every branch at the end of the unattended phase, one Bash call per branch, from the main checkout. Branches made in a linked worktree are visible there. For each blocked or failed push it records the error. It leaves the worktree and branch untouched, and puts the push in "Commands that needed help".

**What the deep findings file gains.** A `## Branches` section after `## Findings`:

```markdown
## Branches

| Branch | Spike | Worktree | Last commit | Pushed |
| --- | --- | --- | --- | --- |
| longer-unintended-explore-sessions-001 | <approach> | .claude/worktrees/<name> | <sha> <subject> | Yes / No: <reason> |

### Cleanup

Run these when you are done with the spikes. Nothing has been removed.

    git worktree unlock .claude/worktrees/<name>      # only if git says it is locked
    git worktree remove --force .claude/worktrees/<name>
    git branch -D longer-unintended-explore-sessions-001
    git push origin --delete longer-unintended-explore-sessions-001   # only for pushed branches
```

The commands come from worktrees.md ("run `git worktree remove`, adding `--force` if the worktree has uncommitted changes… If git refuses because the worktree is locked, run `git worktree unlock` on it first"). The findings are for reading only, so the agent writes these commands and never runs them. The prompt must also tell the agent never to remove a worktree or branch itself.

### 6. Dependencies must ask

- Even with sandbox auto-allow, "Content-scoped ask rules like `Bash(git push *)` still force a prompt" (https://code.claude.com/docs/en/permissions.md:748-754). Content-scoped `ask` rules in the `--settings` blob therefore guarantee a prompt. Examples: `Bash(bundle install *)`, `Bash(bundle add *)`, `Bash(gem install *)`, `Bash(npm install *)`, `Bash(yarn add *)`, `Bash(pip install *)`.
- **Bare commands match.** "A `*` at the end, with a space before it, also matches the bare command. `Bash(ls *)` matches `ls`" (permissions.md, Wildcard patterns). So `Bash(bundle install *)` covers a bare `bundle install`, and no extra rule is needed.
- **Env prefixes and wrappers don't dodge them.** "A deny or ask rule matches past any leading assignment". Wrappers such as `timeout`, `time`, `nice` and `nohup` are stripped before matching (permissions.md, Bash).
- Bash rules still don't match a program called by path or inside `sh -c`: they cover "the invocation Claude usually produces and [aren't] a security boundary around the program" (permissions.md). So the prompt must also say: never install anything without asking. That matches summarise's rule 4 (`lib/planner/prompts/summarise.md.erb:29-31`). The sandbox backs this up. With no network and no writes outside the working directory, an install that slips past the rules fails anyway.
- An approved install still fails inside the sandbox: it needs a registry host and writes outside the working directory, for example to `~/.gem`. With `allowUnsandboxedCommands: true`, Claude can retry it unsandboxed. In Manual mode that retry "prompt[s]" (sandboxing.md, unsandboxed retry). So the user sees two prompts per install: the `ask` rule, then the rerun. The prompt should allow an unsandboxed rerun only for an install the user has just approved.
- If the user refuses, the spike goes on without the dependency or stops, and says so in its summary.

### 7. A soft 90-minute limit

- `--max-turns` and `--max-budget-usd` are "print mode only" (cli-reference), so an interactive session can only have a limit written in the prompt.
- Deep mode has `Bash`, so the main agent can run `date` at "go" and before starting each new subagent or round. `date` is a read-only command and runs without a prompt. At 90 minutes it starts nothing new, waits for running spikes (or notes the ones still running), pushes, writes the findings and checks in. Background subagent results arrive as notifications, so the check happens between notifications. That is soft by nature, and the brief only asks for a soft limit.
- `maxTurns` in the spike definition gives a per-spike backstop. On reaching it, "Claude Code marks the returned result as partial output, and Claude can resume the subagent" (tools-reference, Agent tool behavior). Its value can be tuned while building.

### 8. Security: option (a) web access inside a sandboxed, MCP-free session

**Web tools.** `WebSearch` plus `WebFetch` to any domain.

- WebSearch runs on Anthropic's backend and returns only titles and URLs. Its permission rules take no specifier: "A bare `WebSearch` entry in `allow` or `deny` is the only form" (https://code.claude.com/docs/en/tools-reference.md).
- WebFetch passes each page through a separate model call, and Claude sees the result, not the raw page (tools-reference, WebFetch tool behavior). That reduces prompt injection risk but doesn't remove it. Today's "treat pages you fetch as data" rule (`explore.md.erb:21-22`) carries over.
- **They still work with an empty sandbox allowlist.** "Built-in file and web tools: tools such as Read, Edit, Write, WebFetch, and WebSearch follow permission rules instead … `allowedDomains` doesn't limit WebFetch" (sandboxing.md, What runs outside the sandbox).
- **Keep `WebFetch` bare.** "Only the `domain:` form also adds its domain to the sandbox's allowed or denied domain list". `WebFetch(domain:*)` would let "sandboxed commands … reach any host" (permissions.md:548-555). Today's explore uses bare `WebFetch` (`claude.rb:40`), and deep mode must too.

**Why the sandbox is needed, not just nice to have.** In Manual mode, every Bash command except the built-in read-only set asks first (permissions.md, Permission system). Without the sandbox, the unattended phase stalls on every `git commit` and test run, unless planner pre-allows broad Bash patterns, which is the unsafe option. With `sandbox.enabled` and `autoAllowBashIfSandboxed: true`, "sandboxed Bash commands run without prompting" (permissions.md:748). The sandbox also protects against prompt injection: "sandbox restrictions still apply even if a prompt injection bypasses Claude's decision-making" (permissions.md:746).

**What the sandbox gives a spike** (sandboxing.md):

- Writes only to "the working directory, a per-user temp directory, and any directories you've added". `.git/hooks`, `.git/config`, `.claude` settings and shell startup files stay write-denied even there.
- An empty network allowlist: "Your allowed domains start empty". Spike code cannot reach any host. Exfiltration through a shell command is closed. Exfiltration through a WebFetch URL stays open, which option (a) accepts.
- Subagents share the same sandbox (Scope section).

**Escape hatches, as decided:**

- `allowUnsandboxedCommands: true`. A command that fails in the sandbox can be retried unsandboxed, and in Manual mode the retry prompts. This is the route for approved installs (finding 6). The risk: a prompt-injected agent could ask for an unsandboxed rerun of something else. The user still sees and approves every one, and the prompt says reruns are only for approved installs.
- `excludedCommands: ["git push -u origin <prefix>-*"]`. This is needed because "On macOS, `git fetch`, `git pull`, and `git push` against an SSH remote fail inside the sandbox even when the host is allowed". Excluded commands "can reach any host", but only the exact pre-approved push text matches: "a call which adds a `cd`, uses `git -C`, or contains a command substitution stays sandboxed". Excluded commands still need permission, and the pre-approved allow rule gives it.

**MCP removed.** `--disallowedTools=mcp__*` removes every MCP tool ("`"mcp__*"` removes every MCP tool", cli-reference). `disableClaudeAiConnectors: true` stops Claude Code fetching the claude.ai connectors at all ("To turn off the connectors it fetches, set the setting to `true` in any settings scope", https://code.claude.com/docs/en/mcp.md#disable-claude-ai-connectors). This matters more in deep mode: "a background subagent keeps every MCP tool" the main conversation has (sub-agents.md, Available tools). Without the removal, every unattended spike could reach Gmail and Drive. The docs do not say whether `--strict-mcp-config` covers claude.ai connectors, so the two settings above are the reliable pair. Plain `explore` has the same exposure today (finding 1).

**Known friction on macOS:**

- Python process pools have failed in this sandbox in this repo's own runs: "`PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`" (`docs/plans/202611041013-rspec-controller-skill/PLAN-001.md:262`, `docs/plans/202611031255-rspec-test-skill/PLAN-001.md:239`). Parallel test runners in spikes may hit the same problem and fall back to an unsandboxed rerun prompt.
- "Tools such as `gh`, `gcloud`, and `terraform` may fail TLS verification under Seatbelt". `docker` "is incompatible with the sandbox". `jest` needs `--no-watchman` (sandboxing.md).
- The sandbox "is not a complete isolation boundary". Its proxy checks hostnames without inspecting TLS (sandboxing.md, Security limitations). With an empty allowlist, that matters little.
- This repo has no managed settings file (`docs/plans/202610301614-obserability-of-commands/PLAN-002.md:176`). Under an admin-required sandbox, a CLI `--settings` value would still apply. Only the repository's settings are ignored (sandboxing.md).

```mermaid
flowchart TB
  subgraph outside["Outside the sandbox (permission rules only)"]
    WS["WebSearch (allowed)"]
    WF["WebFetch (bare allow)"]
    RW["Read / Write / Edit"]
    PUSH["git push -u origin prefix-* (excluded + allowed)"]
  end
  subgraph sandbox["Sandbox: writes in cwd + temp, network: none"]
    BASH["spike Bash: git commit, tests, …<br/>auto-allowed"]
    INST["installs → ask rule → unsandboxed rerun prompt"]
  end
  MCP["MCP tools + claude.ai connectors"]:::off
  classDef off stroke-dasharray: 5 5
```

### 9. Suggested build plan

These are the capability steps. Finding 12 turns them into an ordered list of iterations with files and checks.

```mermaid
flowchart TD
  s1["1. --deep flag + deep prompt + sandbox/MCP settings<br/>WebSearch, Bash, Agent; clarify → go → unattended;<br/>90-min clock; research subagents, no code"] --> s2["2. spike subagent via --agents<br/>isolation: worktree, baseRef head,<br/>first-free prefix-NNN, install ask rules"]
  s2 --> s3["3. Pre-approved, excluded push of prefix-*<br/>Branches table + Cleanup block<br/>.gitignore .claude/worktrees/"]
  s3 --> s4["4. Same MCP removal for plain explore (optional)"]
  s4 --> s5["5. Worktree skill hook<br/>spike `skills:` from the catalog"]
```

1. **`--deep`, the deep prompt and the security baseline.** Parse the flag, add the template and partials, and add `WebSearch,Bash,Agent,Skill` to the agent call. From day one, pass `--disallowedTools=mcp__*` and a `--settings` blob with the sandbox (enabled, auto-allow, unsandboxed reruns allowed, empty allowlist) and `disableClaudeAiConnectors`. Bash must never be on without the sandbox. The prompt has a clarify phase ending in an explicit "go", an unattended phase using the built-in `Explore` subagent for research (no code), the `date`-based 90-minute limit, and the existing findings and check-in format. Specs as in finding 2.
2. **Spike subagents.** Add `branch_prefix` in Ruby. Add the `--agents` `spike` definition: `isolation: worktree`, `tools`, the model, `maxTurns`, and a prompt covering `git switch -c <branch>`, commit discipline, reporting its worktree path and commit, and "never install without asking". Add `worktree.baseRef: "head"` and the install `ask` rules to `--settings`. The main agent picks the first free `<NNN>` and passes `isolation: "worktree"` on each call. Try the checks in finding 11.
3. **Branches out.** Add `Bash(git push -u origin <prefix>-*)` to `--allowedTools` and to `sandbox.excludedCommands`, and `GIT_TERMINAL_PROMPT=0` to `--settings` `env`. Push at the end, add the Branches table and Cleanup block to the deep findings structure, and record blocked pushes under stats without cleaning up. `.gitignore` gets `.claude/worktrees/`.
4. **Plain explore.** Optionally give plain `explore` the same MCP removal.
5. **Worktree skill.** When a worktree skill ships in `lib/planner/skills`, add it to the spike's `skills` list.

A later, separate iteration could add a headless `--bg` or `-p` variant, which gets the hard caps (`--max-budget-usd`, `--max-turns`).

### 10. Draft of the deep `claude` call

For a plan folder `docs/plans/202611141235-longer-unintended-explore-sessions` (prefix `longer-unintended-explore-sessions`). Flag names are from the CLI reference. Settings keys are from sandboxing.md, worktrees.md, mcp.md and permissions.md.

```text
claude --model opus
  --tools=Read,Grep,Glob,Write,Edit,WebFetch,WebSearch,Bash,Agent,Skill
  --allowedTools=Edit(<findings>),Edit(<toc>),WebFetch,WebSearch,Bash(git push -u origin longer-unintended-explore-sessions-*)
  --disallowedTools=mcp__*
  --settings '<settings JSON>'
  --agents '<agents JSON>'
  '<prompt>'
```

`Edit` is in the main `--tools` so spikes can inherit it. Subagents inherit "the built-in tools … available in the main conversation". The main agent's edits are still limited by `--allowedTools`: without a matching allow rule, an edit outside the findings and toc files prompts. Spikes edit freely only inside their worktree, which is the case to confirm in finding 11.

```json
{
  "env": { "GIT_TERMINAL_PROMPT": "0" },
  "disableClaudeAiConnectors": true,
  "worktree": { "baseRef": "head" },
  "permissions": {
    "ask": [
      "Bash(bundle install *)", "Bash(bundle add *)", "Bash(gem install *)",
      "Bash(npm install *)", "Bash(yarn add *)", "Bash(pip install *)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": true,
    "excludedCommands": ["git push -u origin longer-unintended-explore-sessions-*"],
    "network": { "allowedDomains": [] }
  }
}
```

```json
{
  "spike": {
    "description": "Builds one approach to the brief in its own worktree and branch, then reports.",
    "prompt": "<spike rules: switch to the given branch, build and test the approach, commit, never install without asking, never remove worktrees or branches, report worktree path, branch, last commit and what was learned>",
    "tools": ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "WebFetch", "WebSearch"],
    "model": "inherit",
    "maxTurns": 200,
    "isolation": "worktree"
  }
}
```

Planner builds both JSON blobs in Ruby with `JSON.generate` and passes them as single argv entries, as `Agents::Claude` already does for every flag (`claude.rb:38-41`), so no shell quoting is involved. The `maxTurns` value is a placeholder.

### 11. The open checks, settled from the docs

| Check | Answer | Evidence |
| --- | --- | --- |
| Is `Agent` the name to put in `--tools`? | Yes. The tool table lists `Agent`, which "Spawns a subagent", with no approval needed. Permission rules can target a type with `Agent(<name>)`, for example `Agent(Explore)` | tools-reference, tool table and rule-format table |
| Does the spike get `Bash`? | Yes, as long as the parent has it. Subagents "inherit the built-in tools … available in the main conversation". `tools` narrows that set, and "a tool that isn't available to subagents is never granted, even when listed in `tools`". Background subagents keep `Bash`, `Edit`, `Write`, `WebFetch` and `WebSearch`. Deep mode puts `Bash` in the parent's `--tools`, so the question doesn't arise | sub-agents.md, Available tools; tools-reference, Agent tool behavior |
| Does `Bash(bundle install *)` match a bare `bundle install`? | Yes: "A `*` at the end, with a space before it, also matches the bare command" | permissions.md, Wildcard patterns |
| Does an env prefix break the push rule? | Yes, for allow rules: "An allow rule won't match past an assignment of any other variable". Set `GIT_TERMINAL_PROMPT=0` through `--settings` `env` instead. Ask and deny rules match past any assignment | permissions.md, Bash |

New caveats found while checking:

- **Background subagents keep every MCP tool** the parent has. This is now a reason for the MCP removal in finding 8, not just a precaution.
- **Agent teams can bypass the frontmatter's `isolation`** for named spawns. Pass `isolation` on the call (finding 3).
- **To try out while building, since docs can't settle these:** that `.claude/worktrees/<name>` is writable inside the sandbox (finding 4). That a background spike's install prompt and unsandboxed-rerun prompt both reach the main session. That the excluded push pattern matches with the `-u origin <branch>` text exactly as the agent writes it. That the project's test runner works under Seatbelt (finding 8).

### 12. Draft order for the implementation

Each item is one planner iteration in this folder: an `ITERATION-<NNN>.md` brief, then `planner plan`, `planner review` and `planner run`. Every item leaves `planner explore` working and shippable, and plain `explore` never changes behaviour until item 5. Numbers continue from this brief, so the first is `ITERATION-002.md`. They are a suggestion: nothing here is decided until a plan records it.

```mermaid
flowchart LR
  i2["002 Partials refactor<br/>(no behaviour change)"] --> i3["003 --deep, research only<br/>+ sandbox / MCP baseline"]
  i3 --> i4["004 Spike subagents<br/>in worktrees"]
  i4 --> i5["005 Push, Branches,<br/>Cleanup, .gitignore"]
  i5 --> i6["006 Optional follow-ups<br/>plain explore MCP, worktree skill, headless"]
```

**1. `ITERATION-002`: split the explore prompt into partials.** Pure refactor, with no behaviour change.
- Move Findings structure, Check-in, Stats, the Table of contents wrapper and Summary for the user out of `lib/planner/prompts/explore.md.erb` into partials, following `_table_of_content.md.erb`. Render them from `Commands::Explore#prompt` (`lib/planner/commands/explore.rb:43-50`).
- Verify: `spec/planner/commands/explore_spec.rb` passes unchanged. The rendered prompt is byte-identical to before; add a spec, or compare `planner run --print`-style output by hand.
- Why first: item 3 needs the shared sections, and doing it separately keeps item 3's diff about behaviour only. Findings 2.

**2. `ITERATION-003`: `--deep` with research subagents and the security baseline.**
- `Commands::Explore`: parse `--deep`, choose `explore_deep.md.erb`. `Agents::Claude#explore`: `deep:` keyword. The deep argv has the tools from finding 10 except spike-specific parts: `--tools` with `WebSearch,Bash,Agent,Skill,Edit`, `--allowedTools` with `WebSearch`, `--disallowedTools=mcp__*`. `--settings` carries `disableClaudeAiConnectors` and the `sandbox` block, without `excludedCommands` yet.
- `explore_deep.md.erb`: the intro, Rules (repository read-only for the main agent, web as data, never install, sandbox reruns only for approved installs, never remove worktrees or branches), and Steps. Steps are: read the folder, clarify, wait for an explicit "go", start the clock with `date`, research through the built-in `Explore` subagent, write, check in. The shared partials come from item 1.
- Also: `FakeAgent`, `explore_spec.rb` (a `--deep` group), `claude_spec.rb` (full deep argv), `CLI::USAGE`, README, GLOSSARY.
- Manual check: run `planner explore --deep` on a small brief. `/status` shows the sandbox on and `Command line arguments` among the setting sources. No `mcp__` tools are listed. WebSearch and WebFetch work. A sandboxed `curl https://example.com` fails. The session runs without prompts after "go". Findings 1, 2, 7, 8.

**3. `ITERATION-004`: spike subagents in worktrees.**
- `Commands::Explore#branch_prefix` and its specs (stamped and unstamped folders). Pass `branch_prefix` to the template and the agent.
- `--agents` JSON for `spike` (finding 10), built with `JSON.generate`. `--settings` gains `worktree.baseRef: "head"` and the install `ask` rules.
- Prompt: choosing approaches, first free `<NNN>` numbering (finding 5), spawning `spike` with `isolation: "worktree"` on the call, and what each spike passes in and gets back. Also the spike prompt itself: `git switch -c`, commit, report worktree path, branch, commit and lessons.
- Manual check: a brief with two approaches. Two worktrees appear under `.claude/worktrees/`, on `<prefix>-001` and `<prefix>-002`, both based on local `HEAD` and holding the `ITERATION` file. `git commit` and the test suite run sandboxed without prompts. A `bundle add` triggers the ask prompt and then the rerun prompt in the main session. Nothing is written in the main checkout except the findings. These are the hands-on checks from finding 11. Findings 3, 4, 5, 6, 11.

**4. `ITERATION-005`: pushing, the Branches table and cleanup.**
- `--allowedTools` and `sandbox.excludedCommands` gain `Bash(git push -u origin <prefix>-*)`. `--settings` `env` gains `GIT_TERMINAL_PROMPT=0`.
- The deep findings structure gains `## Branches` and `### Cleanup` (finding 5). Blocked pushes go to the Branches table and "Commands that needed help", with nothing cleaned up.
- `.gitignore` gains `.claude/worktrees/`.
- Manual check: pushes reach `origin` with no prompt. Add a user-level `deny` for `Bash(git push *)` and rerun: the push is reported as blocked, and the worktree and branch stay. The Cleanup commands, run by hand, remove everything. Findings 4, 5, 8.

**5. `ITERATION-006` and later: optional follow-ups, in any order.**
- Plain `explore` gets `--disallowedTools=mcp__*` and `disableClaudeAiConnectors` (finding 8).
- When a worktree skill ships in `lib/planner/skills`, add it to the spike's `skills` list (finding 3).
- A headless `--bg` or `-p` variant with `--max-budget-usd` and `--max-turns` (finding 7).

---

## Stats

| Field | Value |
| --- | --- |
| Model | opus |
| Tokens | ~260k (estimate) |

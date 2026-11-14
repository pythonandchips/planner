# PLAN-006 — Push deep explore spike branches and list cleanup

At the end of each unattended phase, the deep explore main agent pushes every spike branch with a
pre-approved `git push -u origin <prefix>-<NNN>` that runs outside the sandbox. A push that is refused or
fails is reported and nothing is cleaned up. The findings gain a Branches section with cleanup commands
for the user to run. `.gitignore` ignores `.claude/worktrees/`. Part of PLAN-002 (step 4), from
FINDINGS-001 findings 4, 5, 8 and 12 item 4.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Push approval | `Bash(git push -u origin <prefix>-*)` in `--allowedTools` |
| Push and the sandbox | `git push -u origin <prefix>-*` in `sandbox.excludedCommands` |
| Git credentials | `GIT_TERMINAL_PROMPT=0` in `--settings` `env` |
| When to push | At the end of each unattended phase, one plain Bash call per branch, from the main checkout |
| Blocked or failed push | Recorded in the Branches section and "Commands that needed help". Worktree and branch left as they are |
| Cleanup | Commands written in the findings' Branches section. The agent never runs them |
| `.gitignore` | Add `.claude/worktrees/` |
| Commit | Yes |

## Files to create / change

- `lib/planner/agents/claude.rb`
- `lib/planner/prompts/explore_deep.md.erb`
- `spec/planner/commands/explore_spec.rb`
- `spec/planner/agents/claude_spec.rb`
- `README.md`
- `.gitignore`

## Implementation

### `lib/planner/agents/claude.rb`

Replace `explore_deep` with:

```ruby
def explore_deep(prompt, model:, findings_file:, toc_file:, branch_prefix:)
  push = "git push -u origin #{branch_prefix}-*"
  @executor.call('claude', '--model', model, "--tools=#{EXPLORE_DEEP_TOOLS}",
                 "--allowedTools=Edit(#{findings_file}),Edit(#{toc_file}),WebFetch,WebSearch,Bash(#{push})",
                 '--disallowedTools=mcp__*', "--settings=#{JSON.generate(deep_settings(push))}",
                 "--agents=#{JSON.generate(spike: SPIKE_AGENT)}", prompt)
end
```

Remove any `_ = branch_prefix` line PLAN-005 added.

Replace `deep_settings` with:

```ruby
# Settings for a deep explore: git never prompts for credentials, no claude.ai connectors, worktrees from
# local HEAD, installs that always ask, and Bash sandboxed with no network apart from the push.
def deep_settings(push)
  { env: { GIT_TERMINAL_PROMPT: '0' }, disableClaudeAiConnectors: true, worktree: { baseRef: 'head' },
    permissions: { ask: INSTALL_COMMANDS.map { |command| "Bash(#{command} *)" } },
    sandbox: { enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: true,
               excludedCommands: [push], network: { allowedDomains: [] } } }
end
```

### `lib/planner/prompts/explore_deep.md.erb`

Replace rule 3 (from `3. Use Bash only` to `` `git log` and `git status`. ``) with:

````
3. Use Bash only for commands that change nothing,
   such as `date`, `git log` and `git status`, and
   for the pushes in step 5.
````

Replace step 5 (from `5. **Keep to the time limit.**` to `finish, then go on to step 6.`) with:

````
5. **Keep to the time limit, then push.** Before
   you start each new subagent or round of
   research, run `date -u +%Y-%m-%dT%H:%M:%SZ`. Once
   90 minutes have passed since the start of this
   phase, start nothing new. Wait for running
   subagents to finish. Then push every spike
   branch made in this phase from this checkout,
   one Bash call per branch, written exactly
   `git push -u origin <branch>` with nothing before
   or after it. If a push is refused or fails,
   record the error in the Branches section and
   under "Commands that needed help", and leave its
   worktree and branch as they are. Then go on to
   step 6.
````

Replace the line `<%= findings_structure %>` with:

`````
<%= findings_structure %>

When this session made spike branches, add a
`## Branches` section after `## Findings`, listing
every spike branch from every phase:

```markdown
## Branches

| Branch | Spike | Worktree | Last commit | Pushed |
| --- | --- | --- | --- | --- |
| <%= branch_prefix %>-<NNN> | <approach> | <worktree path> | <sha> <subject> | Yes / No: <reason> |

### Cleanup

Run these when you are done with the spikes. Nothing has been removed.

    git worktree unlock <worktree path>      # only if git says it is locked
    git worktree remove --force <worktree path>
    git branch -D <%= branch_prefix %>-<NNN>
    git push origin --delete <%= branch_prefix %>-<NNN>   # only for pushed branches
```

Write one set of Cleanup commands per branch. The
commands are for the user to run: never run them
yourself.
`````

### `spec/planner/commands/explore_spec.rb`

Add to the end of `describe 'the deep prompt'`:

```ruby
it 'pushes the spike branches and lists them with cleanup commands' do
  expect(prompt).to include('`git push -u origin <branch>` with nothing before',
                            '`## Branches` section after `## Findings`, listing', 'git branch -D x-<NNN>',
                            'never run them')
end
```

### `spec/planner/agents/claude_spec.rb`

In `describe 'deep exploring'`:

- In the first example, the `--allowedTools` entry becomes
  `'--allowedTools=Edit(d/FINDINGS-001.md),Edit(d/TABLE-OF-CONTENT.md),WebFetch,WebSearch,Bash(git push -u origin x-*)'`,
  wrapped to stay within 120 characters. Its description becomes
  `'runs claude with web search, a shell and subagents, the findings and toc editable and the push allowed'`.
- Replace the settings example with:

  ```ruby
  it 'stops git prompting, turns off connectors, asks before installs and sandboxes all but the push' do
    expect(JSON.parse(argv[6].delete_prefix('--settings='))).to eq(
      'env' => { 'GIT_TERMINAL_PROMPT' => '0' },
      'disableClaudeAiConnectors' => true, 'worktree' => { 'baseRef' => 'head' },
      'permissions' => { 'ask' => ['Bash(bundle install *)', 'Bash(bundle add *)', 'Bash(gem install *)',
                                   'Bash(npm install *)', 'Bash(yarn add *)', 'Bash(pip install *)'] },
      'sandbox' => { 'enabled' => true, 'autoAllowBashIfSandboxed' => true, 'allowUnsandboxedCommands' => true,
                     'excludedCommands' => ['git push -u origin x-*'], 'network' => { 'allowedDomains' => [] } }
    )
  end
  ```

### `README.md`

In the `planner explore` line, replace `then checks in as usual.` with:

```
then pushes those branches to `origin`, lists them in the findings with the commands to clean them up, and checks in as usual.
```

### `.gitignore`

Add a last line:

```
.claude/worktrees/
```

## Verification

1. `bundle exec rake` passes.

## Commit

Commit only after the change is made and Verification passes. Stage:

- `lib/planner/agents/claude.rb`
- `lib/planner/prompts/explore_deep.md.erb`
- `spec/planner/commands/explore_spec.rb`
- `spec/planner/agents/claude_spec.rb`
- `README.md`
- `.gitignore`
- `docs/plans/202611141235-longer-unintended-explore-sessions/PLAN-006.md`

Suggested commit message:

```
Push deep explore spike branches and list how to clean them up

At the end of each unattended phase the agent pushes every spike branch
with a pre-approved push that runs outside the sandbox. A push that
fails is reported and nothing is cleaned up. The findings list the
branches with the commands to remove them, and .gitignore ignores
.claude/worktrees/.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-14T16:53:03Z |
| Finished | 2026-11-14T16:53:24Z |
| Elapsed | 21s |
| Model | sonnet |
| Tokens | ~40k (estimate) |

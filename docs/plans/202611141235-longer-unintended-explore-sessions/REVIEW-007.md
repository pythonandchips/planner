# REVIEW-007 — docs/plans/202611141235-longer-unintended-explore-sessions/PLAN-007.md

## Summary

The plan matches the code well. Every file, constant, method, spec example and prompt passage it names exists.
Each "replace from X to Y" anchor in `explore_deep.md.erb` matches exactly one passage. Every string the new and
existing specs look for will be in the rendered prompt, and the new argv indexes are right. One problem will
stop Verification passing: adding the new subagent pushes `Planner::Agents::Claude` over RuboCop's default
100-line class limit, and `bundle exec rake` runs RuboCop. The no-worktree mode also leaves a few risky git
operations unaddressed.

## High-confidence findings

1. **`bundle exec rake` will fail on `Metrics/ClassLength`.** `Rakefile:10` runs `spec` and `rubocop`.
   `.rubocop.yml` does not change `Metrics/ClassLength`, so the default limit of 100 applies, and nothing in
   `lib/` disables it. By my count the class body in `lib/planner/agents/claude.rb:9-124` has about 96 lines
   that RuboCop counts. Heredoc lines count, blank lines and comments do not. The plan adds
   `SPIKE_ON_BRANCH_PROMPT` (21 counted lines), `SPIKE_ON_BRANCH_AGENT` (5) and one more line in
   `explore_deep`. That brings the class to about 123 lines. The plan does not say how to handle this, so the
   developer would have to decide alone. One option is to move the two spike prompts and agent hashes into
   their own module or file, such as `lib/planner/agents/claude/spikes.rb`, and reference them from `Claude`.
   Another is to add a scoped `# rubocop:disable Metrics/ClassLength`. If the constants move, the spec's
   `described_class::SPIKE_PROMPT` and `described_class::SPIKE_ON_BRANCH_PROMPT` references need to change
   too, unless `Claude` keeps aliases for them.

   **Applied:** The plan now moves all four spike constants into a new `Planner::Agents::ClaudeSpikes` module in `lib/planner/agents/claude_spikes.rb`, which `Claude` includes and `lib/planner.rb` requires, so the spec references stay as they are.

## Lower-confidence concerns

1. **"Any command inside the sandbox" lets the agent run commands that throw away work.** The new rule 3 and
   the "Working without worktrees" section stop the agent removing branches and pushing. They do not stop it
   running `git clean`, `git reset --hard`, `git checkout -- <path>`, `git restore` or `git stash` in the
   user's main checkout. Item 6 tells the agent to keep going until `git status --porcelain` shows nothing
   outside the plan folder. An agent stuck on an untracked artefact could reach for `git clean -fd`, which
   would also delete untracked files in the plan folder, such as the untracked `ITERATION-007.md` right now.
   With `autoAllowBashIfSandboxed: true` (`lib/planner/agents/claude.rb:122`), nothing would prompt. Consider
   one line forbidding commands that discard changes or untracked files, and forbidding commits on the
   starting branch.

   **Applied:** Added item 7 to "Working without worktrees", which forbids `git clean`, `git reset --hard`, `git checkout -- <path>`, `git restore`, `git stash` and commits on the starting branch. "Never push." became item 8, and the Decisions row and spec strings were updated to match.
2. **Items 5 and 6 can commit test artefacts onto the spike branch.** If a test run creates untracked files
   that `.gitignore` does not cover, item 6 makes the agent commit them, because it must reach a clean
   status before switching back and it may not remove files. That is probably acceptable for throwaway
   branches, but the plan does not say so.
3. **Asking the user to "stash" will not clear untracked files.** Step 2 asks the user to "commit or stash"
   changes outside the plan folder. A plain `git stash` leaves untracked files behind, and
   `git status --porcelain` still lists them as `??`, so the agent will keep asking. Saying
   `git stash -u`, or "commit, stash or remove", would avoid that loop.

   **Applied:** Step 2 and the "Dirty checkout" Decisions row now say to commit the changes or stash them with `git stash -u`, and the spec checks for that wording.
4. **`--permission-mode=acceptEdits` takes away the edit prompt in worktree mode too.** Today, the
   `--allowedTools=Edit(<findings>),Edit(<toc>)` list (`lib/planner/agents/claude.rb:76`) means any other
   edit by the main agent prompts the user. With `acceptEdits`, the only guard on repository edits in
   worktree mode is the prompt's rule 1. The Decisions table accepts this ("The prompt keeps worktree mode
   read-only"), so this is only a note that a real guard goes away in a mode that did not need to lose it.
5. **One spec line may be right at the 120-character limit.** In the new `'defines the spike subagent ...'`
   example, the `'Takes one task about the brief on its own branch in the main checkout, then reports.',`
   line lands at about column 120 once it is indented inside `describe 'deep exploring'`. The plan only
   says "Wrap any line over 120 characters", which RuboCop will enforce anyway. The `it` line itself is
   fine, because `Layout/LineLength` ignores the trailing `rubocop:disable` comment by default.
6. **Step 4 is worded for `spike` only.** "When a spike reports a worktree path, branch or commit, cite it
   as evidence" (new step 4) does not mention `spike_on_branch`, which reports a branch and commit but no
   worktree. The `## Branches` row template does cover it ("worktree path, or main checkout"), so the risk
   is small.

## Top recommendations

1. Say in the plan how to keep `Planner::Agents::Claude` under `Metrics/ClassLength`, by moving the spike
   prompts and agents to their own module or by adding a scoped disable, and update the spec references to
   match.

   **Applied:** The spike constants now go in a new `ClaudeSpikes` module that `Claude` includes, with a `require_relative` line added to `lib/planner.rb`.
2. Add a no-worktree rule forbidding `git clean`, `git reset --hard`, `git checkout -- <path>`,
   `git restore` and stashing, and forbidding commits on the starting branch.

   **Applied:** Added item 7 to "Working without worktrees", with matching Decisions and spec updates.
3. Change "commit or stash" in step 2 to cover untracked files, for example `git stash -u`.

   **Applied:** Step 2 and the Decisions row now say to stash with `git stash -u`.

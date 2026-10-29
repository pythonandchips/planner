# REVIEW-002 — docs/plans/202610271623-run-command-improvements/PLAN-002.md

## Summary

The plan is accurate about the code and its steps are in a workable order. The file names, line numbers, the spec group, the README line and the TODO bullet all match what is in the repository. Two things will cause trouble as written. Three of the new spec strings use double quotes where RuboCop expects single quotes, so Verification step 1 will fail. The folder-wide `git add` will also stage this review file, but the plan says it stages only `ITERATION-002.md` and `PLAN-002.md`.

## High-confidence findings

1. **Three new spec strings will fail RuboCop, so Verification step 1 fails.**
   PLAN-002.md lines 163, 166 and 168 give these strings in double quotes:
   - `"Before anything else, run `date -u +%Y-%m-%dT%H:%M:%SZ`"`
   - ``"stage `PLAN-001.md` with the commit"``
   - ``"top of `PLAN-001.md`, above everything already"``

   None of them has interpolation, an escape or a single quote. `.rubocop.yml` doesn't override `Style/StringLiterals`, so the default `single_quotes` style applies and RuboCop reports each one. The existing specs follow that style: every double-quoted string in `spec/` has `\n`, `#{}` or an apostrophe in it (for example `spec/planner/commands/run_spec.rb:11` and `:34`). The `rake` task runs RuboCop without autocorrect (`Rakefile:8-10`), so `bundle exec rake` fails. The run prompt's rule 4 then tells the agent to stop, and rule 2 tells it not to change the wording. The other new strings are fine: they either contain `\n` or are already single-quoted.
   **Fix:** write those three strings in single quotes in the plan.

2. **`git add docs/plans/202610271623-run-command-improvements` stages more than the plan says.**
   PLAN-002.md line 222 stages the whole folder. Lines 225-226 say this stages "this folder's `ITERATION-002.md` and `PLAN-002.md`". This review file (`REVIEW-002.md`) will also be untracked in that folder when the plan runs, so it gets staged and committed too. So does anything else left in the folder, such as a commit-message file written there (see concern 3).
   **Fix:** either name the files (`.../ITERATION-002.md .../PLAN-002.md`), or say on purpose that the review is committed as well.

## Lower-confidence concerns

1. **The agent may not be able to tell when a permission prompt was approved.** (PLAN-002.md line 25; template lines 92-97)
   In an interactive `claude` session, a command the user approves at a prompt usually comes back to the agent like any other successful command. The agent sees denials and sandbox failures, but probably not approvals. If so, the "needed the user to approve a permission prompt" category will be under-reported, and that is the main thing the table is meant to capture. Consider saying that this category is best effort, or confirm how Claude Code reports approvals before relying on it.

2. **A "Completed" summary is written before the commit, and the commit can fail.** (PLAN-002.md line 23; template rule 6, lines 83-88)
   The summary is written with Status `Completed` before the Commit step runs. If `git add` or `git commit` then fails, the plan file still says `Completed` even though nothing was committed. The organisation's call-shape rules make git failures in this environment fairly likely. The plan doesn't say whether the agent should change the summary to `Stopped` at that point, and rule 3 ("most literal reading") means it won't.

3. **Where to write the commit-message file isn't specified.** (PLAN-002.md lines 226-227)
   "Write the message to a file" doesn't say where the file goes. If the agent writes it inside the repo after `git add`, it is left behind as an untracked file. If it writes it inside the plan folder before `git add`, it gets committed. Naming a temporary location (for example `$TMPDIR`) would remove the guesswork.

4. **Verification doesn't check the stop path or the "no commands" path.** (PLAN-002.md lines 204-214)
   The specs only check that the right text is in the prompt. This is in line with PLAN-001's key-content approach. Nothing checks how the agent behaves: on a stop, with no commands needing help, or that the plan file's original content is unchanged below the summary. The decisions leave all of that to the manual smoke check in step 3. That is acceptable, but the user should know that step 3 is the only real proof the feature works.

5. **The rendered summary pushes the plan's `# PLAN-<N>` heading off the first line.** (template lines 99-102)
   No code reads a plan's first line (`lib/planner/commands/review.rb:8` checks only the file name), so nothing breaks today. But `lib/planner/prompts/plan.md.erb:8-11` and `:26` tell the plan agent to read earlier `PLAN-*.md` files and match their convention. A later plan agent might copy the `## Run summary` block or get confused by it. This is a low risk because the plan prompt gives an explicit structure.

## Top recommendations

1. Change the three double-quoted spec strings (PLAN-002.md lines 163, 166, 168) to single quotes so `bundle exec rake` passes.
2. Make the `git add` in the Commit section name the exact files, or say that `REVIEW-002.md` is committed on purpose.
3. Say where the commit-message file goes (for example `$TMPDIR`).
4. Decide what the summary should say if the commit fails after a `Completed` summary has been written.

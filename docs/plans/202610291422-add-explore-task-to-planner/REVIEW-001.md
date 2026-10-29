# REVIEW-001 — docs/plans/202610291422-add-explore-task-to-planner/PLAN-001.md

## Summary

The plan is accurate and ready to carry out. Every file, method, constant, comment and spec it
refers to exists and does what the plan says. The new command copies `Commands::Review` closely,
the specs follow `review_spec.rb`, and the code samples look RuboCop-clean. There is one real
problem: the `-m sonnet` re-run in Verification step 2 will fail as written, because Ruby treats
`-m` as its own option. There are also a few small gaps in Verification and in the Commit
section.

Claims checked against the code:

- `Commands::Review` (`lib/planner/commands/review.rb:14-65`): the `call` shape, the
  `review_file` suffix loop (lines 30-39) and `parse` (lines 55-65) match what `Explore` copies.
- `Commands::Plan` (`lib/planner/commands/plan.rb:8,19-20,29-30`): the `ITERATION_NAME` regex,
  the two error messages in the order the plan gives, `%03d` zero-padding, and ERB with no
  `trim_mode` all match.
- `Agents::Claude` (`lib/planner/agents/claude.rb:5-6,11,25-28,34-36`): the interface comment,
  `REVIEW_TOOLS`, `#review` and `#default_review_model` sit where the plan says. The new
  `#explore` is the same as `#review` except for the argument name.
- `CLI` (`lib/planner/cli.rb:6-20`): `COMMANDS` and `USAGE` are as described, and the review line
  is at line 18.
- `lib/planner.rb:18` requires `planner/commands/review`, so the new require can go straight
  after it.
- `spec/spec_helper.rb:22-32` has `FakeAgent#review` and `#default_review_model` where the plan
  says.
- `spec/planner/agents/claude_spec.rb:31` has the "defaults the review model to opus" example,
  and `spec/planner/cli_spec.rb:34` has the "raises Error" example.
- README line 20 is the `planner review` bullet. `docs/GLOSSARY.md:6` is the **review file**
  entry.
- `planner.gemspec:17` already packages `lib/**/*.erb`, so the new template ships with the gem
  without any gemspec change.
- `.rubocop.yml` uses the default 120-character line length. The longest lines in the plan's
  code (`explore_spec.rb` lines 386 and 391 of the plan, about 117 and 110 characters) fit.

## High-confidence findings

1. **Verification step 2: the `-m sonnet` re-run fails as written** (PLAN-001.md lines 493 and
   498-499). The command is `ruby -Ilib -rplanner -e '…' <file>`, and step 2 says to run it again
   "with `-m sonnet` before the file". Ruby keeps reading its own switches after the `-e` script
   until it reaches a non-option argument or `--`. So `ruby … -e '…' -m sonnet <file>` hands
   `-m` to Ruby, not to `ARGV`, and Ruby exits with "invalid option -m". The `-m` check (Model
   row and second-to-last line read `sonnet`) can't pass. Fix: put `--` after the `-e` script,
   e.g. `ruby -Ilib -rplanner -e '…' -- -m sonnet docs/plans/…/ITERATION-001.md`, and write the
   full command out instead of describing the change in words.

## Lower-confidence concerns

1. **The Commit section leaves out this review file** (PLAN-001.md line 507). The `git add`
   stages `ITERATION-001.md` and `PLAN-001.md` but not `REVIEW-001.md`. Earlier plan folders
   include REVIEW files (for example
   `docs/plans/202610281426-add-review-sub-command/REVIEW-002.md` and
   `docs/plans/202610271623-run-command-improvements/REVIEW-002.md`). If those were committed,
   this one will be left untracked after the run. The plan should say whether it is staged.
2. **Nothing exercises `planner explore` through the real executable.**
   `spec/exe/planner_spec.rb:34-39` has an end-to-end "reports a missing iteration file" example
   for `plan`, but the plan adds none for `explore`. The CLI dispatch spec
   (`spec/planner/cli_spec.rb`, new example) covers the dispatch path with a `FakeAgent`, so this
   is a small gap. One `planner('explore', 'ITERATION-001.md')` example would cover the require
   in `lib/planner.rb` and the `COMMANDS` entry together.
3. **The new usage line is not checked anywhere.** The specs compare stderr with
   `described_class::USAGE` (`spec/planner/cli_spec.rb:16`, `spec/exe/planner_spec.rb:16`), so a
   typo or misaligned `planner explore …` line would still pass. Verification could add a check
   that `bundle exec exe/planner` with no args prints the explore line.
4. **Asking questions with a restricted tool set.** `--tools=Read,Grep,Glob,Write`
   (`lib/planner/agents/claude.rb:11`, reused for explore) leaves out any question-asking tool.
   The prompt's central step is "Resolve every open question before writing anything", so the
   agent will have to ask in plain text and wait for the user's reply. That should work in an
   interactive session, but `review` never needed to ask, so this setup hasn't been tried for
   asking questions. Nothing in Verification checks it, and a short manual run would.
5. **"Or data" with no Bash.** The prompt says to explore "the codebase or data", but with no
   Bash the agent can only read data that lives in files. The no-Bash decision is settled. The
   only risk is that users expect queries or scripts to work, and the README bullet repeats
   "code or data" without mentioning this limit.
6. **USAGE indentation wording** (PLAN-001.md line 268). The plan gives the line as 7 spaces
   plus text. That is right for the text after `<<~` strips the indent, but in the source file
   the line needs 13 spaces (6 for the heredoc plus 7), as at `lib/planner/cli.rb:16-19`. "Aligned
   with the other lines" covers this, so a developer is unlikely to get it wrong.

## Top recommendations

1. Rewrite the Verification step 2 re-run as a full command with `--` before `-m sonnet`.
2. Say whether `REVIEW-001.md` is staged in the Commit section's `git add`.
3. Optionally add a `spec/exe/planner_spec.rb` example for `planner explore ITERATION-001.md`,
   which also covers the require and the `COMMANDS` entry.

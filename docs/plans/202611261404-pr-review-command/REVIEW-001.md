# REVIEW-001 — docs/plans/202611261404-pr-review-command/PLAN-001.md

## Summary

The plan is accurate and detailed. Its claims about the code match: `Commands::Next`, `CLI::COMMANDS`/`USAGE`,
the require list in `lib/planner.rb`, `FakeAgent`, the GLOSSARY entry and both TODO lines are all where and
what the plan says. The steps are in a workable order and the worked `to_markdown` example matches the rules
given for it. The gaps are small: a pending-review loophole in the inline threads, a staging list that leaves out
this review file, and a few RuboCop and spec details the implementer will run into.

## High-confidence findings

- **PLAN-001.md:408 — the staging list leaves out `REVIEW-001.md`.** The Commit section stages
  `docs/plans/202611261404-pr-review-command/` but says in brackets that this means `ITERATION-001.md` and
  `PLAN-001.md`. This review now adds `REVIEW-001.md` to the folder, so the runner has to guess whether to stage
  it. Say explicitly whether `REVIEW-001.md` is staged (staging the whole folder is the simplest reading).

  **Applied:** The staging list now stages the whole plan folder, naming `ITERATION-001.md`, `PLAN-001.md` and `REVIEW-001.md`.

- **PLAN-001.md:143-146, 171-172 — inline comments from a pending review are not filtered out.** The Decisions
  table (line 22) leaves out pending reviews, but the filter only checks review `state` on `reviews`. GitHub
  returns the viewer's own pending (unsubmitted) inline comments inside `reviewThreads`, so a user who has
  started but not submitted a review on the PR would get those draft comments written to the iteration file.
  Add `state` to the thread comment nodes (`nodes { author { login } body state }`; `PullRequestReviewComment.state`
  is `PENDING` or `SUBMITTED`), drop comments whose state is `PENDING` with the blank ones, and add a spec example
  for it.

  **Applied:** Added a "Pending inline comments" decision, `state` on thread comment nodes in `QUERY`, a `PENDING` filter on thread comments, a `comment(..., state:)` fixture helper and a spec example.

- **PLAN-001.md:316 — the render example will trip `RSpec/ExampleLength`.** `.rubocop.yml` sets no override,
  so the default limit of 5 lines applies, and the expected string is about 25 lines. Verification step 2
  (`bundle exec rake`, which runs RuboCop per `Rakefile:10`) will fail unless the expected string goes in a
  `let` or the example takes an inline `# rubocop:disable RSpec/ExampleLength`, as the repo already does in
  `spec/planner/commands/plan_spec.rb:56` and `spec/planner/commands/explore_spec.rb:155`. Line 66 tells the
  implementer to split methods for `Metrics/*`, but says nothing about the RSpec cops; say which approach to use.

  **Applied:** Added a decision and a Specs rule to put long expected strings in a `let` (the render spec uses `let(:expected_markdown)` with a `<<~MARKDOWN` heredoc), with no `rubocop:disable`.

## Lower-confidence concerns

- **PLAN-001.md:130-160 — the GraphQL query is never checked against GitHub.** Every spec uses `FakeGh`, and
  the manual check was deliberately left out (line 41). The field names look right to me (`isResolved`,
  `isOutdated`, `path`, `line` on `PullRequestReviewThread`; `state` and `body` on `PullRequestReview`), but a
  typo in `QUERY` would pass every spec and only fail for the first real user. This is a decided trade-off;
  it is worth the implementer reading the query against the GitHub GraphQL schema docs once.

- **PLAN-001.md:82-89 — `Gh#json` does not handle output that is not JSON.** A `JSON::ParserError` (for
  example from a gh version that prints a warning on stdout) would escape as a stack trace instead of a
  `[planner]` error. Low likelihood; could be rescued as `Error, "gh returned output that is not JSON"`.

- **PLAN-001.md:330-331 — `folder` created in `before`.** The `writing-rspec` skill
  (`lib/planner/skills/writing-rspec/SKILL.md:54`) says to set objects up with `let`/`let!` rather than
  `before`. `spec/planner/commands/next_spec.rb:15` creates the folder in `before` too, so this follows local
  precedent; just be aware the skill may push the implementer the other way.

- **PLAN-001.md:62, 254-260 — the iteration file is left behind if planning fails.** `File.write` happens before
  `Plan.new(@context).call([path])`. If the agent fails or the user quits, the folder keeps a filled
  `ITERATION-NNN.md` with no plan; rerunning `planner feedback` would then write `ITERATION-NNN+1.md` with the
  same comments rather than reuse it. This is probably acceptable (the user can run `planner plan <folder>`),
  but the README section could say so.

- **README.md:3 — the intro still says only `planner next` creates later iterations.** The plan updates the
  GLOSSARY to mention `planner feedback` but not the README's opening paragraph. Optional.

## Top recommendations

1. Filter out `PENDING` comments inside review threads (add `state` to the query) and spec it.

   **Applied:** Thread comments with `state` `PENDING` are dropped, with the query, filter, decision and spec updated.

2. Say how the render spec should satisfy `RSpec/ExampleLength` (a `let` or an inline disable).

   **Applied:** Long expected strings go in a `let` heredoc; no `rubocop:disable`.

3. Make the staging list say whether `REVIEW-001.md` is committed.

   **Applied:** The whole plan folder is staged, including `REVIEW-001.md`.

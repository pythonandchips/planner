# REVIEW-005 — docs/plans/202610271252-improve-plan-command/PLAN-005.md

## Summary

The plan is accurate and ready to run. Every text it replaces exists word for word. The anchor lines and spec placements are where it says. Each spec string it adds would match the new prompt text, and the existing specs it says must keep passing still would. The weak spots are small: one Verification step cannot see new files, the review prompt is never rendered by hand, and there are a few edge cases in how the review and run agents handle the trailer.

## High-confidence findings

1. **Verification step 4 cannot see untracked files.** `git diff --stat` only lists changes to tracked files. `PLAN-005.md` and `ITERATION-005.md` are untracked (they show as `??` in `git status`), so "plus this plan file, once the stats are added" will never show up. A stray new file created by mistake would not show up either. `git status --short` would show both modified and new files. (PLAN-005.md, Verification step 4.)

   **Applied:** The old step 4, now step 5, uses `git status --short` and lists the untracked files it expects (`ITERATION-005.md`, `PLAN-005.md`, `REVIEW-005*.md`).

2. **The review prompt is only checked by specs, never rendered and read.** Steps 2 and 3 render the plan and run prompts and read the new text. Nothing does the same for `review.md.erb`, which gets the largest change: two rewrapped rules and a new section placed by position (straight before `## Summary for the user`, `lib/planner/prompts/review.md.erb:66`). The review spec only checks for fragments, so a bad placement, such as inside the `Report` section or after the summary block, would still pass. A one-line render through `Planner::Commands::Review` with a stub agent, like step 2, would close this gap.

   **Applied:** Added Verification step 4, which renders the review prompt with a stub agent and checks rules 1 and 2, where the Attribution section sits, and that no `<%` is left.

3. **The plan's claims about the code all check out.** For the record:
   - The step 5 text to replace matches `lib/planner/prompts/plan.md.erb:41-42` exactly. The existing spec that needs `If `<%= toc_file %>` exists, list` on one line is `spec/planner/commands/plan_spec.rb:100`.
   - Rules 1 and 2 match `lib/planner/prompts/review.md.erb:12-18`.
   - Rule 8's last line is `lib/planner/prompts/run.md.erb:58`, followed by a blank line and `## Deviations` at line 60.
   - The examples the new specs go after are at `plan_spec.rb:56`, `review_spec.rb:124` and `run_spec.rb:77`.
   - The existing `'lets the agent apply suggestions to the plan'` check (`review_spec.rb:125-126`) still matches the new rule 2, because "`<%= source_file %>` when the user asks you to" is unchanged.
   - The review agent can already edit the plan: `Edit(#{source_file})` is in its allowed tools (`lib/planner/agents/claude.rb:65`). No Ruby change is needed.
   - Verification step 2's command works. `Context` takes exactly those seven fields (`lib/planner/context.rb:5`), and `Plan#call` only calls `agent.plan` (`lib/planner/commands/plan.rb:24`).

   This is not a defect. It is listed so that the clean result above is backed by evidence.

## Lower-confidence concerns

1. **The run prompt already knows the run model, but the plan asks the agent to work it out.** `run.md.erb:99` already fills in `| Model | <%= model %> |` from the `--model` value (`lib/planner/commands/run.rb:44`, default `sonnet` at `lib/planner/agents/claude.rb:10`). Rule 9 tells the agent to take the model from its system context instead. This matches the skill (`lib/planner/skills/commit-message/SKILL.md:28`) and the "Ruby passes nothing new" decision. Still, the trailer and the Stats row may name the model differently (for example `Claude Sonnet 5.5` against `sonnet`). This is probably fine, but it is worth knowing.

2. **The review agent will also edit plans that have already been run and committed.** The Attribution section applies to every `PLAN-<N>.md` review, with no check on whether the plan already has a `| Status | Completed |` Stats row. If someone reviews an old, completed plan, the agent changes a committed file's suggested message for no purpose, and the working tree gets an unexpected diff. The decisions only exempt "Do not commit." plans. Consider also skipping plans whose Stats say Completed, or confirm this is intended.

3. **The order of steps in the review prompt is only implied.** The `Report` section (`review.md.erb:62-64`) says "After writing `<review_file>`, update `<toc_file>`". The new Attribution section, which comes later in the prompt, says to add the line before the table-of-contents update. An agent reading top to bottom may already have updated the table of contents. The result is the same either way, because the table of contents does not depend on the trailer, so this matters little. Adding "then add the attribution line" to the Report sentence would remove the doubt.

4. **Applying suggestions after a review could disturb the trailer.** If a later "apply suggestions" request rewrites the Commit section, the agent could drop or reorder the `Assisted-by:` lines that earlier agents added. Nothing in the Applying suggestions section says to keep them. This is a low risk, and the plan says not to touch that section.

5. **Lens reviews add a line too.** The Attribution section sits outside the `<% if lens -%>` blocks, so a narrow lens review (for example a security-only pass) also adds a `review` trailer. That fits "every review", but a plan reviewed with several lenses will gather many review lines. This is noted so it is a conscious choice.

## Top recommendations

1. Change Verification step 4 to `git status --short`, so that new and untracked files are checked too.

   **Applied:** The old step 4, now step 5, uses `git status --short` and lists the untracked files it expects.

2. Add a Verification step that renders the review prompt with a stub agent and checks that the Attribution section sits straight before `## Summary for the user`, with no `<%` left.

   **Applied:** Added Verification step 4, which renders the review prompt and checks the rules, where the Attribution section sits, and that no `<%` is left.

3. Decide whether the review agent should skip plans whose Stats already say `Completed`, and record the answer in the Decisions table.

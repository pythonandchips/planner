# REVIEW-001 — docs/plans/202611031255-rspec-test-skill/PLAN-001.md

## Summary

The plan is small, well scoped and its claims about the code hold up. `SkillCatalog`, the
gemspec and `planner skills list` already pick up a new skill folder. The catalog spec
already checks name and description. The `.and` uses it leaves alone are where it says. The
exe spec's `commit-message  ` assertion still passes, because `commit-message` (14
characters) is longer than `writing-rspec` (13), so the padding stays at two spaces. The
main gaps are two places where a developer would have to guess. The first is how the "edit
an existing spec" eval gets its starting file without adding files outside `SKILL.md` and
`evals/evals.json`. The second is what to do if the optimised description drops the wording
the plan requires. Verification also does not check that the evals cover the three required
scenarios.

## High-confidence findings

1. **The third eval needs an input file, but the plan forbids any file other than
   `SKILL.md` and `evals/evals.json`.** Step 2 (PLAN-001.md:127-128) asks for an eval that
   "edits an existing spec file that already breaks a rule elsewhere". skill-creator usually
   handles input files through an eval's `files` list, stored next to `evals.json` (for
   example `evals/files/`). But PLAN-001.md:116 and Verification step 4 (PLAN-001.md:169-171)
   allow only `SKILL.md` and `evals/evals.json` in the skill folder. The shipped
   commit-message evals (`lib/planner/skills/commit-message/evals/evals.json:1-44`) have no
   input files, so there is no example to copy. A developer would have to ask whether to put
   the existing spec inline in the prompt text, or whether a fixtures folder is allowed. Under
   run rule 3 (`lib/planner/prompts/run.md.erb:19-21`) they would take the literal reading,
   but either reading leads to trouble: a fixtures folder fails Verification step 4, and the
   plan never says to put the spec inline. Also, any fixture under
   `lib/planner/skills/writing-rspec/` would ship in the gem, because `planner.gemspec:17`
   includes `lib/planner/skills/**/*`.

2. **The required description wording and the optimised description could disagree.**
   PLAN-001.md:63-65 says the description must say the skill is for writing or editing RSpec
   specs, and must be used whenever `describe`, `context` or `it` blocks or expectations are
   added or changed. PLAN-001.md:141-142 then says to put whatever skill-creator's
   optimisation produces into the frontmatter. The plan does not say which wins if the
   optimiser drops or rewords those points. That is likely, since the optimiser rewrites the
   description to improve triggering. The commit-message description
   (`lib/planner/skills/commit-message/SKILL.md:3`) shows how far the optimiser moves the
   text from a plain sentence.

3. **Verification does not check the eval coverage the plan requires.** PLAN-001.md:122-128
   says the evals must cover three scenarios: implementation-focused or "should"
   descriptions, a compound `.and` matcher, and editing an existing spec that already breaks
   a rule. None of the Verification steps (PLAN-001.md:161-172) checks that
   `evals/evals.json` contains them. Step 3 checks only `SKILL.md`.

## Lower-confidence concerns

1. **The YAML in the optimised description may need quoting.** Optimised descriptions tend
   to contain colons and quotes. The commit-message one has to be single-quoted with `''`
   escapes (`lib/planner/skills/commit-message/SKILL.md:3`). If the YAML is malformed,
   `SkillCatalog.frontmatter` silently returns `{}` (`lib/planner/skill_catalog.rb:20-27`).
   Verification step 1 would then fail through the "every shipped skill names itself"
   example (`spec/planner/skill_catalog_spec.rb:46-51`). So it would be caught, but a short
   note to quote the description as commit-message does would avoid a stop under run rule 4.

2. **"Prints two lines" depends on the description being on one line.**
   `List#print_skills` prints the raw description (`lib/planner/commands/skills/list.rb:25`).
   If the description uses a YAML block scalar (`|`), it can print across several lines, and
   Verification step 2 (PLAN-001.md:164-165) would fail. A folded scalar (`>`) or a quoted
   string avoids this. Saying "keep the description on one line" would remove the risk.

3. **The stopping point for the eval loop is vague.** "Iterate on `SKILL.md` until
   skill-creator's results show the rules are followed" (PLAN-001.md:122) has no pass
   threshold. The user review pause (PLAN-001.md:132-137) acts as the real gate, so this is
   probably fine. Still, a runner on the default `sonnet` model
   (`lib/planner/agents/claude.rb:10`) may loop for a long time before it reaches the pause.

4. **The first bad example uses the word "and" in a description.** The bad example
   `it 'calls #apply_discount and memoizes @total'` (PLAN-001.md:96) puts "and" in
   description text. The plan says that is not covered by the `.and` rule (PLAN-001.md:21).
   A reader of the finished skill could take it as a hint that "and" in descriptions is also
   bad. An example without "and" (for example `it 'calls #apply_discount'`) would keep the
   two rules clearly separate.

5. **A review file in the plan folder would be left untracked.** The commit stages only
   `ITERATION-001.md` and `PLAN-001.md` from the plan folder (PLAN-001.md:183), and the run
   prompt adds only the plan and the table of contents
   (`lib/planner/prompts/run.md.erb:37-39`). This `REVIEW-001.md` would stay untracked after
   the commit. Whether to commit it is a choice for the user, not a defect.

6. **`git diff --stat` does not show new untracked files.** Verification step 5
   (PLAN-001.md:172) would not notice a new file under `spec/`. Step 4's `git status` would
   show it, so this is covered, but step 5 on its own proves less than it seems.

## Top recommendations

1. Say that the "edit an existing spec" eval includes the starting spec inline in its
   prompt text, with no files beyond `evals/evals.json`, or else allow an `evals/files/`
   folder and update step 1, Verification step 4 and the file list to match.

   **Applied:** Step 2's third eval bullet now says to put the existing spec inline in the prompt, with no input files and no `evals/files/` folder.
2. Say that the optimised description must still mention writing or editing RSpec specs and
   adding or changing `describe` / `context` / `it` blocks or expectations, and that it
   should be adjusted by hand if the optimiser drops those points.

   **Applied:** Step 3 now requires the optimised description to keep both points, and to be edited by hand with minimal changes if either is lost.
3. Add a Verification step that reads `evals/evals.json` and confirms it covers the three
   required scenarios.

   **Applied:** New Verification step 4 reads `evals/evals.json` and checks the three scenarios, with the later steps renumbered to 5 and 6.
4. Ask for the description to be a single-line, quoted YAML string, as commit-message's is.

   **Applied:** Step 1 now requires a single-line, single-quoted description with `''` escapes and no block scalar, and Verification step 3 checks for it.

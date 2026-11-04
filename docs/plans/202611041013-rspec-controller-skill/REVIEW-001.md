# REVIEW-001 — docs/plans/202611041013-rspec-controller-skill/PLAN-001.md

## Summary

The plan is accurate about the code. The exe spec line, the padding arithmetic, how
`SkillCatalog` and the gemspec pick up a new skill folder, the sort order of
`planner skills list`, and the README Skills section all match what is in the repository.
The steps are in a workable order and closely follow the plan that shipped `writing-rspec`.
There are two concrete problems. The suggested commit subject breaks the `commit-message`
skill's 50-character limit. The description optimisation step will almost certainly stop
the run, because the same step was blocked by the sandbox in both earlier skill runs. The
plan also misses a risk: the new rules clash with two default rubocop-rspec cops in
projects that use them. There are a few smaller wording gaps.

## High-confidence findings

1. **The suggested commit subject is 56 characters, over the `commit-message` limit.**
   PLAN-001.md:219 suggests `Ship a writing-rspec-controller-specs skill with planner`.
   That is 56 characters. `lib/planner/skills/commit-message/SKILL.md:35` says "Keep the
   subject line to 50 characters or fewer", and the plan tells the runner to follow that
   skill (PLAN-001.md:214-215). Run rule 2 (`lib/planner/prompts/run.md.erb:16-18`) tells
   the runner not to change the plan's wording. That leaves the runner choosing between
   the plan and the skill. Give a subject that fits, for example
   `Ship a controller spec skill with planner` (41 characters).

   **Applied:** The suggested commit subject is now `Ship a controller spec skill with planner`.

2. **The description optimisation step is likely to stop the run under run rule 4.**
   PLAN-001.md:158-160 says to stop under run rule 4 if the optimisation cannot run. The
   optimiser (`python3 -m scripts.run_loop`) failed in the sandbox with
   `PermissionError: [Errno 1] Operation not permitted` in both earlier skill runs
   (`docs/plans/202610291133-git-commit-skill/PLAN-001.md:16` and
   `docs/plans/202611031255-rspec-test-skill/PLAN-001.md:239`). Each time, the user ran
   it outside the sandbox. This plan gives the runner no such route, so a literal reading
   (run rule 3) means stopping without a commit after the evals and review pause are done.
   Say in step 4 that if the optimiser is blocked by the sandbox, the runner should ask
   the user to run it (for example with `! <command>`) and carry on with its output. The
   alternative is to allow the command to run unsandboxed before the run starts. Also note
   the earlier PyYAML failure in packaging
   (`docs/plans/202610291133-git-commit-skill/PLAN-001.md:17`).

   **Applied:** Step 4 and the skill-creator decision row now say that if the sandbox or a missing package blocks the optimiser or packager, the runner asks the user to run it with `! <command>` and carries on, and stops only if it still fails.

3. **The new rules clash with default rubocop-rspec cops, and the plan does not mention
   it.** This repository enables `rubocop-rspec` with its defaults (`.rubocop.yml:1-2`).
   Its own specs tag groups `:aggregate_failures` (`spec/exe/planner_spec.rb:5`,
   `spec/planner/skill_catalog_spec.rb:3`) partly because `RSpec/MultipleExpectations`
   allows only one expectation per example by default and skips examples tagged
   `:aggregate_failures`. The new skill asks for several expectations in one `it` and no
   `:aggregate_failures` (PLAN-001.md:99-101, 118-120). In any project that uses
   rubocop-rspec defaults, every example written to the skill will get a
   `RSpec/MultipleExpectations` offence. In the same way, a `let!` record that no example
   references (the normal case for records that "the request needs", PLAN-001.md:105-107)
   triggers `RSpec/LetSetup`. The decision itself is the user's to keep. But the skill
   should say what to do when these cops are on, for example "follow the project's RuboCop
   config; if it enforces these cops, …", or the plan should record that the clash is
   accepted. Otherwise agents will either break the project's lint or quietly ignore the
   skill.

## Lower-confidence concerns

1. **The bad/good examples could not be checked.** PLAN-001.md:122-124 and
   Verification 3 (PLAN-001.md:189) copy the examples from `ITERATION-001.md` as written
   there. This review was not allowed to read that file, so it cannot confirm that those
   examples follow every rule in step 2. Points to check: the request on the first line,
   the blank lines, no `:aggregate_failures`, no records in `before`, and `widget`
   used as the `let` case that PLAN-001.md:23 mentions. If they break a rule, "copied as
   written" and "nothing that contradicts them" (PLAN-001.md:90) conflict.

2. **"Never create records in `before`" is unclear for sign-in.** PLAN-001.md:108 lists
   sign-in as a normal `before` task. A typical `before { sign_in user }` with
   `let(:user) { create(:user) }` creates the user record inside `before`. A developer or
   the skill's reader would have to ask whether that is allowed or whether `user` must be
   a `let!`. State which.

   **Applied:** The Setup decision row and the step 2 Setup rule now say that `before { sign_in user }` with a lazy `let(:user)` is allowed.

3. **"Normally" in the decision against "put" in the rule.** The decision table says
   separate `it`s "normally go in separate contexts" (PLAN-001.md:26). Step 2 says "put
   those in separate contexts" (PLAN-001.md:120), which reads as always. Under run rule 3
   the runner will write the stricter version. Make them say the same thing.

4. **"The request on the first line" for multi-line requests.** A `post :create, params:
   { ... }` call often spans several lines. PLAN-001.md:112-113 says "on the first line of
   the `it`" and "Follow it with a blank line". It does not say the request may span lines
   as long as it starts on the first line. The skill and the evals could judge that either
   way.

5. **The eval pass bar is still undefined.** "Iterate on `SKILL.md` until skill-creator's
   results show the rules are followed" (PLAN-001.md:134-135) has no threshold, and no
   Verification step checks the eval results. The user's review pause is the only real
   gate. That may be intended, but Verification 4 (PLAN-001.md:193-195) only checks that
   the scenarios exist, not that they pass.

## Top recommendations

1. Replace the suggested commit subject with one of 50 characters or fewer, for example
   `Ship a controller spec skill with planner`.

   **Applied:** The suggested commit subject is now `Ship a controller spec skill with planner`.
2. In step 4, say what to do when the description optimiser or packager is blocked by the
   sandbox (ask the user to run it and carry on), instead of stopping under run rule 4.

   **Applied:** Step 4 now tells the runner to give the user the blocked command (or a package install command), ask them to run it with `! <command>`, and carry on with its output.
3. Add a line to the skill rules (or the decisions table) on how to handle rubocop-rspec's
   `RSpec/MultipleExpectations` and `RSpec/LetSetup` cops in projects that enable them.
4. Say whether `before { sign_in user }` with a lazy `let(:user)` is allowed.

   **Applied:** The plan now says it is allowed, in both the Setup decision row and the step 2 Setup rule.
5. Make PLAN-001.md:26 and PLAN-001.md:120 agree on whether separate `it`s always go in
   separate contexts.

# REVIEW-002 — docs/plans/202611050909-convert-skills-to-rubocop-config/PLAN-002.md

## Summary

The plan is detailed and mostly accurate against the repo. The root `.rubocop.yml` does exclude `docs/**/*`
(`.rubocop.yml:10`), `bundle exec rake` does run specs then RuboCop (`Rakefile:10`), and the installed gems
(rubocop 1.92.1, rubocop-rspec 3.10.2, `Gemfile.lock:36,53`) support `plugins:` and the cop options the plan
sets. Running the cop specs from the repo root loads `spec/spec_helper.rb` through `.rspec:1`, and its `around`
hook moves each example into a temp directory (`spec/spec_helper.rb:68-70`). The specs still find the folder's
`.rubocop.yml`, because `__dir__` is an absolute path.

Two things will cause trouble as written. One message constant is too long for this repo's RuboCop, so
Verification step 2 fails. `ConstructorMethods: [new]` flags the kind of time travel the skill allows. The
remaining points are smaller gaps in coverage and wording.

## High-confidence findings

1. **`Planner/StatusCheckedFirst`'s `MSG_FIRST` breaks Verification step 2** (PLAN-002.md:248, 303).
   Inside `module RuboCop / module Cop / module Planner / class`, the line
   `MSG_FIRST = 'Check the response status with `expect(response).to have_http_status(...)` before any other expectation.'`
   is 126 characters (8 indent + 12 for `MSG_FIRST = ` + 106 for the literal). The root `.rubocop.yml` does
   not change `Layout/LineLength`, so the default maximum of 120 applies. Step 2 lints `cops/*.rb` with that
   config, so it reports an offence. The plan should either shorten the message or say to split the literal
   across two lines with `\`. `NoCompoundMatcher`'s `MSG` (PLAN-002.md:208) comes to 117 characters, which is
   just under the limit.

   **Applied:** Shortened `MSG_FIRST` to `'Make the first expectation `expect(response).to have_http_status(...)`.'` (about 93 columns) and noted why.

2. **`NoObjectsInBefore` flags time travel that the skill allows** (PLAN-002.md:131-133, 227, 286). Any
   `Const.new` or `Const.create` inside a hook is an offence, and that includes `travel_to Time.new(2024, 1, 1)`
   and `travel_to Date.new(2024, 1, 1)`. `writing-rspec` lists time travel and config as allowed `before`
   setup (`lib/planner/skills/writing-rspec/SKILL.md:66-67`). The spec case "does not flag ... `travel_to`"
   (PLAN-002.md:286) does not name an argument, so a developer can make it pass with `travel_to 1.day.ago`
   and never see the conflict. The plan should do one of two things. It can state that `travel_to Date.new(...)`
   is an accepted false positive. Or it can define what is exempt (for example, sends inside the arguments of
   `travel_to`/`freeze_time`) and add a spec case that uses a `Const.new` argument.

   **Applied:** Added a `TimeTravelMethods` key (`travel_to`, `travel`, `freeze_time`) and a Decisions row; the cop skips sends in those calls' arguments but still checks their block bodies, and the spec covers `travel_to Time.new(...)`/`Date.new(...)` and `create` inside a `travel_to` block.

## Lower-confidence concerns

1. **`SkipBlocks: true` weakens the `described_class` rule** (PLAN-002.md:24, 86-90). As I understand
   rubocop-rspec's `RSpec/DescribedClass`, `SkipBlocks: true` stops the search at any block that is not an
   RSpec block, and it does this in `explicit` style as well. For example, `widgets.map { |w| described_class.new(w) }`
   would not be flagged. The skill says "Never use `described_class`" and that this "covers every use"
   (`lib/planner/skills/writing-rspec/SKILL.md:128-132`). The decision is settled, but the config comment
   "never use described_class" claims more than the cop checks. A short note in the plan would set the right
   expectation. I could not confirm this in the gem source without reading outside the repo.

2. **Verification never runs `NoCompoundMatcher`/`NoObjectsInBefore` through the config** (PLAN-002.md:270-272,
   307-314). The specs strip `Include` and read the method lists straight from the YAML. The smoke test runs
   only the three controller cops and `RSpec/DescribedClass`. So nothing checks that the `'**/*_spec.rb'`
   include glob, or the `CreationMethods`/`ConstructorMethods` keys, work under a real `rubocop` run. Adding
   a line such as `before { create(:x) }` and `expect(a).to eq(1).and eq(2)` to the smoke test, plus
   both cops to `--only`, would cover them.

   **Applied:** The smoke test now adds `create(:widget)` to `before` and `.and eq(2)` to the expectation, runs both cops under `--only`, and expects six offences.

3. **`--only` with custom cop names may be checked before the config's `require:` runs**
   (PLAN-002.md:310). If RuboCop checks `--only` names against its registry before it loads the config, the
   `Planner/...` names are unknown and step 3 fails with "Unrecognized cop". I could not confirm the load
   order without reading the gem. If it fails, the fallback is to drop `--only` and pass a source that only
   breaks the four intended cops.

4. **The blank-line check is measured from line numbers** (PLAN-002.md:204). A comment line between the
   request and the next statement counts as a gap, so it passes. A request whose arguments include a heredoc
   (`post "/x", params: <<~JSON`) has a `last_line` on the `post` line rather than the heredoc's end, so a
   missing blank line after the heredoc goes unreported. Both are edge cases, but the plan could say whether
   they are accepted.

5. **The two ordering cops' `on_block` may exceed the default Metrics limits** (PLAN-002.md:240-254). Each
   has three branches with `add_offense` and early returns, and step 2 lints with the default
   `Metrics/MethodLength` (10) and `Metrics/AbcSize`. The plan does not forbid helper methods, but a sentence
   allowing private helpers (`statements`, `hook_block?`, `missing_blank_line?`) would answer the question
   before anyone asks it.

6. **The commit leaves this review untracked** (PLAN-002.md:323-328). The staging list is "exactly"
   `.rubocop.yml`, `cops/`, `ITERATION-002.md` and `PLAN-002.md`. `REVIEW-002.md` will be in the folder by
   then, and the plan does not say whether to include it or leave it out.

   **Applied:** Added `REVIEW-002.md` to the Commit section's staging list.

## Top recommendations

1. Shorten `StatusCheckedFirst::MSG_FIRST`, or say to split it, so it fits in 120 columns.

   **Applied:** Shortened `MSG_FIRST` so the line fits in 120 columns.

2. Decide how `NoObjectsInBefore` treats `travel_to Time.new(...)`/`Date.new(...)`, and add a spec case that uses a constructor argument.

   **Applied:** Exempted the arguments of `TimeTravelMethods` calls and added spec cases with `Time.new`/`Date.new` arguments.

3. Extend the smoke test to run `Planner/NoCompoundMatcher` and `Planner/NoObjectsInBefore` through the config.

   **Applied:** Extended the smoke-test source and `--only` list; the expected result is now six offences.

4. Note that `SkipBlocks: true` lets `described_class` through inside non-RSpec blocks.
5. Say whether `REVIEW-002.md` is staged in the commit.

   **Applied:** `REVIEW-002.md` is now staged in the commit.

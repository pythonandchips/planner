# PLAN-002 — Set up spec objects with let, not before

Add a third rule to the shipped `writing-rspec` skill. Every object an example needs
(FactoryBot `create` / `build` / `build_stubbed` and friends, `Model.new` /
`Model.create`, and test doubles) is created with `let!` or `let`, never in a `before`
block. `before` only does setup that doesn't instantiate objects (stubs, sign-in, headers,
time travel, config), and is always written as plain `before`, never `before(:all)` /
`before(:context)` and without an `:each` / `:example` argument. The rule moves out of
`writing-rspec-controller-specs`: that skill drops its "create records with `let!`" bullet,
trims the records from its bad/good example, and keeps only its controller-specific rules.
`writing-rspec` gets three new evals and goes through the full skill-creator process again
(eval runs, user review pause, description optimisation, packaging). The controller skill is
edited by hand. Both README bullets are updated.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the rule lives | Moved into `writing-rspec`. `writing-rspec-controller-specs` drops its record-creation bullet and relies on its existing "also follow `writing-rspec`" pointer. `writing-rspec` still does not mention the controller skill (PLAN-001 of the controller folder). |
| `let!` vs `let` | Create objects with `let!`, or with `let` when an example references the value and it doesn't have to exist before the example runs. Never in `before`. |
| Grouping objects of the same kind | Not prescribed. One `let!` per object or one `let!` returning an array are both fine. |
| What counts as instantiating an object | Any object built via FactoryBot (`create`, `create_list`, `build`, `build_stubbed`, ...) or by hand (`Widget.new`, `Widget.create`, ...). |
| Test doubles | Also objects: `double`, `instance_double`, `spy`, ... are defined with `let` / `let!`. `before` may still stub them (`allow(...).to receive`). |
| What `before` may contain | Setup that doesn't instantiate objects: stubs (`allow` / `expect ... to receive`), sign-in, headers, time travel, config. |
| Hook form | Only per-example hooks, written as plain `before do ... end`. Never `before(:all)` / `before(:context)`, and never write the `:each` / `:example` argument. |
| `around` hooks | Not mentioned in the skill. |
| `writing-rspec` example | One bad/good pair: the brief's two specs from `ITERATION-002.md`, trimmed to the setup (`subject`, `let`s, `before`) and the `#total_sales` describe block. |
| Controller skill example | Keep its bad/good shape but drop the record lines (the `let(:widget)`, the `create` calls in bad, the `let!`s in good). |
| Process | Full skill-creator run for `writing-rspec`, as in PLAN-001: add evals, run all evals, pause for user review in the viewer, iterate, description optimisation, package. Workspace, benchmark, viewer and `.skill` output in `$TMPDIR`. |
| Eval scope | `writing-rspec` only. The controller skill's evals are not changed or re-run; its edit is checked by reading it. |
| New `writing-rspec` evals | Three, added after the existing three (which stay unchanged): a new spec needing several records; adding an example to an existing spec (inline) that creates records in `before`; a spec needing an `instance_double`. No `before(:all)` eval. |
| Descriptions and README | `writing-rspec`'s description (via the optimiser) and README bullet mention the new rule. The controller skill's description and README bullet drop "records are created with `let!`" (hand-edited, minimal change). |
| Optimiser / packager blocked by the sandbox or a missing package | As in the controller folder's PLAN-001: give the user the exact command, ask them to run it with `! <command>`, wait, carry on with its output, record it under "Commands that needed help". Stop under run rule 4 only if it still cannot run. |
| Settled by PLAN-001 and not changed | Skill location, frontmatter keys (`name`, `description` only), single-line single-quoted description, only `SKILL.md` and `evals/evals.json` in the skill folder, rules apply only to specs the agent writes or edits, evals put existing specs inline with no input files, no change to `docs/TODO.md`. |

## Files to create / change

```
lib/planner/skills/writing-rspec/SKILL.md                    new setup rule, example, wording; optimised description
lib/planner/skills/writing-rspec/evals/evals.json            three new evals (ids 4-6)
lib/planner/skills/writing-rspec-controller-specs/SKILL.md   drop record rule, trim example, edit description
README.md                                                    update both rspec skill bullets
```

No Ruby or spec changes. `lib/planner/skills/writing-rspec-controller-specs/evals/evals.json`
is not changed.

## Implementation

### 1. Update `writing-rspec` with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to improve the
existing skill at `lib/planner/skills/writing-rspec/`. Keep all workspace, benchmark,
grading and viewer output under `$TMPDIR` (for example
`$TMPDIR/writing-rspec-workspace/`), never in the repo.

The body of `SKILL.md` keeps both existing rules unchanged and adds the rule below. Keep it
concise.

- Intro: change "Follow these two rules" to "Follow these three rules", and make the scope
  sentence cover setup too: the rules apply only to the descriptions, expectations and setup
  you write or change.
- Add a section after "No compound matchers", headed e.g. `## Set up objects with let, not
  before`, with a one-sentence reason (objects made in `before` have no name, so examples
  can't refer to them and readers can't see what each example depends on) and these rules:
  - Create every object the examples need with `let!`, or with `let` when an example
    references the value and it doesn't have to exist before the example runs. This covers
    FactoryBot (`create`, `create_list`, `build`, `build_stubbed`, ...), objects made by hand
    (`Widget.new`, `Widget.create`, ...) and test doubles (`double`,
    `instance_double`, `spy`, ...). Never create them in `before`.
  - Several objects of the same kind can each have their own `let!` or share one `let!`
    that returns an array. Either is fine.
  - `before` only does setup that doesn't instantiate objects: stubs
    (`allow(...).to receive`, `expect(...).to receive`), sign-in, headers, time travel,
    config.
  - Write hooks as plain `before do ... end`. Never use `before(:all)` or
    `before(:context)`, and don't write the `:each` or `:example` argument.
- Example for that section, in one fenced `ruby` block:

  ```ruby
  # Bad
  RSpec.describe Widgets::WidgetMetrics do
    subject(:metrics) { described_class.new(widget: second_widget) }

    let(:project) { create(:project) }
    let(:first_widget) { project.widgets.first }
    let(:second_widget) { create(:widget, project: project) }

    before do
      create(:widget_sale, widget: first_widget, amount: 150, dated_on: Date.yesterday)
      create(:widget_review, widget: first_widget, marked_for_review: true)

      create(:widget_sale, widget: second_widget, amount: 40, dated_on: Date.yesterday)
      create(:widget_review, widget: second_widget, marked_for_review: true)
    end

    describe "#total_sales" do
      it "returns the total sales of the widget only" do
        expect(metrics.total_sales).to eq("140")
      end
    end
  end

  # Good
  RSpec.describe Widgets::WidgetMetrics do
    subject(:metrics) { described_class.new(widget: second_widget) }

    let(:project) { create(:project) }
    let(:first_widget) { project.widgets.first }
    let(:second_widget) { create(:widget, project: project) }
    let!(:widget_sales) do
      [
        create(:widget_sale, widget: first_widget, amount: 150, dated_on: Date.yesterday),
        create(:widget_sale, widget: second_widget, amount: 40, dated_on: Date.yesterday)
      ]
    end
    let!(:widget_reviews) do
      [
        create(:widget_review, widget: second_widget, marked_for_review: true),
        create(:widget_review, widget: first_widget, marked_for_review: true)
      ]
    end

    describe "#total_sales" do
      it "returns the total sales of the widget only" do
        expect(metrics.total_sales).to eq("140")
      end
    end
  end
  ```

- "Before you finish": check each description, expectation and piece of setup you wrote or
  changed against the rules.

Frontmatter stays `name` and `description` only, with the description on a single line as a
single-quoted YAML string (`'` escaped as `''`), no block scalar.

### 2. Evals

Add three evals to `lib/planner/skills/writing-rspec/evals/evals.json`, with ids 4, 5 and 6,
after the existing three. Do not change evals 1-3. Each existing spec or class goes inline in
the prompt text; no input files, no `evals/files/` folder.

- **4, new spec with records**: write a spec for a class that needs several records (along
  the lines of the brief's `WidgetMetrics`), where the natural first draft creates them in
  `before`. Expectations: no `create` / `build` / `.new` / double inside a `before`; records
  are in `let!` / `let`; no `before(:all)` / `before(:context)` / `before(:each)` /
  `before(:example)`.
- **5, edit an existing spec**: an existing spec (inline) creates records in `before`; ask
  the agent to add an example that needs a new record. Expectations: the existing `before`
  block is left as it was; the new record is created with `let!` / `let`, not added to
  `before`.
- **6, doubles**: a spec for a class that takes a collaborator, where an `instance_double`
  is needed and stubbed. Expectations: the double is defined with `let` / `let!`; `before`
  (if any) only stubs it with `allow(...).to receive`; no double is created in `before`.

Run all six evals, grade them, and iterate on `SKILL.md` until skill-creator's results show
the rules are followed. If an eval run cannot be launched (sandbox, permissions), stop under
run rule 4.

When skill-creator reaches its human review step, generate its review viewer, then stop and
ask the user to review the eval results. Tell them where the viewer output is (the sandbox
blocks `open`, so give the path for them to open). This is a planned pause, not a failure:
wait in the same session for their feedback, apply it as skill-creator describes (re-running
evals as it directs), and pause again each time skill-creator asks. Continue to step 3 only
once the user says they are happy. If the viewer can't be generated, stop under run rule 4.

### 3. Description optimisation and packaging

Run skill-creator's description optimisation and put the result into the `SKILL.md`
frontmatter, written as step 1 describes. Keep its working files in `$TMPDIR`.

The optimiser (`python3 -m scripts.run_loop ...`) has been blocked by the sandbox before
(`PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`), and
packaging has failed before with `ModuleNotFoundError: No module named 'yaml'`. If either is
blocked by the sandbox or a missing package, do not stop: give the user the exact command
(and, for a missing package, the install command such as `python3 -m pip install pyyaml`),
preferably as a short wrapper script in `$TMPDIR` since a long pasted one-liner has failed
before, ask them to run it with `! <command>`, wait, and carry on with its output. Record
each one under "Commands that needed help" in the stats. If it still cannot run after the
user has tried, stop under run rule 4.

The optimised description must still say:

- the skill is for writing or editing RSpec specs, used whenever the agent adds or changes
  `describe`, `context` or `it` blocks or expectations (from PLAN-001)
- objects are set up with `let!` / `let` rather than in `before` blocks

If the result drops any point, edit it back in by hand, changing as little of the optimised
text as possible.

Package the skill with skill-creator, writing the `.skill` file to `$TMPDIR`, not the repo.

### 4. Edit `writing-rspec-controller-specs` by hand

In `lib/planner/skills/writing-rspec-controller-specs/SKILL.md`:

- Frontmatter description: remove `records are created with let!, ` and nothing else, so
  it reads `... spec/controllers or spec/requests: the request is the first line of the
  example, the response status is checked first, and every expectation about one request
  lives in one example.'`
- `## Setup`: change the lead sentence to `Making the request in \`before\` hides which
  action an example runs.` Delete the first bullet (`Create the records the request needs
  with \`let!\` ... Never create records in \`before\`.`). Keep the `before` only prepares
  the request bullet unchanged.
- Bad/good example: delete `let(:widget) { project.widgets.first }` from both
  halves, the two `create(...)` lines and the blank line after them from the bad `before`,
  and the two `let!` lines from the good half. Keep the blank line between the context line
  and `before`. Change nothing else in the example.
- Leave everything else, including the `writing-rspec` pointer, the `:aggregate_failures`
  override and "Before you finish", unchanged.

### 5. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edits small. In `## Skills`:

- `writing-rspec` bullet: append the new rule, written from the finished skill, e.g.
  `..., use separate \`expect\` lines instead of \`.and\` matchers, and set up test objects
  with \`let!\` or \`let\` instead of in \`before\` blocks.`
- `writing-rspec-controller-specs` bullet: remove `records in \`let!\`, ` so it reads
  `... Rails controller and request specs with the request on the first line of each
  example, the response status checked first, and one example per request.`

## Verification

1. `bundle exec rake` passes: all specs and RuboCop with no offences.
2. `bundle exec exe/planner skills list` prints three lines (`commit-message`,
   `writing-rspec`, `writing-rspec-controller-specs`), each on one line, and exits 0.
3. Read `lib/planner/skills/writing-rspec/SKILL.md` and confirm: both old rules and examples
   are unchanged; the new section states every rule in step 1 (objects incl. doubles in
   `let!` / `let`, grouping either way, what `before` may contain, plain `before` only);
   the bad/good pair matches step 1; frontmatter has only `name` and `description`; the
   description is one single-quoted line covering the points in step 3.
4. Read `lib/planner/skills/writing-rspec/evals/evals.json` and confirm evals 1-3 are
   unchanged and evals 4-6 cover the three scenarios in step 2, with code inline and no
   input files.
5. Read `lib/planner/skills/writing-rspec-controller-specs/SKILL.md` and confirm it no
   longer tells the agent how to create records, its example has no `create` / `let` /
   `let!` lines, and its description and other sections match step 4.
6. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the
   repo; `lib/planner/skills/writing-rspec/` contains only `SKILL.md` and
   `evals/evals.json`.
7. `git diff --stat` shows changes only to the four files listed above, and none under
   `spec/`.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/writing-rspec lib/planner/skills/writing-rspec-controller-specs/SKILL.md README.md docs/plans/202611031255-rspec-test-skill/ITERATION-002.md docs/plans/202611031255-rspec-test-skill/PLAN-002.md
```

Write the message to a file and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Set up spec objects with let instead of before

The writing-rspec skill now asks for every object an example needs,
including factory records, hand-built objects and doubles, to be
created with let! or let rather than in a before block. Each object
then has a name the examples can refer to. before is kept for stubs,
sign-in and similar setup, and is never run once for a whole group.

The rule moves out of the controller spec skill, which now relies on
writing-rspec for it. The README bullets for both skills are updated.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-04T14:21:11Z |
| Finished | 2026-11-04T14:38:33Z |
| Elapsed | 17m 22s |
| Model | sonnet |
| Tokens | ~600k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `python3 -m scripts.run_loop --eval-set ... --skill-path lib/planner/skills/writing-rspec ...` (via `$TMPDIR/writing-rspec-workspace/optimise/run.sh`) | Blocked by the sandbox: `PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`. The user ran the wrapper script with `!`. It finished, but no query triggered the skill in any iteration (0% recall), so it returned the original description unchanged and the let rule was added to the description by hand. | Allow `sh $TMPDIR/writing-rspec-workspace/optimise/run.sh` to run outside the sandbox, or allow the semaphore `sysconf` call the process pool needs. |
| `timeout 100 $TMPDIR/writing-rspec-workspace/optimise/run.sh` | Failed with `command not found: timeout` on macOS; rerun in the background without `timeout`. | Do not use `timeout` on macOS; run in the background with `&`. |

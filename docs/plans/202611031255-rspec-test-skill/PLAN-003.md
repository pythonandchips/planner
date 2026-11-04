# PLAN-003 — Refer to the class under test by its full name

Add a fourth rule to the shipped `writing-rspec` skill. Specs the agent writes or changes
never use the `described_class` helper. They refer to the class under test by its fully
qualified name (`Widgets::WidgetMetrics`, not `WidgetMetrics` relying on module
nesting, and no leading `::`). The one exception is a `shared_examples` / `shared_context`
block that is used with more than one class. The existing WidgetMetrics bad/good example
switches from `described_class` to the full name. `writing-rspec` gets two new evals, evals 2
and 5 drop `described_class` from their inline specs, and the skill goes through the full
skill-creator process again (eval runs, user review pause, description optimisation,
packaging). The description is not required to mention the new rule, the README is not
changed, and `writing-rspec-controller-specs` is not changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Which uses are banned | Every use of `described_class`: `subject`, `let`, inside examples, `described_class::CONST`, `instance_double(described_class)`, `expect(described_class).to receive`, and so on. |
| Editing a spec that already uses `described_class` | As with the other rules, only lines the agent writes or changes use the full name. Existing `described_class` lines it does not otherwise touch are left alone. |
| What "full name" means | The fully qualified constant, as in `RSpec.describe Widgets::WidgetMetrics`. Never a shortened name that relies on module nesting. No leading `::`. |
| Shared examples / shared contexts | `described_class` is allowed inside `shared_examples` / `shared_context` only when that block is used with more than one class. If it is used with a single class, the full name is required. |
| Process | Full skill-creator run, as PLAN-002: add evals, run all evals, pause for user review in the viewer, iterate, description optimisation, package. Workspace, benchmark, viewer and `.skill` output in `$TMPDIR`. |
| New evals | Two, ids 7 and 8: a new spec for a namespaced class; an edit to an existing spec (inline) that uses `described_class`. No shared-examples eval. |
| Existing evals | Evals 2 and 5 replace `described_class` with the full class name in their inline specs. Nothing else in evals 1-6 changes. |
| WidgetMetrics example (let rule) | Replace `described_class` with `Widgets::WidgetMetrics` in both the bad and good halves. Nothing else in it changes. |
| Reason given in the skill | Readability: the full name shows which class an example uses without scrolling up to the `describe` line, and it can be searched for. |
| New rule's example | One short subject pair (see Implementation step 1). |
| Description and README | Neither is required to mention the new rule. The README is not changed. The description is what the optimiser produces, keeping the points PLAN-001 and PLAN-002 require. |
| `writing-rspec-controller-specs` | No change. |
| `feedback-002.md` notes (evals 4 and 5 from the PLAN-002 run) | Out of scope. |
| Settled by PLAN-001 / PLAN-002 and not changed | Skill location, frontmatter keys (`name`, `description` only), single-line single-quoted description, only `SKILL.md` and `evals/evals.json` in the skill folder, rules apply only to what the agent writes or changes, evals put code inline with no input files, optimiser/packager sandbox fallback (user runs the command with `!`), no change to `docs/TODO.md`. |

## Files to create / change

```
lib/planner/skills/writing-rspec/SKILL.md            new rule section, example fix, intro wording; optimised description
lib/planner/skills/writing-rspec/evals/evals.json    evals 2 and 5 use full names; two new evals (ids 7-8)
```

No Ruby, spec or README changes. `lib/planner/skills/writing-rspec-controller-specs/` is not
changed.

## Implementation

### 1. Update `writing-rspec` with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to improve the
existing skill at `lib/planner/skills/writing-rspec/`. Keep all workspace, benchmark,
grading and viewer output under `$TMPDIR` (for example `$TMPDIR/writing-rspec-workspace/`),
never in the repo.

The body of `SKILL.md` keeps the three existing rules unchanged except for the example fix
below, and adds the rule below. Keep it concise.

- Intro: change "Follow these three rules" to "Follow these four rules", and make the scope
  sentence cover class references too: the rules apply only to the descriptions,
  expectations, setup and class references you write or change.
- In the `## Set up objects with let, not before` example, change
  `described_class.new(widget: second_widget)` to
  `Widgets::WidgetMetrics.new(widget: second_widget)` in both the bad and good
  halves. Change nothing else in that example.
- Add a section after `## Set up objects with let, not before` and before
  `## Before you finish`, headed `## Name the class under test, not described_class`, with
  the reason (the full name shows which class an example uses without scrolling up to the
  `describe` line, and it can be searched for) and these rules:
  - Never use `described_class`. Write the class's fully qualified name instead, as in the
    `RSpec.describe` line: `Widgets::WidgetMetrics`, not `WidgetMetrics` and not
    `::Widgets::WidgetMetrics`. This covers every use: `subject`, `let`, inside
    examples, constants (`Widgets::WidgetMetrics::LIMIT`), doubles
    (`instance_double(Widgets::WidgetMetrics)`) and message expectations.
  - Exception: inside `shared_examples` or `shared_context` used by more than one class,
    `described_class` is allowed. If the shared block is used by only one class, write the
    full name.
- Example for that section, in one fenced `ruby` block:

  ```ruby
  # Bad
  subject(:metrics) { described_class.new(widget: widget) }

  # Good
  subject(:metrics) { Widgets::WidgetMetrics.new(widget: widget) }
  ```

- "Before you finish": check each description, expectation, piece of setup and class
  reference you wrote or changed against the rules.

Frontmatter stays `name` and `description` only, with the description on a single line as a
single-quoted YAML string (`'` escaped as `''`), no block scalar.

### 2. Evals

In `lib/planner/skills/writing-rspec/evals/evals.json`:

- Eval 2: in the inline spec, change `described_class.new(rows: %w[a b c])` to
  `Report.new(rows: %w[a b c])`. Change nothing else in eval 2.
- Eval 5: in the inline spec, change `described_class.new(project: project)` to
  `Widgets::OverdueReport.new(project: project)`. Change nothing else in eval 5.
- Evals 1, 3, 4 and 6 are unchanged.

Add two evals, ids 7 and 8, after eval 6. Code goes inline in the prompt text; no input
files, no `evals/files/` folder.

- **7, new spec for a namespaced class**: give a class defined inside a namespace (for
  example `module Widgets; class WidgetBuilder ... end; end`) with an instance method and a
  class method or constant, and ask for a new spec. Expectations: no `described_class`
  anywhere; `RSpec.describe` and every other reference use the fully qualified name
  (`Widgets::WidgetBuilder`), with no leading `::` and no shortened name.
- **8, edit an existing spec**: an existing spec (inline) whose `subject` uses
  `described_class.new(...)`; ask the agent to add one example that needs a second instance
  of the class or a reference to one of its constants. Expectations: the existing
  `described_class` lines are left as they were; the new lines use the fully qualified name,
  not `described_class`.

Run all eight evals, grade them, and iterate on `SKILL.md` until skill-creator's results
show the rules are followed. If an eval run cannot be launched (sandbox, permissions), stop
under run rule 4.

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
blocked by the sandbox or a missing package, do not stop: write the exact command as a short
wrapper script in `$TMPDIR` (and, for a missing package, give the install command such as
`python3 -m pip install pyyaml`), ask the user to run it with `! <command>`, wait, and carry
on with its output. Do not use `timeout` (not available on macOS). Record each one under
"Commands that needed help" in the stats. If it still cannot run after the user has tried,
stop under run rule 4.

The optimised description must still say:

- the skill is for writing or editing RSpec specs, used whenever the agent adds or changes
  `describe`, `context` or `it` blocks or expectations (from PLAN-001)
- objects are set up with `let!` / `let` rather than in `before` blocks (from PLAN-002)

It does not need to mention the `described_class` rule. If the result drops either point,
edit it back in by hand, changing as little of the optimised text as possible.

Package the skill with skill-creator, writing the `.skill` file to `$TMPDIR`, not the repo.

## Verification

1. `bundle exec rake` passes: all specs and RuboCop with no offences.
2. `bundle exec exe/planner skills list` prints three lines (`commit-message`,
   `writing-rspec`, `writing-rspec-controller-specs`), each on one line, and exits 0.
3. Read `lib/planner/skills/writing-rspec/SKILL.md` and confirm: the intro says four rules
   and covers class references; the three earlier rules are unchanged; the WidgetMetrics
   example uses `Widgets::WidgetMetrics.new` in both halves and has no
   `described_class`; the new section states every rule in step 1 (every use banned, fully
   qualified name with no leading `::`, the multi-class shared examples exception) with the
   bad/good pair from step 1; "Before you finish" mentions class references; frontmatter has
   only `name` and `description`; the description is one single-quoted line covering the
   points in step 3.
4. `grep -n described_class lib/planner/skills/writing-rspec/SKILL.md` shows only the new
   section (rule text and the bad example line).
5. Read `lib/planner/skills/writing-rspec/evals/evals.json` and confirm: evals 1, 3, 4 and 6
   are unchanged; evals 2 and 5 differ only in the full class name replacing
   `described_class`; evals 7 and 8 cover the two scenarios in step 2, with code inline and
   no input files.
6. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the
   repo; `lib/planner/skills/writing-rspec/` contains only `SKILL.md` and
   `evals/evals.json`.
7. `git diff --stat` shows changes only to the two files listed above, and none under
   `spec/`, `README.md` or `lib/planner/skills/writing-rspec-controller-specs/`.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/writing-rspec docs/plans/202611031255-rspec-test-skill/ITERATION-003.md docs/plans/202611031255-rspec-test-skill/PLAN-003.md
```

Write the message to a file and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Name the class under test instead of described_class

The writing-rspec skill now asks for specs to refer to the class under
test by its fully qualified name rather than described_class, so each
example shows which class it uses and the name can be searched for.
described_class is still allowed in shared examples used by more than
one class.

The skill's own examples and evals no longer use described_class, and
two evals cover new and edited specs.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-04T15:10:37Z |
| Finished | 2026-11-04T15:42:13Z |
| Elapsed | 31m 36s |
| Model | sonnet |
| Tokens | ~700k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sh /tmp/claude-501/writing-rspec-workspace/optimise/run.sh` | The description optimiser failed in the sandbox with `PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`; the user ran it with `!` instead. | Allow the optimiser to run outside the sandbox, or keep running it with `!`. |

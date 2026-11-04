# PLAN-001 — Ship a writing-rspec-controller-specs skill

Ship a third planner skill, `writing-rspec-controller-specs`, under
`lib/planner/skills/writing-rspec-controller-specs/`. It adds controller and request spec
rules on top of the existing `writing-rspec` skill. Records the request needs are created
with `let!`, not in `before`. `before` only prepares the request and never makes it. Each
`it` makes the request on its first line. The first expectation checks the response status.
All expectations about the same request go in one example. The skill is built with the
`skill-creator` skill, using the same process as `writing-rspec` (evals, a pause for the
user to review them, description optimisation, packaging). It ships in the gem and is
installed with `planner skills install`. The README Skills section gets a bullet for it.
`spec/exe/planner_spec.rb` is loosened so the longer skill name doesn't break it. Existing
specs and the `writing-rspec` skill are not otherwise changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Skill name and location | `writing-rspec-controller-specs`, at `lib/planner/skills/writing-rspec-controller-specs/SKILL.md`, shipped in the gem. Not copied into this repo's `.claude/skills`. |
| Which specs it covers | Controller specs (`spec/controllers`, `type: :controller`) and request specs (`spec/requests`, `type: :request`). |
| Relation to `writing-rspec` | The new skill says to also follow `writing-rspec`. `writing-rspec` is not changed and does not mention the new skill. |
| `:aggregate_failures` | Not used in controller/request examples. The status check acts as a gate: if the status is wrong, the example stops before the other expectations run. The new skill states that this overrides `writing-rspec`'s `:aggregate_failures` rule for these specs. |
| Setup | Records the request needs are created with `let!` (or `let` when the examples reference them and they don't have to exist beforehand, as `widget` in the brief). Records are never created in `before`. `before` only prepares the request (headers, sign-in, stubs) and never makes the request. Signing in a lazy `let` record in `before` (`before { sign_in user }` with `let(:user)`) is allowed. |
| Request placement and layout | The request (`get :index`, `post "/path"`, ...) is the first line of each `it`, followed by a blank line, then the status check, a blank line, then the other expectations. |
| Status check | Every example checks `expect(response).to have_http_status(...)` straight after the request, with whatever status fits (`:success`, `:redirect`, `:not_found`, a number, ...). |
| Examples per request | All expectations about the same request go in one `it`. Use separate `it`s only when the setup or request differs, and those normally go in separate contexts. |
| Examples in SKILL.md | One bad/good pair: the two examples from `ITERATION-001.md`, as written there. |
| Eval scenarios | Writing a new controller spec; adding an example to an existing controller spec (given inline) that already breaks the rules; an action with a non-200 status. |
| skill-creator process and the rest of the setup | Same as `writing-rspec` (docs/plans/202611031255-rspec-test-skill/PLAN-001.md): draft, write and run evals (skill-creator's default count), pause for user review in the viewer, iterate, description optimisation, package. Workspace, benchmark, viewer and `.skill` output go in `$TMPDIR`. Only `SKILL.md` and `evals/evals.json` are committed. The description is a single line, single-quoted. Frontmatter has only `name` and `description`. Rules apply only to specs the agent writes or edits. Stop under run rule 4 if any step can't run, except that a description optimiser or packager command blocked by the sandbox or a missing package is handed to the user to run (step 4). |
| `spec/exe/planner_spec.rb:31` | Change `/\Acommit-message  \S/` to `/\Acommit-message +\S/`, so the test doesn't depend on the padding set by the longest skill name. |
| README | Add a `writing-rspec-controller-specs` bullet to the `## Skills` section. |
| TODO | No change to `docs/TODO.md`. |

## Files to create / change

```
lib/planner/skills/writing-rspec-controller-specs/SKILL.md          new: the skill
lib/planner/skills/writing-rspec-controller-specs/evals/evals.json  new: skill-creator's evals
spec/exe/planner_spec.rb                                            line 31: regex allows any padding
README.md                                                           new bullet in the Skills section
```

`SkillCatalog`, `planner skills list/install` and the gemspec already pick up a new skill
folder. `spec/planner/skill_catalog_spec.rb` already checks that every shipped skill's
`name` matches its folder and that its description is not blank.

## Implementation

### 1. Loosen the exe spec

`planner skills list` pads every name to the longest one. At 30 characters, the new name
puts 18 spaces after `commit-message`, so the current assertion fails. In
`spec/exe/planner_spec.rb`, change:

```ruby
    expect(out).to match(/\Acommit-message  \S/)
```

to:

```ruby
    expect(out).to match(/\Acommit-message +\S/)
```

Change nothing else in that file.

### 2. Build the skill with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to create the skill
directly at `lib/planner/skills/writing-rspec-controller-specs/`. Keep all workspace,
benchmark, grading and viewer output under `$TMPDIR` (for example
`$TMPDIR/writing-rspec-controller-specs-workspace/`), never in the repo.

`SKILL.md` must have this frontmatter, and only these keys:

```
---
name: writing-rspec-controller-specs
description: <written and then optimised with skill-creator>
---
```

Write the description on a single line as a single-quoted YAML string, escaping any `'`
inside it as `''`, as `lib/planner/skills/writing-rspec/SKILL.md` does. Do not use a YAML
block scalar (`|` or `>`).

The description must say the skill is for writing or editing Rails controller or request
specs, and that it is used alongside `writing-rspec`.

The body of `SKILL.md` must state every rule below and nothing that contradicts them. Keep
it concise.

Scope and relation to `writing-rspec`:

- The rules apply to controller specs (`spec/controllers`, `type: :controller`) and request
  specs (`spec/requests`, `type: :request`) that you write or edit. Do not rewrite existing
  specs that the task does not otherwise touch.
- Also follow the `writing-rspec` skill. Where the two differ, this skill wins for
  controller and request specs. The one difference is that these examples are not tagged
  `:aggregate_failures`: the status check comes first, and if it fails, the example stops
  before the other expectations run.

Setup:

- Create the records the request needs with `let!`, or with `let` when an example
  references the value and it doesn't have to exist before the request. Never create
  records in `before`.
- `before` only prepares the request: headers, sign-in, stubs. It never makes the request.
  Signing in a lazy `let` record there, as in `before { sign_in user }` with
  `let(:user)`, is allowed.

The example:

- Make the request (`get :index`, `post "/path"`, ...) on the first line of the `it`, so it
  is clear which action the example runs. Follow it with a blank line.
- The first expectation checks the response status with
  `expect(response).to have_http_status(...)`, using whatever status fits (`:success`,
  `:redirect`, `:not_found`, a number, ...). Follow it with a blank line, then the other
  expectations.
- Put every expectation about the same request in one `it`. This creates the records once
  instead of once per example. Use separate `it`s only when the setup or request differs,
  and put those in separate contexts.

Include exactly one bad/good pair: the two code examples from
`docs/plans/202611041013-rspec-controller-skill/ITERATION-001.md`, copied as written there,
in fenced `ruby` blocks headed `# Bad` and `# Good` (or under Bad / Good labels).

End with a short "Before you finish" step: check each controller or request example you
wrote or changed against the rules and fix any that break them.

Do not add any file other than `SKILL.md` and `evals/evals.json`.

### 3. Evals

Use skill-creator to write its default number of eval prompts into
`lib/planner/skills/writing-rspec-controller-specs/evals/evals.json`, run them, grade them,
and iterate on `SKILL.md` until skill-creator's results show the rules are followed. Between
them, the evals must cover:

- writing a new controller spec from scratch, where the natural first draft would create
  records and make the request in `before` and use one `it` per assertion
- adding an example to an existing controller spec that already breaks the rules, checking
  the agent follows the rules only in what it writes or changes. Put the existing spec
  inline in the eval's prompt text. Do not give the eval input files, and do not add an
  `evals/files/` folder or any other file to the skill folder.
- an action that does not return 200 (for example a redirect or a 404), checking the status
  check uses the status that fits

If an eval run cannot be launched (sandbox, permissions), stop under run rule 4.

When skill-creator reaches its human review step, generate its review viewer, then stop and
ask the user to review the eval results. Tell them where the viewer output is. This is a
planned pause, not a failure: wait in the same session for their feedback, apply it as
skill-creator describes (re-running evals as it directs), and pause for review again each
time skill-creator asks for it. Continue to step 4 only once the user says they are happy.
If the viewer can't be generated or opened, stop under run rule 4.

### 4. Description optimisation and packaging

Run skill-creator's description optimisation on the skill and put the resulting description
into the `SKILL.md` frontmatter, written as step 2 describes (single line, single-quoted).
Keep its working files in `$TMPDIR`.

The optimiser (`python3 -m scripts.run_loop ...`) has been blocked by the sandbox before
(`PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`), and
packaging has failed before with `ModuleNotFoundError: No module named 'yaml'`. If the
optimiser or the packager is blocked by the sandbox or a missing package, do not stop: give
the user the exact command (and, for a missing package, the install command such as
`python3 -m pip install pyyaml`), ask them to run it with `! <command>`, wait for them, and
carry on with its output. Record each one under "Commands that needed help" in the stats.
If it still cannot run after the user has tried, stop under run rule 4.

The optimised description must still say the skill is for writing or editing Rails
controller or request specs, and that it is used alongside `writing-rspec`. If the
optimiser's result drops either point, edit the description by hand to add it back,
changing as little of the optimised text as possible.

Then use skill-creator to package the skill, writing the `.skill` file to `$TMPDIR`. Do not
put it in the repo.

### 5. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. In `## Skills`, add
after the `writing-rspec` bullet:

```
- `writing-rspec-controller-specs`: <one line in plain English, written from the finished skill: records in let!, the request first in each example, the status checked first, one example per request>
```

## Verification

1. `bundle exec rake` passes: all specs (including "every shipped skill names itself and
   has a description" and "lists the shipped skills"), plus RuboCop with no offences.
2. `bundle exec exe/planner skills list` prints three lines, for `commit-message`,
   `writing-rspec` and `writing-rspec-controller-specs` in that order, with descriptions
   lined up in one column, and exits 0.
3. Read `lib/planner/skills/writing-rspec-controller-specs/SKILL.md` and confirm:
   - it states every rule in Implementation step 2, including the pointer to
     `writing-rspec` and the `:aggregate_failures` override
   - it has exactly one bad/good pair, matching the code examples in `ITERATION-001.md`
   - its frontmatter has only `name` and `description`
   - the description is on a single line as a single-quoted string, and mentions writing
     or editing controller or request specs and `writing-rspec`
4. Read `lib/planner/skills/writing-rspec-controller-specs/evals/evals.json` and confirm it
   covers the three scenarios in Implementation step 3, with the existing spec inline in
   the edit eval's prompt and no input files.
5. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the
   repo, and `lib/planner/skills/writing-rspec-controller-specs/` contains only `SKILL.md`
   and `evals/evals.json`.
6. `git diff --stat` shows `spec/exe/planner_spec.rb` as the only change under `spec/`, and
   no change under `lib/planner/skills/writing-rspec/`.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/writing-rspec-controller-specs spec/exe/planner_spec.rb README.md docs/plans/202611041013-rspec-controller-skill/ITERATION-001.md docs/plans/202611041013-rspec-controller-skill/PLAN-001.md
```

Write the message to a file and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Ship a controller spec skill with planner

Add a shipped skill with rules for controller and request specs, used
alongside writing-rspec. Records are created with let! instead of in
a before block, and each example makes the request on its first line,
checks the response status first, and holds every expectation about
that request. The records are then created once per request instead
of once per assertion, and a wrong status stops the example early.

The skills list spec now allows any padding after commit-message, as
the new skill name is longer. The README lists the new skill.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-04T11:00:18Z |
| Finished | 2026-11-04T12:01:43Z |
| Elapsed | 1h 1m 25s |
| Model | sonnet |
| Tokens | ~400k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `python3 -m scripts.run_loop --eval-set ... --skill-path ... --model claude-sonnet-5-5 --max-iterations 5 --verbose` | Blocked by the sandbox (`PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`), so the user ran it. The long one-liner I first gave them did nothing when pasted; a short wrapper script worked. | Run the optimiser outside the sandbox, or allow `os.sysconf("SC_SEM_NSEMS_MAX")` in the sandbox. |
| `open <review.html>` (viewer) | Not run: the sandbox blocks `open`, so I generated a static `review.html` and asked the user to open it. | Allow opening local files from the sandbox. |

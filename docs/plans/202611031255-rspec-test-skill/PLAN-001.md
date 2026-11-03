# PLAN-001 — Ship a writing-rspec skill

Ship a second planner skill, `writing-rspec`, under `lib/planner/skills/writing-rspec/`. It
gives the agent two basic RSpec rules for specs it writes or edits. First, every description
string says what the code does (its observable outcome) in the present tense without
"should", not how it does it. Second, no compound matchers (`.and` / `&`): use separate
`expect` lines under `:aggregate_failures` instead. The skill is guidance only, with one
short bad/good example per rule. It is built with the `skill-creator` skill, using the same
process as the commit-message skill (evals, a pause for the user to review them, description
optimisation, packaging). It ships in the gem and is installed with `planner skills install`.
The README Skills section gets a bullet for it. Existing specs in this repo are not changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Skill name and location | `writing-rspec`, at `lib/planner/skills/writing-rspec/SKILL.md`, shipped in the gem. Not copied into this repo's `.claude/skills`. |
| Which descriptions the behaviour rule covers | Every `describe`, `context` and `it` (and `specify` / `example`) string. Exception: examples may be grouped under a `describe '#method'` (or `'.method'`) string naming the method under test. |
| What "behaviour, not implementation" means | Say what the caller or user observes (returned value, output, error raised, side effect). Do not name private methods, internal classes, data structures or how the result is computed. |
| Tense / "should" | Write descriptions in the present tense without "should" (e.g. `it 'returns the total'`, not `it 'should return the total'`). |
| What the `and` rule forbids | RSpec compound matchers: `.and` and `&` (e.g. `expect(x).to eq(1).and include(2)`). `.or` / `|` and the word "and" in description text are not covered. |
| What to do instead of `and` | Write separate `expect` lines in the same example, under `:aggregate_failures`. |
| When the rules apply | To specs the agent writes or edits (new or changed descriptions and assertions). Do not rewrite existing specs that the task does not otherwise touch. |
| This repo's existing `.and` uses (`spec/planner/commands/skills_spec.rb:85`, `:155`) | Leave them. Out of scope. |
| Examples in SKILL.md | Yes: one short bad/good code pair per rule. |
| Enforcement / skill shape | Instructions only. No check script. Only `SKILL.md` and `evals/evals.json`. Frontmatter has only `name` and `description`. |
| skill-creator process | Same as the commit-message plan: draft, write and run evals (skill-creator's default count), pause for user review in the viewer, iterate, description optimisation, package. Workspace, benchmark, viewer and `.skill` output go in `$TMPDIR`. `evals/evals.json` is committed. Stop under run rule 4 if any step can't run. |
| README | Add a `writing-rspec` bullet to the existing `## Skills` section. |
| TODO | No change to `docs/TODO.md`. |

## Files to create / change

```
lib/planner/skills/writing-rspec/SKILL.md          new: the skill
lib/planner/skills/writing-rspec/evals/evals.json  new: skill-creator's evals
README.md                                          new bullet in the Skills section
```

No Ruby or spec changes. `SkillCatalog`, `planner skills list/install` and the gemspec
already pick up a new skill folder. `spec/planner/skill_catalog_spec.rb` already checks that
every shipped skill's `name` matches its folder and that its description is not blank.
`writing-rspec` sorts after `commit-message`, so the exe spec's `/\Acommit-message  \S/`
assertion still passes unchanged.

## Implementation

### 1. Build the skill with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to create the skill
directly at `lib/planner/skills/writing-rspec/`. Keep all workspace, benchmark, grading and
viewer output under `$TMPDIR` (for example `$TMPDIR/writing-rspec-workspace/`), never in the
repo.

`SKILL.md` must have this frontmatter, and only these keys:

```
---
name: writing-rspec
description: <written and then optimised with skill-creator>
---
```

Write the description on a single line as a single-quoted YAML string, escaping any `'`
inside it as `''`, as `lib/planner/skills/commit-message/SKILL.md` does. Do not use a YAML
block scalar (`|` or `>`).

The description must say the skill is for writing or editing RSpec specs, and that it should
be used whenever the agent adds or changes `describe`, `context` or `it` blocks or
expectations.

The body of `SKILL.md` must state every rule below and nothing that contradicts them. Keep
it concise.

Scope:

- The rules apply to specs you write or edit. Do not rewrite existing specs that the task
  does not otherwise touch.

Descriptions describe behaviour, not implementation:

- Every `describe`, `context`, `it`, `specify` and `example` string says what the caller or
  user observes: the value returned, the output, the error raised or the side effect.
- Do not name private methods, internal classes, data structures, or how the result is
  computed.
- Exception: you may group examples under `describe '#method'` (or `'.method'`) naming the
  method under test. `describe SomeClass` with a constant is also fine.
- Write in the present tense without "should": `it 'returns the total'`, not
  `it 'should return the total'`.

No compound matchers:

- Do not chain expectations with `.and` or `&`.
- Instead, write one `expect` per line in the same example and tag the example or group
  `:aggregate_failures` so every failure is reported.

Include one short bad/good pair per rule. Use these, or something equally short:

```ruby
# Bad
it 'calls #apply_discount and memoizes @total' do

# Good
it 'returns the total after the discount' do
```

```ruby
# Bad
expect(out).to start_with('Done').and include('3 files')

# Good
it 'reports the files it wrote', :aggregate_failures do
  expect(out).to start_with('Done')
  expect(out).to include('3 files')
end
```

End with a short "Before you finish" step: check each description and expectation you wrote
or changed against the rules and fix any that break them.

Do not add any file other than `SKILL.md` and `evals/evals.json`.

### 2. Evals

Use skill-creator to write its default number of eval prompts into
`lib/planner/skills/writing-rspec/evals/evals.json`, run them, grade them, and iterate on
`SKILL.md` until skill-creator's results show the rules are followed. Between them, the evals
must cover:

- a prompt that tempts implementation-focused or "should" descriptions
- a prompt that tempts a compound `.and` matcher
- a prompt that edits an existing spec file that already breaks a rule elsewhere, checking
  the agent fixes only what it writes or changes. Put the existing spec inline in the eval's
  prompt text. Do not give the eval input files, and do not add an `evals/files/` folder or
  any other file to the skill folder.

If an eval run cannot be launched (sandbox, permissions), stop under run rule 4.

When skill-creator reaches its human review step, generate its review viewer, then stop and
ask the user to review the eval results. Tell them where the viewer output is. This is a
planned pause, not a failure: wait in the same session for their feedback, apply it as
skill-creator describes (re-running evals as it directs), and pause for review again each
time skill-creator asks for it. Continue to step 3 only once the user says they are happy.
If the viewer can't be generated or opened, stop under run rule 4.

### 3. Description optimisation and packaging

Run skill-creator's description optimisation on the skill and put the resulting
description into the `SKILL.md` frontmatter, written as step 1 describes (single line,
single-quoted). Keep its working files in `$TMPDIR`. If it cannot run, stop under run
rule 4.

The optimised description must still say the skill is for writing or editing RSpec specs,
and that it should be used whenever the agent adds or changes `describe`, `context` or `it`
blocks or expectations. If the optimiser's result drops or loses either point, edit the
description by hand to add it back, changing as little of the optimised text as possible.

Then use skill-creator to package the skill, writing the `.skill` file to `$TMPDIR`. Do not
put it in the repo.

### 4. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. In `## Skills`, add
after the `commit-message` bullet:

```
- `writing-rspec`: <one line in plain English: descriptions say what the code does, not how, in the present tense; separate expects instead of `.and` matchers>
```

Write the one-line explanation from the finished skill.

## Verification

1. `bundle exec rake` passes: all specs (including the existing "every shipped skill names
   itself and has a description" and "lists the shipped skills" examples), plus RuboCop
   with no offences.
2. `bundle exec exe/planner skills list` prints two lines, `commit-message  ...` then
   `writing-rspec  ...`, and exits 0.
3. Read `lib/planner/skills/writing-rspec/SKILL.md` and confirm it states every rule in
   Implementation step 1, has one bad/good pair per rule, has only `name` and
   `description` in its frontmatter, and has the description on a single line as a
   single-quoted string that mentions writing or editing RSpec specs and adding or changing
   `describe`, `context` or `it` blocks or expectations.
4. Read `lib/planner/skills/writing-rspec/evals/evals.json` and confirm it covers the three
   scenarios in Implementation step 2: an eval tempting implementation-focused or "should"
   descriptions, an eval tempting a compound `.and` matcher, and an eval that edits an
   existing spec given inline in its prompt, with no input files.
5. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the
   repo, and `lib/planner/skills/writing-rspec/` contains only `SKILL.md` and
   `evals/evals.json`.
6. `git diff --stat` shows no change under `spec/`.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/writing-rspec README.md docs/plans/202611031255-rspec-test-skill/ITERATION-001.md docs/plans/202611031255-rspec-test-skill/PLAN-001.md
```

Write the message to a file and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Ship a writing-rspec skill with planner

Add a second shipped skill with two basic RSpec rules. Spec
descriptions say what the code does, in the present tense, rather
than how it does it. Expectations are written as separate expect
lines instead of being chained with and, so each failure is reported
on its own.

The README lists the new skill.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-03T14:01:42Z |
| Finished | 2026-11-03T14:37:42Z |
| Elapsed | 36m 0s |
| Model | sonnet |
| Tokens | ~330k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `python3 -m scripts.run_loop --eval-set ... --skill-path lib/planner/skills/writing-rspec --model claude-sonnet-5-5 --max-iterations 5` | Failed in the sandbox with `PermissionError: [Errno 1] Operation not permitted` from `ProcessPoolExecutor`. The user ran it outside the sandbox through a script, after a first paste was split across lines. | Allow multiprocessing semaphores in the sandbox, or allow `python3 -m scripts.run_loop` to run unsandboxed |

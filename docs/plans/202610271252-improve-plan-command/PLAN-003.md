# PLAN-003 — Make the plan's commit optional, and have run respect it

At the moment, every plan that `planner plan` writes ends with a Commit section that has a
stage list and a suggested message, so `planner run` always commits. This change makes the
commit optional. When the other decisions are settled and before it writes the plan file, the
plan agent asks the user whether they want the change committed. It asks every time and
records the answer as a `Commit` row in the Decisions table. If the answer is no, the Commit
section holds a fixed do-not-commit text. The run prompt gets a new rule 8: when the plan's
Commit section says "Do not commit.", run stages nothing and commits nothing. The plan and run
specs, `docs/GLOSSARY.md` and `README.md` are updated to match.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| When the plan agent asks about committing | After every other question has an answer, before it writes the plan file |
| Ask every time? | Yes, even if an earlier plan in the folder answered it. An earlier answer is not precedent. |
| Record the choice | A `Commit` row (`Yes` or `No`) in the plan's Decisions table |
| Plan's Commit section when the answer is no | Keep the section. Its whole body is exactly `Do not commit. Do not stage any files. Leave every change in the working tree.` |
| Plan's Commit section when the answer is yes | Unchanged: stage list, suggested message, commit only after implementing and verifying, and list the TOC if it exists |
| Where run's do-not-commit instruction comes from | The plan's Commit section, plus a new run rule that acts on it |
| Run rule wording | A new rule 8, plus "unless rule 8 applies" added to rule 7's staging sentence (exact text below) |
| Run staging when not committing | Stage nothing. Every change stays unstaged, including the plan file and the TOC. |
| Plan-structure placeholder under `## Commit` | Mention both cases (exact text below) |
| Step 4 wording in the plan prompt | As given below |
| Specs | Add content checks to `plan_spec.rb` and `run_spec.rb` |
| Glossary | Add one sentence to the plan file entry (exact text below) |
| README | Update it with the `update-readme` skill |
| `docs/TODO.md` | No change |
| Commit | Yes |

## Files to create / change

```
lib/planner/prompts/plan.md.erb       step 4 and the Commit placeholder
lib/planner/prompts/run.md.erb        rule 7 staging sentence, new rule 8
spec/planner/commands/plan_spec.rb    new content checks
spec/planner/commands/run_spec.rb     new content check
docs/GLOSSARY.md                      plan file entry
README.md                             via the update-readme skill
```

## Implementation

Prerequisite: PLAN-001 and PLAN-002 are committed. `git status` must not list
`lib/planner/prompts/plan.md.erb` as modified before you start. If it does, stop and tell the
user.

### `lib/planner/prompts/plan.md.erb`

Replace step 4 (the four lines starting `4. **End the plan with a Commit section.**` and ending
`it in what to stage.`) with exactly:

```
4. **End the plan with a Commit section.** Once every other question has an answer,
   and before you write `<%= plan_file %>`, ask the user whether they want this plan's
   change committed. Ask every time, even if an earlier plan in the folder answered
   it. Record the answer as a `Commit` row (`Yes` or `No`) in the Decisions table.
   - If yes, state exactly what to stage and give a suggested commit message, with
     the instruction that the commit happens only after the plan's change has
     actually been made (implemented and verified), never before. If `<%= toc_file %>` exists, list
     it in what to stage.
   - If no, write exactly this as the whole body of the Commit section:
     `Do not commit. Do not stage any files. Leave every change in the working tree.`
```

Step 5 stays as it is.

In the plan structure block, replace:

```
<what to stage and a suggested commit message, contingent on verification passing>
```

with:

```
<what to stage and a suggested commit message, contingent on verification passing, or the
do-not-commit text from step 4>
```

Change nothing else.

### `lib/planner/prompts/run.md.erb`

In rule 7, replace:

```
   Verification step passes and before the Commit
   step, and stage `<%= plan_file %>` and every file
```

with:

```
   Verification step passes and before the Commit
   step, and, unless rule 8 applies,
   stage `<%= plan_file %>` and every file
```

Straight after rule 7's last line (`   stop, do all three but still do not commit.`), add:

```
8. If the plan's Commit section says
   "Do not commit.", do not stage or commit
   anything. Skip the Commit step and leave every
   change, including `<%= plan_file %>` and
   `<%= toc_file %>`, unstaged.
```

Change nothing else. Rule 1 doesn't need to change: skipping the Commit step adds nothing.

### `spec/planner/commands/plan_spec.rb`

Add these two examples after `'hands the rendered prompt to the agent'`:

```ruby
  it 'asks whether to commit every time and records the answer' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    expect(agent.calls.first.last).to include("ask the user whether they want this plan's",
                                              'Ask every time, even if an earlier plan in the folder answered',
                                              'Record the answer as a `Commit` row')
  end

  it 'gives the do-not-commit text for a plan that is not committed' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    expect(agent.calls.first.last).to include(
      '- If no, write exactly this as the whole body of the Commit section:',
      '`Do not commit. Do not stage any files. Leave every change in the working tree.`'
    )
  end
```

The existing `'updates the table of contents when it exists'` example has to keep passing
unchanged. The new step 4 keeps `If `docs/plans/x/TABLE-OF-CONTENT.md` exists, list` on one
line.

### `spec/planner/commands/run_spec.rb`

Inside `describe 'the prompt'`, after the example
`'writes the deviations and stats on finish and on stop, staging the plan file and fixed files'`, add:

```ruby
    it 'stages and commits nothing when the plan says not to commit' do
      expect(prompt).to include('step, and, unless rule 8 applies,',
                                "8. If the plan's Commit section says",
                                '"Do not commit.", do not stage or commit',
                                'change, including `PLAN-001.md` and',
                                '`./TABLE-OF-CONTENT.md`, unstaged.')
    end
```

The existing rule 7 example (`'stage `PLAN-001.md` and every file'`) has to keep passing
unchanged.

### `docs/GLOSSARY.md`

Replace:

```
- **plan file**: `PLAN-<NNN>.md`. The implementation plan written from an iteration file by `planner plan`.
```

with:

```
- **plan file**: `PLAN-<NNN>.md`. The implementation plan written from an iteration file by `planner plan`. Its Commit section says what to commit, or says not to commit, as the user chose when planning.
```

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Keep the edit small: edit the existing
`planner plan` and `planner run` bullets (README lines 18–19) in place. The plan bullet should
say that the agent asks whether to commit. The run bullet should say that it commits only when
the plan says to.

## Verification

1. `bundle exec rake` passes: all specs, including the new ones, and RuboCop with no offences.
2. Render the plan prompt and read step 4 and the Commit placeholder. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/ITERATION-003.md"])'`
   Step 4 reads as given above, with `…/PLAN-003.md` filled in and no `<%` left anywhere.
3. Render the run prompt without starting the agent:
   `bundle exec exe/planner run -p docs/plans/202610271252-improve-plan-command/PLAN-003.md`
   In the `prompt` value, rule 7 contains "unless rule 8 applies" and rule 8 follows it, with the
   plan path and `…/TABLE-OF-CONTENT.md` filled in.
4. `git diff --stat` lists only the files under "Files to create / change" (plus this plan file,
   once the stats are added).

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib/planner/prompts/plan.md.erb lib/planner/prompts/run.md.erb spec/planner/commands/plan_spec.rb spec/planner/commands/run_spec.rb docs/GLOSSARY.md README.md docs/plans/202610271252-improve-plan-command/ITERATION-003.md docs/plans/202610271252-improve-plan-command/PLAN-003.md
```

Write the message to a file and commit with `git commit -F <file>`. Suggested message:

```
Make the plan's commit optional

The plan agent now asks every time whether the change should be
committed, and records the answer in the plan. A plan that is not to
be committed says so in its Commit section, and the run prompt then
stages and commits nothing.
```

## Deviations

- RuboCop RSpec/ExampleLength and Layout/LineLength failed because the do-not-commit example given in the plan had 6 lines; changed `spec/planner/commands/plan_spec.rb` to read the prompt into a local variable and use two single-line `include` expectations

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-10T21:20:55Z |
| Finished | 2026-11-10T21:21:27Z |
| Elapsed | 32s |
| Model | sonnet |
| Tokens | ~40k (estimate) |

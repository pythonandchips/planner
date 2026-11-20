# PLAN-004 — Check with the user before adding a manual verification step

Plans written by `planner plan` sometimes include manual Verification steps, such as checking
something in a browser, that verification the user runs outside the agent after the run may
already cover. This change adds a new step 4 to the plan prompt `lib/planner/prompts/plan.md.erb`:
prefer automated checks, and ask the user about each manual step before adding it, keeping only
the ones they approve. The Commit step becomes step 5 and the table of contents step becomes
step 6. `spec/planner/commands/plan_spec.rb` gets a content check, and the matching item is
removed from `docs/TODO.md`. The run prompt, README and glossary do not change.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| What counts as a manual step | Any Verification step a person does rather than the agent that runs the plan (browser checks, starting a real session, looking at a UI) |
| When the agent asks | A separate step after every other question in step 2 has an answer, before the Commit question |
| A manual step the user declines | Left out of the plan entirely. Only its Decisions row records it. |
| Prefer automated checks | Yes. Propose a manual step only when no automated check covers it. |
| Placement in the prompt | New step 4. Commit becomes step 5, table of contents becomes step 6. |
| Recording the answers | One Decisions row per proposed manual step: `Manual check: <step>` with `Include` or `Leave out` |
| No manual step to propose | Do not ask |
| Step 4 wording | Exactly as given under Implementation |
| Plan structure Verification placeholder | Unchanged |
| Run prompt (`run.md.erb`) | No change |
| Specs | Add a content check to `plan_spec.rb`, and update the table of contents example for the renumbering |
| `docs/TODO.md` | Remove the "[Skill] always confirm if manual verification steps" bullet |
| README / glossary | No change |
| Staging `docs/TODO.md` | Stage the whole file, including the other uncommitted bullets already in it |
| Commit | Yes |

## Files to create / change

```
lib/planner/prompts/plan.md.erb       new step 4, renumber steps 4–5, Commit placeholder step reference
spec/planner/commands/plan_spec.rb    new example, renumbered TOC example
docs/TODO.md                          remove one bullet
```

## Implementation

Prerequisite: PLAN-003 is committed. `git status` must not list
`lib/planner/prompts/plan.md.erb` as modified before you start. If it does, stop and tell the
user.

### `lib/planner/prompts/plan.md.erb`

Insert this new step straight after step 3 (after the line
`   follow-up question.`) and before the line starting `4. **End the plan with a Commit section.**`:

```
4. **Check with the user before adding a manual verification step.** A manual
   step is any Verification step a person does rather than the agent that runs
   the plan, such as checking a page in a browser or starting a real session.
   Prefer an automated check (a spec or a command), and propose a manual step
   only when no automated check covers it. Once every other question in step 2
   has an answer, and before you ask about committing in step 5, ask the user
   about each manual step you want to add, because verification the user runs
   outside the agent after the run may already cover it. Add only the steps the
   user approves, and leave the others out of the plan entirely. Record each as
   a `Manual check: <step>` row (`Include` or `Leave out`) in the Decisions
   table. If you have no manual step to propose, do not ask.
```

Renumber the following two steps. Replace:

```
4. **End the plan with a Commit section.** Once every other question has an answer,
```

with:

```
5. **End the plan with a Commit section.** Once every other question has an answer,
```

and replace:

```
5. **Update the table of contents.** After writing `<%= plan_file %>`, update
```

with:

```
6. **Update the table of contents.** After writing `<%= plan_file %>`, update
```

In the plan structure block, replace:

```
do-not-commit text from step 4>
```

with:

```
do-not-commit text from step 5>
```

Change nothing else.

### `spec/planner/commands/plan_spec.rb`

In the example `'updates the table of contents when it exists'`, change
`'5. **Update the table of contents.**'` to `'6. **Update the table of contents.**'`.

Add this example after `'gives the do-not-commit text for a plan that is not committed'`:

```ruby
  it 'checks with the user before adding a manual verification step' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    prompt = agent.calls.first.last
    expect(prompt).to include('4. **Check with the user before adding a manual verification step.**')
    expect(prompt).to include('a `Manual check: <step>` row (`Include` or `Leave out`) in the Decisions')
    expect(prompt).to include('5. **End the plan with a Commit section.**')
  end
```

### `docs/TODO.md`

Delete this line:

```
- [Skill] always confirm if manual verification steps. Manual verification steps should be minimised
```

Leave every other line, including the other uncommitted bullets, as it is.

## Verification

1. `bundle exec rake` passes: all specs, including the new one, and RuboCop with no offences.
2. Render the plan prompt and read steps 3 to 6. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/ITERATION-004.md"])'`
   Steps run 1 to 6 in order, step 4 reads as given above, the Commit placeholder says
   "from step 5", and no `<%` is left anywhere.
3. `grep -n "manual verification" docs/TODO.md` prints nothing.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib/planner/prompts/plan.md.erb spec/planner/commands/plan_spec.rb docs/TODO.md docs/plans/202610271252-improve-plan-command/ITERATION-004.md docs/plans/202610271252-improve-plan-command/PLAN-004.md
```

This stages the whole of `docs/TODO.md`, including the other bullets already added to it. Write
the message to a file and commit with `git commit -F <file>`. Suggested message:

```
Check with the user before adding a manual verification step

Plans sometimes ask for manual checks that verification run outside
the agent already covers. The plan prompt now prefers automated
checks and asks about each manual step before adding it, recording
each answer in the plan's Decisions table.
```

## Deviations

- RuboCop `RSpec/ExampleLength` failed because the new example had 6 lines (limit 5); changed
  `spec/planner/commands/plan_spec.rb` to add an inline `# rubocop:disable RSpec/ExampleLength`
  on the example, as the file already does for other examples

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-20T08:43:04Z |
| Finished | 2026-11-20T08:43:31Z |
| Elapsed | 27s |
| Model | sonnet |
| Tokens | ~30k (estimate) |

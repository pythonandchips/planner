# PLAN-005 — Attribute the plan, review and run models in the commit

Today a plan's suggested commit message can come out attributed to the wrong model: the
`commit-message` skill asks for a single `Assisted-by:` trailer taken from the committing agent's
own context, so either the plan model or the run model gets credited, never both. This change
gives each agent that worked on the change its own trailer line, tagged with its role. The plan
agent ends the suggested message with `Assisted-by: <agent> (<model>, plan)`. Every review of a
plan adds `Assisted-by: <agent> (<model>, review)` to that message. The run agent keeps those
lines and adds `Assisted-by: <agent> (<model>, run)` last. A new run rule says these lines
replace the skill's single trailer, so the skill and the run prompt don't conflict. The skill
itself does not change. Scope: `plan.md.erb`, `review.md.erb`, `run.md.erb` and their specs. No
README, glossary, TODO or Ruby code changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| How the models reach the commit | Each agent adds its own line. The plan agent writes its line in the plan's suggested commit message. The review agent appends its line to that message in the plan. The run agent adds its line when committing. |
| Line format | `Assisted-by: <agent> (<model>, <role>)`, role `plan`, `review` or `run`, e.g. `Assisted-by: Claude Code (Claude Opus 5.5, plan)` |
| Same model in two roles | One line per role, even when the model repeats. Each review adds its own line. |
| Line order | Plan, then reviews in the order they ran, then run |
| Compatibility with the `commit-message` skill | The skill is not changed. A new run rule says the role lines replace the skill's single `Assisted-by:` trailer, the skill's other rules still apply, and no `Co-Authored-By:` line is added. |
| When the review agent adds its line | On every review of a `PLAN-<N>.md`, whether or not suggestions are applied. Not for `FINDINGS-<N>.md` reviews (`review_findings.md.erb` is unchanged). Nothing is added when the plan's Commit section says "Do not commit." |
| What the run agent does with the message | Start from the plan's suggested message, keep every `Assisted-by:` line in it in order, add its own run line last. A plan with no `Assisted-by:` lines just gets the run line. |
| How each agent names its agent and model | From its own system context. If it cannot tell, it asks the user and does not guess. Ruby passes nothing new. |
| Prompt wording | Exactly as given under Implementation |
| Specs | Content checks in `plan_spec.rb`, `review_spec.rb` and `run_spec.rb` |
| README / glossary / `docs/TODO.md` | No change |
| Manual check: real plan → review → run, then check `git log -1` for the three lines | Leave out |
| Commit | Yes |

## Files to create / change

```
lib/planner/prompts/plan.md.erb       step 5 "If yes" bullet: plan attribution line
lib/planner/prompts/review.md.erb     rules 1 and 2, new "Attribution" section
lib/planner/prompts/run.md.erb        new rule 9
spec/planner/commands/plan_spec.rb    new example
spec/planner/commands/review_spec.rb  new example
spec/planner/commands/run_spec.rb     new example
```

## Implementation

Prerequisite: PLAN-004 is committed. `git status` must not list any file under
`lib/planner/prompts/` as modified before you start. If it does, stop and tell the user.

### `lib/planner/prompts/plan.md.erb`

In step 5, replace:

```
     actually been made (implemented and verified), never before. If `<%= toc_file %>` exists, list
     it in what to stage.
```

with:

```
     actually been made (implemented and verified), never before. If `<%= toc_file %>` exists, list
     it in what to stage. End the suggested message with a blank line, then
     `Assisted-by: <agent> (<model>, plan)`, taking the agent and model from your
     own system context, for example `Assisted-by: Claude Code (Claude Opus 5.5, plan)`.
     If you cannot tell what they are, ask the user. Do not guess. Add no other
     `Assisted-by:` or `Co-Authored-By:` line, because the review and run agents
     add their own.
```

The line `If `<%= toc_file %>` exists, list` must stay on one line (an existing spec depends on
it). Change nothing else.

### `lib/planner/prompts/review.md.erb`

Replace rules 1 and 2:

```
1. Do not modify repository files, except the plan
   and the table of contents as described under
   "Applying suggestions" and "Table of contents".
2. You may write only `<%= review_file %>`,
   `<%= source_file %>` when the user asks you to
   apply suggestions, and `<%= toc_file %>` as
   described under "Table of contents".
```

with:

```
1. Do not modify repository files, except the plan
   and the table of contents as described under
   "Applying suggestions", "Attribution" and
   "Table of contents".
2. You may write only `<%= review_file %>`,
   `<%= source_file %>` when the user asks you to
   apply suggestions or as described under
   "Attribution", and `<%= toc_file %>` as
   described under "Table of contents".
```

Then add this new section straight before the line `## Summary for the user`, with one blank line
before and after it:

```
## Attribution

After writing `<%= review_file %>` and before
updating `<%= toc_file %>`, add one line to the
suggested commit message in the Commit section of
`<%= source_file %>`:

`Assisted-by: <agent> (<model>, review)`

Take the agent and model from your own system
context, for example
`Assisted-by: Claude Code (Claude Opus 5.5, review)`.
If you cannot tell what they are, ask the user. Do
not guess. Put the line straight after the last
`Assisted-by:` line in the message. When the message
has none, put it after the message's last line, with
a blank line before it. Add it even when an earlier
review has added one, and change nothing else in
the plan. If the Commit section says
"Do not commit.", add nothing.
```

Change nothing else. Do not touch `lib/planner/prompts/review_findings.md.erb`.

### `lib/planner/prompts/run.md.erb`

Straight after rule 8's last line (`   `<%= toc_file %>`, unstaged.`) and before the blank line
and `## Deviations`, add:

```
9. When you commit, start from the plan's suggested
   commit message. Keep every `Assisted-by:` line
   already in it, in order, and add your own after
   them: `Assisted-by: <agent> (<model>, run)`.
   Take the agent and model from your own system
   context, for example
   `Assisted-by: Claude Code (Claude Sonnet 5.5, run)`.
   If you cannot tell what they are, ask the user.
   Do not guess. When the message has no
   `Assisted-by:` line, add yours after its last line
   with a blank line before it. These lines replace
   the single `Assisted-by:` trailer of the
   `commit-message` skill. Follow its other rules,
   and do not add a `Co-Authored-By:` line.
```

Change nothing else.

### `spec/planner/commands/plan_spec.rb`

Add this example after `'checks with the user before adding a manual verification step'`:

```ruby
  it 'ends the suggested commit message with the plan agent attribution' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    expect(agent.calls.first.last).to include('`Assisted-by: <agent> (<model>, plan)`, taking the agent and model',
                                              '`Assisted-by:` or `Co-Authored-By:` line, because the review and run')
  end
```

### `spec/planner/commands/review_spec.rb`

Inside `describe 'the prompt with no lens'`, after the example
`'lets the agent apply suggestions to the plan'`, add:

```ruby
    it 'adds its attribution line to the plan commit message' do
      expect(prompt).to include('"Applying suggestions", "Attribution" and', "## Attribution\n\nAfter writing",
                                "`Assisted-by: <agent> (<model>, review)`\n", 'Add it even when an earlier',
                                '"Do not commit.", add nothing.')
    end
```

The existing `'lets the agent apply suggestions to the plan'` and
`'updates the table of contents when it exists'` examples must keep passing unchanged.

### `spec/planner/commands/run_spec.rb`

Inside `describe 'the prompt'`, after the example
`'stages and commits nothing when the plan says not to commit'`, add:

```ruby
    it 'keeps the plan and review attribution and adds its own' do
      expect(prompt).to include("9. When you commit, start from the plan's suggested",
                                'them: `Assisted-by: <agent> (<model>, run)`.',
                                'the single `Assisted-by:` trailer of the',
                                'and do not add a `Co-Authored-By:` line.')
    end
```

## Verification

1. `bundle exec rake` passes: all specs, including the three new ones, and RuboCop with no
   offences.
2. Render the plan prompt and read step 5. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/ITERATION-005.md"])'`
   The "If yes" bullet ends with the `Assisted-by: <agent> (<model>, plan)` text as given above,
   and no `<%` is left anywhere.
3. Render the run prompt without starting the agent:
   `bundle exec exe/planner run -p docs/plans/202610271252-improve-plan-command/PLAN-005.md`
   In the `prompt` value, rule 9 follows rule 8 and reads as given above.
4. Render the review prompt without starting the agent. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def default_review_model = "x"; def review(x, **) = puts(x) }.new; Planner::Commands::Review.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/PLAN-005.md"])'`
   Rules 1 and 2 read as given above. The `## Attribution` section reads as given above and
   sits straight before `## Summary for the user`, after the `## Report` section, with one blank
   line before and after it. No `<%` is left anywhere.
5. `git status --short` lists only the files under "Files to create / change", plus
   `docs/plans/202610271252-improve-plan-command/ITERATION-005.md`, this plan file and any
   `REVIEW-005*.md` files in the same folder. `lib/planner/skills/commit-message/SKILL.md` and
   `lib/planner/prompts/review_findings.md.erb` are not in it.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib/planner/prompts/plan.md.erb lib/planner/prompts/review.md.erb lib/planner/prompts/run.md.erb spec/planner/commands/plan_spec.rb spec/planner/commands/review_spec.rb spec/planner/commands/run_spec.rb docs/plans/202610271252-improve-plan-command/ITERATION-005.md docs/plans/202610271252-improve-plan-command/PLAN-005.md
```

Write the message to a file and commit with `git commit -F <file>`. Suggested message:

```
Credit the plan, review and run models in commits

A plan's commit was credited to a single model, so the model that
planned the change or the one that ran it was often missing or wrong.
Each agent now adds its own Assisted-by line tagged with its role:
the plan agent in the suggested message, each plan review after it,
and the run agent last when it commits. The run prompt says these
lines replace the commit-message skill's single trailer.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-24T12:42:10Z |
| Finished | 2026-11-24T12:42:40Z |
| Elapsed | 30s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

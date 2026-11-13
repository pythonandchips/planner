# PLAN-004 — Read the table of contents before the rest of the plan folder

Step 1 of the `plan` and `explore` prompts reads every earlier file in the plan folder, which
costs tokens. Change that step so the agent reads the brief, then reads `TABLE-OF-CONTENT.md`
if it exists and only the `PLAN-*.md` and `FINDINGS-*.md` files it lists that look relevant.
Without a table of contents, the agent reads every `PLAN-*.md` and `FINDINGS-*.md`. In both
cases it no longer reads the folder's other `ITERATION-*.md` files. Specs, the README and the
glossary are updated. No Ruby code, tool list or other prompt changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Which prompts change | Only step 1 of `plan.md.erb` and step 1 of `explore.md.erb`. The shared partial's "Read every `PLAN-*.md` … for its status" line and plan's "Check sibling files" note stay as they are |
| Always read | The brief (the iteration file) only |
| Which files to choose from, with a table of contents | Listed `PLAN-*.md` and `FINDINGS-*.md` files that look relevant to the brief, in both prompts. Never other `ITERATION-*.md` files: they are only briefs |
| Files in the folder the table of contents does not list | Ignored: not read in step 1 |
| Skipped listed files | The agent may read one later if a question turns on it |
| No table of contents | Read every `PLAN-*.md` and `FINDINGS-*.md` in the folder, and no other `ITERATION-*.md` files, in both prompts (plan now reads `FINDINGS-*.md` too) |
| Specs | Add one example each to `plan_spec.rb` and `explore_spec.rb` for the new wording |
| README and glossary | Update the `planner toc` bullet (via the `update-readme` skill) and the **table of contents** glossary entry |
| Commit | Yes |

## Files to create / change

```
lib/planner/prompts/plan.md.erb       step 1
lib/planner/prompts/explore.md.erb    step 1
spec/planner/commands/plan_spec.rb    new example
spec/planner/commands/explore_spec.rb new example
README.md                             `planner toc` bullet
docs/GLOSSARY.md                      **table of contents** entry
```

## Implementation

### 1. `lib/planner/prompts/plan.md.erb`

Replace step 1 (the four lines from `1. **Read the whole folder, not just the one file.**` to
`   something to ask about again.`) with exactly:

```
1. **Read the brief, then the plans and findings it builds on.** Read
   `<%= iteration_file %>`. Do not read the folder's other `ITERATION-*.md` files. If
   `<%= toc_file %>` exists, read it. In this step, read only the `PLAN-*.md` and
   `FINDINGS-*.md` files it lists that look relevant to the brief, and no file in the
   folder it does not list. If a question later turns on a listed file you skipped,
   read it then. If `<%= toc_file %>` does not exist, read every `PLAN-*.md` and
   `FINDINGS-*.md` in `<%= folder %>/`. Earlier plans and findings record decisions that
   still apply. Treat them as established context, not something to ask about again.
```

Change nothing else in the file.

### 2. `lib/planner/prompts/explore.md.erb`

Replace step 1 (the seven lines from `1. **Read the whole folder, not just the one file.**`
to `   again.`) with exactly:

```
1. **Read the brief, then the plans and findings it
   builds on.** Read `<%= iteration_file %>`. Do not
   read the folder's other `ITERATION-*.md` files. If
   `<%= toc_file %>` exists, read it. In this step,
   read only the `PLAN-*.md` and `FINDINGS-*.md` files
   it lists that look relevant to the brief, and no
   file in the folder it does not list. If a question
   later turns on a listed file you skipped, read it
   then. If `<%= toc_file %>` does not exist, read
   every `PLAN-*.md` and `FINDINGS-*.md` in
   `<%= folder %>/`. Earlier plans and findings record
   decisions that still apply. Treat them as
   established context, not something to ask about
   again.
```

Change nothing else in the file. `toc_file` and `folder` are already passed to both
templates.

### 3. `spec/planner/commands/plan_spec.rb`

Add an example next to the existing table of contents example, in the same style
(`write_iteration('ITERATION-001.md')`, `command.call(['docs/plans/x/ITERATION-001.md'])`,
`prompt = agent.calls.first.last`):

```ruby
it 'reads the table of contents before the other plan folder files' do
  write_iteration('ITERATION-001.md')
  command.call(['docs/plans/x/ITERATION-001.md'])

  prompt = agent.calls.first.last
  expect(prompt).to include("Do not read the folder's other `ITERATION-*.md` files.",
                            '`docs/plans/x/TABLE-OF-CONTENT.md` exists, read it.',
                            'If a question later turns on a listed file you skipped,',
                            '`docs/plans/x/TABLE-OF-CONTENT.md` does not exist, read every `PLAN-*.md` and')
  expect(prompt).not_to include('Read the whole folder')
end
```

### 4. `spec/planner/commands/explore_spec.rb`

In `describe 'the prompt'`, after `'updates the table of contents when it exists'`, add:

```ruby
it 'reads the table of contents before the other plan folder files' do
  expect(prompt).to include("read the folder's other `ITERATION-*.md` files.",
                            '`docs/plans/x/TABLE-OF-CONTENT.md` exists, read it.',
                            'later turns on a listed file you skipped, read it',
                            '`docs/plans/x/TABLE-OF-CONTENT.md` does not exist, read')
  expect(prompt).not_to include('Read the whole folder')
end
```

The existing `'reads FINDINGS files and has the findings sections'` example keeps passing
(the new step still contains `` `FINDINGS-*.md` ``).

If rubocop flags line length or example length in either spec, wrap the arguments or add
the same `# rubocop:disable RSpec/ExampleLength` comment the existing specs use, without
changing the strings.

### 5. `README.md`

Use the `update-readme` skill. In the `planner toc` bullet, replace
``Once it exists, `planner plan`, `explore`, `review`, `run` and `summarise` keep it up to date (default model `haiku`).``
with exactly:

```markdown
Once it exists, `planner plan`, `explore`, `review`, `run` and `summarise` keep it up to date, and `planner plan` and `explore` read it to choose which earlier plans and findings to read (default model `haiku`).
```

Change nothing else.

### 6. `docs/GLOSSARY.md`

At the end of the **table of contents** entry, after
``…`planner run` and `planner summarise` when it exists.``, append on the same line:

```markdown
 `planner plan` and `planner explore` read it to choose which earlier plans and findings to read.
```

Change nothing else.

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `grep -n "Read the whole folder" lib/planner/prompts/*.erb` prints nothing.
3. `bundle exec ruby -Ilib -e 'require "planner"; puts Planner::TableOfContent.path("docs/plans/x")'`
   still prints `docs/plans/x/TABLE-OF-CONTENT.md` (sanity check that nothing else moved).
4. `git status` shows changes only to the six files above, plus this folder's
   `ITERATION-004.md` and `PLAN-004.md` (other untracked files that were there before are
   left alone).

## Commit

Commit only after every change above is made and every Verification step passes. Do not
commit before.

Stage:

```
lib/planner/prompts/plan.md.erb
lib/planner/prompts/explore.md.erb
spec/planner/commands/plan_spec.rb
spec/planner/commands/explore_spec.rb
README.md
docs/GLOSSARY.md
docs/plans/202611011829-table-of-content/ITERATION-004.md
docs/plans/202611011829-table-of-content/PLAN-004.md
```

If `docs/plans/202611011829-table-of-content/TABLE-OF-CONTENT.md` exists by then, stage it
too.

Write the message with the `commit-message` skill. Suggested message:

```
Read the table of contents before the rest of a plan folder

Plan and explore read every earlier file in the plan folder, which
gets expensive as a folder grows. Read the brief, then the table of
contents if there is one, and only the plans and findings it lists
that look relevant. Other briefs are no longer read.
```

## Deviations

- RuboCop RSpec/ExampleLength failed because the new plan_spec example had 8 lines (limit 5); changed
  spec/planner/commands/plan_spec.rb to add the `# rubocop:disable RSpec/ExampleLength` comment

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-13T16:16:17Z |
| Finished | 2026-11-13T16:16:49Z |
| Elapsed | 32s |
| Model | sonnet |
| Tokens | ~45k (estimate) |

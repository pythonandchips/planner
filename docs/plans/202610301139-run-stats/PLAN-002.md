## Run summary

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-30T12:21:20Z |
| Finished | 2026-10-30T12:27:43Z |
| Elapsed | 6m 23s |
| Model | sonnet |
| Tokens | ~75k (estimate) |

---

# PLAN-002 — Move the stats to the bottom of files

`planner run` currently tells the agent to add the stats to the very top of the plan file.
This change moves them to the very end, after a `---` rule, the way `planner explore`
already does for the findings file. It also makes the stats instructions in the run and
explore prompts match: the same "keep a list" paragraph, instruction sentence, tokens
placeholder, sub-table heading and leave-out bullet. The fields still differ (run also
records status and timings). Specs, the README `planner run` bullet and the glossary
**stats** entry are updated to match. Existing PLAN files are not changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Scope | Change `planner run` to append, and align `planner explore`'s stats instructions with run's |
| Separator | `---`, blank line, then `## Stats` at the end of the file (as explore does now). Run's trailing `---` after the block is removed |
| Existing PLAN-*.md files with stats or run summary at the top | Leave as-is (historical record) |
| Plan file that already ends with a stats block (re-run) | Not addressed. The prompt only says to add to the end |
| What to align in explore | Instruction sentence, tokens placeholder, leave-out rule format, sub-table heading |
| Sub-table heading and column | `### Commands that needed help` with column `Command`, in both prompts (overrides PLAN-001's "keep both headings") |
| "As you go, keep a list…" paragraph | Run's paragraph, used verbatim in explore too |
| Tokens placeholder | Explore's: `<best estimate, e.g. ~85k> (estimate)` |
| Leave-out rules | Bullets (run's form), explore gets a bullet too |
| Instruction sentence | Run: "Then add the following to the very end of `<file>`, below everything already there, and change nothing else in that file:". Explore: the same without the leading "Then" |
| README | Minimal word swap in the `planner run` bullet: "prepend stats" → "append stats", via the `update-readme` skill |
| Glossary **stats** entry | Update both phrases, wording as in Implementation step 5 |
| Specs | Update and assert the new end-of-file wording in both specs |
| Plan folder files in the commit | `ITERATION-002.md` and `PLAN-002.md` |

## Files to create / change

```
lib/planner/prompts/run.md.erb           stats go at the end; tokens placeholder
lib/planner/prompts/explore.md.erb       align stats section with run
spec/planner/commands/run_spec.rb        'prepends' -> 'appends' and its expectations
spec/planner/commands/explore_spec.rb    'has the stats with the model' expectations
README.md                                `planner run` bullet
docs/GLOSSARY.md                         **stats** entry
```

No other files change. Existing `docs/plans/**/PLAN-*.md` files stay as they are.

## Implementation

### 1. `lib/planner/prompts/run.md.erb`

In the `## Stats` section, make exactly these changes and nothing else:

| Old | New |
| --- | --- |
| `top of `<%= plan_file %>`, above everything already` | `end of `<%= plan_file %>`, below everything already` |
| `\| Tokens \| <best estimate of tokens used, e.g. ~85k> (estimate) \|` | `\| Tokens \| <best estimate, e.g. ~85k> (estimate) \|` |

Inside the fenced block, add `---` and a blank line before `## Stats`, and remove the
`---` and the blank line that currently follow the `| Command |` table row. The fenced
block becomes exactly:

````
```
---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed or Stopped |
| Started | <start time> |
| Finished | <finish time> |
| Elapsed | <finish minus start, e.g. 17m 29s> |
| Model | <%= model %> |
| Tokens | <best estimate, e.g. ~85k> (estimate) |
| Stopped at | <the step you stopped at> |
| Reason | <one sentence on why> |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `<command>` | <what happened> | <the permission or instruction that would let it run unassisted> |
```
````

The "As you go…" paragraph, the two leave-out bullets and Rule 6 stay as they are.

### 2. `lib/planner/prompts/explore.md.erb`

Replace the whole `## Stats` section (from `## Stats` up to, not including,
`## Summary for the user`) with exactly:

````
## Stats

As you go, keep a list of every command you could not
run unassisted: commands that needed the user to approve
a permission prompt, commands denied by permissions or
blocked by the sandbox, commands you asked the user to
run, and commands that failed and had to be run again in
another form.

Add the following to the very end of
`<%= findings_file %>`, below everything already
there, and change nothing else in that file:

```
---

## Stats

| Field | Value |
| --- | --- |
| Model | <%= model %> |
| Tokens | <best estimate, e.g. ~85k> (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `<command>` | <what happened> | <the permission or instruction that would let it run unassisted> |
```

- Leave out the Commands that needed help heading and
  table when there were none.

````

(One blank line between the bullet and `## Summary for the user`.) Step 4 ("ending with the
stats") and the rest of the file stay as they are.

### 3. `spec/planner/commands/run_spec.rb`

Replace:

```ruby
    it 'prepends the stats to the plan file' do
      expect(prompt).to include('top of `PLAN-001.md`, above everything already', "## Stats\n\n| Field | Value |")
    end
```

with:

```ruby
    it 'appends the stats to the plan file' do
      expect(prompt).to include('end of `PLAN-001.md`, below everything already', "---\n\n## Stats\n\n| Field | Value |")
    end
```

Nothing else in the file changes.

### 4. `spec/planner/commands/explore_spec.rb`

Replace the body of `it 'has the stats with the model'` with:

```ruby
      expect(prompt).to include("Add the following to the very end of\n`docs/plans/x/FINDINGS-001.md`, below everything already",
                                "---\n\n## Stats", '| Model | default-explore-model |',
                                "### Commands that needed help\n\n| Command | What happened | Suggested fix |")
      expect(prompt).not_to include('| Status |', '| Started |')
```

Keep the description unchanged. If rubocop flags line length, wrap the arguments to satisfy
it without changing the strings.

### 5. `docs/GLOSSARY.md`

Replace the **stats** entry with:

```markdown
- **stats**: The `## Stats` block the agent adds to a file it writes: model, estimated tokens, and the commands that needed help. `planner run` also records status and timings. Appended to the plan file by `planner run` and to the findings file by `planner explore`.
```

### 6. `README.md`

Use the `update-readme` skill. In the `planner run` bullet change `prepend stats` to
`append stats`. Change nothing else.

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `grep -rn "very top\|above everything\|prepend\|Prepended\|Tool call\|tokens used" lib spec README.md docs/GLOSSARY.md`
   prints nothing.
3. `grep -c "Commands that needed help" lib/planner/prompts/run.md.erb lib/planner/prompts/explore.md.erb`
   prints `2` for each file (the block heading and the leave-out bullet).
4. `git status` shows no changes under `docs/plans/` other than `docs/plans/202610301139-run-stats/`.

## Commit

Commit only after every change above is made and every Verification step passes. Do not commit
before.

Stage:

```
lib/planner/prompts/run.md.erb
lib/planner/prompts/explore.md.erb
spec/planner/commands/run_spec.rb
spec/planner/commands/explore_spec.rb
README.md
docs/GLOSSARY.md
docs/plans/202610301139-run-stats/ITERATION-002.md
docs/plans/202610301139-run-stats/PLAN-002.md
```

Write the message with the `commit-message` skill. Suggested message:

```
Move the stats to the bottom of files

Stats at the top of a plan pushed the plan itself down the page.
`planner run` now appends them after a `---` rule, as `planner
explore` already did, and both prompts describe the stats the same
way, with one "Commands that needed help" table.
```

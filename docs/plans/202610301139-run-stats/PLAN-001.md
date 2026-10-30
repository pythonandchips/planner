## Run summary

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-30T11:54:40Z |
| Finished | 2026-10-30T11:55:05Z |
| Elapsed | 25s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

---

# PLAN-001 — Rename the run summary to stats

"Summary" currently means two things. One is the plain-English reply the agent gives in the session
after `planner explore` or `planner review`. The other is the `## Run summary` block (model, tokens,
timings, commands that needed help) that `planner run` and `planner explore` write into a file.
This change renames the second one to **stats**: the block heading becomes `## Stats`, and the
prompts, specs and README call it "stats". It also adds glossary entries for **summary** and
**stats**. The user-facing summary ("Summary for the user", the REVIEW file's `## Summary`
section) is not changed. Existing PLAN files are not changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| New heading and term | Heading `## Stats`. Prose says "the stats" wherever it said "the run summary" or "the summary" for this block |
| Existing PLAN-*.md files with `## Run summary` | Leave as-is (historical record) |
| README | Update the `planner run` bullet to the new term using the `update-readme` skill. Nothing else in the README changes |
| `docs/TODO.md` uncommitted line ("Have plan ignore files that are gitignored for staging") | Stage it in this commit |
| Glossary wording | Draft A, as written in Implementation step 5, added at the end of `docs/GLOSSARY.md` |
| Glossary **summary** scope | The session reply only. The REVIEW file's `## Summary` section is not mentioned |
| Sub-table headings | Kept: `### Commands that needed help` (run) and `### Tool calls that needed help` (explore) |
| Spec descriptions | Rename `it` descriptions that use "summary" for stats, and update the expected strings. Specs for the user-facing summary are not changed |
| Plan folder files in the commit | `ITERATION-001.md` and `PLAN-001.md` |

## Files to create / change

```
lib/planner/prompts/run.md.erb             rename run summary -> stats
lib/planner/prompts/explore.md.erb         rename run summary -> stats
spec/planner/commands/run_spec.rb          descriptions and expectations
spec/planner/commands/explore_spec.rb      description and expectation
README.md                                  `planner run` bullet
docs/GLOSSARY.md                           add summary and stats entries
```

No other files change. In particular `lib/planner/prompts/review.md.erb`, the "Summary for the user"
sections of `explore.md.erb`, and every existing `docs/plans/**/PLAN-*.md` stay as they are.

## Implementation

### 1. `lib/planner/prompts/run.md.erb`

Make exactly these replacements (keep line wrapping as shown):

| Old | New |
| --- | --- |
| `   else apart from the run summary below. Do not add` | `   else apart from the stats below. Do not add` |
| `6. Write the run summary when you finish and when you` | `6. Write the stats when you finish and when you` |
| `## Run summary` (the section heading above "As you go, keep a list…") | `## Stats` |
| ``To write the summary, run `date -u +%Y-%m-%dT%H:%M:%SZ` `` | ``To write the stats, run `date -u +%Y-%m-%dT%H:%M:%SZ` `` |
| `## Run summary` (inside the fenced block, above `\| Field \| Value \|`) | `## Stats` |

Nothing else in the file changes. `### Commands that needed help` stays.

### 2. `lib/planner/prompts/explore.md.erb`

| Old | New |
| --- | --- |
| `   below, ending with the run summary.` | `   below, ending with the stats.` |
| `## Run summary` (the section heading above "As you go, keep a list…") | `## Stats` |
| `## Run summary` (inside the fenced block, after `---`) | `## Stats` |

Nothing else in the file changes. `### Tool calls that needed help` and the
`## Summary for the user` section stay.

### 3. `spec/planner/commands/run_spec.rb`

- `it 'writes the summary on finish and on stop, staging the plan file'` →
  `it 'writes the stats on finish and on stop, staging the plan file'`, and its expected string
  `'6. Write the run summary when you finish and when you'` →
  `'6. Write the stats when you finish and when you'`.
- `it 'prepends the summary to the plan file'` → `it 'prepends the stats to the plan file'`, and its
  expected string `"## Run summary\n\n| Field | Value |"` → `"## Stats\n\n| Field | Value |"`.
- `it 'puts the chosen model in the run summary'` → `it 'puts the chosen model in the stats'`
  (expectation unchanged).

### 4. `spec/planner/commands/explore_spec.rb`

- `it 'has the run summary with the model'` → `it 'has the stats with the model'`, and its expected
  string `"---\n\n## Run summary"` → `"---\n\n## Stats"`.

Leave `it 'has the summary format'` and its expectations unchanged (that is the user-facing summary).
Leave `review_spec.rb` unchanged.

### 5. `docs/GLOSSARY.md`

Append these two entries at the end of the list, after **agent**:

```markdown
- **summary**: The plain-English reply the agent gives in the session after `planner explore` or `planner review` writes its file, describing what it found. Not written to any file.
- **stats**: The `## Stats` block the agent adds to a file it writes: model, estimated tokens, and the commands or tool calls that needed help. `planner run` also records status and timings. Prepended to the plan file by `planner run`; appended to the findings file by `planner explore`.
```

### 6. `README.md`

Use the `update-readme` skill. In the `planner run` bullet change `prepend a run summary (status,
elapsed time, estimated tokens, commands that needed help) to the plan file` to `prepend stats
(status, elapsed time, estimated tokens, commands that needed help) to the plan file`. Change
nothing else.

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `grep -rn "Run summary\|run summary" lib spec README.md docs/GLOSSARY.md` prints nothing.
3. `grep -n "Summary for the user" lib/planner/prompts/explore.md.erb lib/planner/prompts/review.md.erb`
   still prints one heading in each file.
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
docs/TODO.md
docs/plans/202610301139-run-stats/ITERATION-001.md
docs/plans/202610301139-run-stats/PLAN-001.md
```

Write the message with the `commit-message` skill. Suggested message:

```
Rename the run summary to stats

"Summary" meant both the agent's reply to the user and the block of
model, token and command-failure details written into plan and
findings files. Call the second one stats, with a `## Stats`
heading, and define both terms in the glossary.

Also add a TODO about ignoring gitignored files when staging.
```

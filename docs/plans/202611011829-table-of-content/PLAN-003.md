# PLAN-003 — Rename the table of contents file to `TABLE-OF-CONTENT.md`

Rename the table of contents file from `TABLE_OF_CONTENT.md` to `TABLE-OF-CONTENT.md` so it
matches the hyphenated names of the other files in a plan folder (`ITERATION-001.md`,
`PLAN-001.md`). Only the file name changes: the `FILE` constant, the two prompt templates that
spell the name out, the specs, the README and the glossary. Ruby and ERB identifiers, the
format, and earlier plan files stay as they are. An existing `TABLE_OF_CONTENT.md` gets no
special handling.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| New file name | `TABLE-OF-CONTENT.md` (from the brief) |
| An existing `TABLE_OF_CONTENT.md` in a folder | No handling. It is not renamed or excluded, so it would be listed in the `Other` group like any other file |
| Ruby/ERB names | Unchanged: `Planner::TableOfContent`, `lib/planner/table_of_content.rb`, `_table_of_content.md.erb`, `toc_file`, `table_of_content`. Only the file name string changes |
| Earlier `ITERATION-*.md` / `PLAN-*.md` files that mention the old name | Leave them as they are |
| README and glossary | Update the file name only, nothing else. README via the `update-readme` skill |

## Files to create / change

```
lib/planner/table_of_content.rb               FILE constant and class comment
lib/planner/prompts/_table_of_content.md.erb  excluded file name
lib/planner/prompts/toc.md.erb                excluded file name
spec/planner/table_of_content_spec.rb         expected paths
spec/planner/commands/toc_spec.rb             expected paths
spec/planner/commands/plan_spec.rb            expected path
spec/planner/commands/explore_spec.rb         expected paths
spec/planner/commands/review_spec.rb          expected paths
spec/planner/commands/run_spec.rb             expected paths
spec/planner/agents/claude_spec.rb            toc_file arguments and expected tool lists
README.md                                     `planner toc` bullet
docs/GLOSSARY.md                              **table of contents** entry
```

## Implementation

In every file listed above, replace each `TABLE_OF_CONTENT.md` with `TABLE-OF-CONTENT.md`.
Change nothing else in them. The new name is the same length, so no line needs rewrapping.

That covers:

- `lib/planner/table_of_content.rb`: the comment becomes
  `# The TABLE-OF-CONTENT.md a plan folder can have, and the prompt section describing it.`
  and the constant becomes `FILE = 'TABLE-OF-CONTENT.md'`.
- `lib/planner/prompts/_table_of_content.md.erb`: the exclusion bullet line becomes
  ``  `TABLE-OF-CONTENT.md` and names starting with `.`.``
- `lib/planner/prompts/toc.md.erb`: the line becomes
  ``the folder except `TABLE-OF-CONTENT.md`. If``
- The specs: every expected path and `toc_file:` argument (`table_of_content_spec.rb` lines
  5, 14, 20; `toc_spec.rb` 42, 46, 58, 60; `plan_spec.rb` 57; `explore_spec.rb` 53, 98, 99;
  `review_spec.rb` 33, 133; `run_spec.rb` 122, 123; `claude_spec.rb` 26, 29, 39, 42, 51, 54).
- `README.md`: in the `planner toc` bullet, `` `TABLE_OF_CONTENT.md` `` becomes
  `` `TABLE-OF-CONTENT.md` ``. Use the `update-readme` skill.
- `docs/GLOSSARY.md`: in the **table of contents** entry, `` `TABLE_OF_CONTENT.md` `` becomes
  `` `TABLE-OF-CONTENT.md` ``.

Do not edit anything under `docs/plans/`.

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `grep -rn TABLE_OF_CONTENT lib spec README.md docs/GLOSSARY.md` prints nothing.
3. `grep -rln TABLE-OF-CONTENT lib spec README.md docs/GLOSSARY.md` lists exactly the twelve
   files above.
4. `bundle exec ruby -Ilib -e 'require "planner"; puts Planner::TableOfContent.path("docs/plans/x")'`
   prints `docs/plans/x/TABLE-OF-CONTENT.md`.
5. `git status` shows changes only to the twelve files above, plus this folder's
   `ITERATION-003.md` and `PLAN-003.md`.

## Commit

Commit only after every change above is made and every Verification step passes. Do not
commit before.

Stage:

```
lib/planner/table_of_content.rb
lib/planner/prompts/_table_of_content.md.erb
lib/planner/prompts/toc.md.erb
spec/planner/table_of_content_spec.rb
spec/planner/commands/toc_spec.rb
spec/planner/commands/plan_spec.rb
spec/planner/commands/explore_spec.rb
spec/planner/commands/review_spec.rb
spec/planner/commands/run_spec.rb
spec/planner/agents/claude_spec.rb
README.md
docs/GLOSSARY.md
docs/plans/202611011829-table-of-content/ITERATION-003.md
docs/plans/202611011829-table-of-content/PLAN-003.md
```

If `docs/plans/202611011829-table-of-content/TABLE-OF-CONTENT.md` exists by then, stage it
too.

Write the message with the `commit-message` skill. Suggested message:

```
Rename the table of contents to TABLE-OF-CONTENT.md

Every other file in a plan folder uses hyphens (ITERATION-001.md,
PLAN-001.md), so TABLE_OF_CONTENT.md stood out. Only the file name
changes; the format and the code that writes it stay the same.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-02T12:23:32Z |
| Finished | 2026-11-02T12:23:43Z |
| Elapsed | 11s |
| Model | sonnet |
| Tokens | ~40k (estimate) |

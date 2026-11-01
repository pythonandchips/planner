# PLAN-002 — Group the table of contents by number

Change the `TABLE_OF_CONTENT.md` format so `## Files` is grouped by number instead of being
one flat list. Each number gets a plain `NNN - <summary>` line describing that number's work,
followed by a linked bullet per entry. Any file or folder whose name ends in `-NNN` joins its
number's group, and anything without a number goes in a final `Other` group. The format lives
in the shared partial `lib/planner/prompts/_table_of_content.md.erb`, so `planner toc` and the
update step in `plan`, `explore`, `review` and `run` all pick it up from that one file. The
spec, README and glossary are updated to match. No Ruby code, tool list or other prompt
changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Group header | Plain line `NNN - <summary>` (not a heading, not bold), links on the lines straight below, blank line between groups |
| File lines in a group | Link only: `- [<file>](<file>)`. No per-file summary |
| Plan status | Stays on the PLAN line: `- [PLAN-NNN.md](PLAN-NNN.md) (<status>)`. Not on the group header |
| Group summary | One line on what that number's work asked for and where it got to, written from the group's `.md` files |
| Unknown numbered entries | Any file or folder, of any type, whose name carries the number joins that group |
| How the number is found | The name, before any extension, ends in `-NNN` or `-NNN-<letters>` (three digits) |
| Order within a group | ITERATION, FINDINGS, PLAN, REVIEW, then other entries alphabetically. Lettered entries straight after their base, in letter order (as in PLAN-001) |
| Entries with no number | A last group headed by the plain line `Other`, alphabetical, any file or folder. Left out when empty |
| Excluded entries | `TABLE_OF_CONTENT.md` and names starting with `.` |
| Folder links | `- [<folder>/](<folder>/)` |
| Finding folders | From Glob results only. No tool changes; an empty folder is missed |
| Reading folders | List them only. Never read inside a folder |
| Update rule (plan/explore/review/run) | Add or replace the link for each file written, in its group (adding the group if missing); rewrite the summary line of every group a link was added to; refresh every plan's status; rewrite the Summary; leave every other line as it is |
| An existing table of contents in the old flat format | Out of scope. No special handling |
| README and glossary | Update both to describe the grouped format. README via the `update-readme` skill |

## Files to create / change

```
lib/planner/prompts/_table_of_content.md.erb   new grouped format and update rules
spec/planner/table_of_content_spec.rb          expectations for the new wording
README.md                                      `planner toc` bullet wording
docs/GLOSSARY.md                               **table of contents** entry wording
```

## Implementation

### 1. `lib/planner/prompts/_table_of_content.md.erb`

Replace the whole file with exactly:

````
<% if update -%>
If `<%= toc_file %>` exists, update it when this
prompt says to. Read every `PLAN-*.md` in
`<%= folder %>/` for its status, then:

- add a link for each file you wrote, or replace its
  link if it is already listed, in its place in its
  number's group, adding the group if it is missing
- rewrite the summary line of every group you added
  a link to
- set every plan's status from its stats
- rewrite the Summary to cover the folder as the
  lines now describe it
- leave every other line as it is

If `<%= toc_file %>` does not exist, do not create it.

<% end -%>
The table of contents lists the files and folders in
`<%= folder %>/`, grouped by number, in exactly this
format:

```markdown
# Table of contents — <%= name %>

## Summary

<two to four plain-English sentences on what has been done in this folder and where it stands>

## Files

<NNN> - <what this number's work asked for and where it got to, in one line>
- [<file>](<file>)
- [PLAN-<NNN>.md](PLAN-<NNN>.md) (<status>)
- [<folder>/](<folder>/)

Other
- [<file or folder>](<file or folder>)
```

- List every file and folder in the folder except
  `TABLE_OF_CONTENT.md` and names starting with `.`.
  Find folders from the paths Glob returns, and do
  not read inside them.
- An entry has number `NNN` when its name, before any
  extension, ends in `-NNN` or `-NNN-<letters>`, where
  `NNN` is three digits.
- Give each number one group: a plain line
  `NNN - <summary>`, then one link per entry on the
  lines below it. Write the summary from the group's
  `.md` files. Put the groups in number order with a
  blank line between them.
- Within a group, put `ITERATION`, then `FINDINGS`,
  then `PLAN`, then `REVIEW`, then any other entries
  alphabetically. Put lettered entries such as
  `FINDINGS-001-a.md` straight after their base
  entry, in letter order (`a`, `b` ... `z`, `aa`).
- Put entries with no number in a last group headed
  by the plain line `Other`, alphabetically. Leave
  the group out when there are none.
- Link a folder as `[<folder>/](<folder>/)`.
- Only plan lines have a status. It is `Completed`
  when the plan's stats have a `| Status | Completed |`
  row, in the `## Stats` block at the end of the file
  or the older `## Run summary` block at the top.
  Otherwise it is `Not completed`.
````

`lib/planner/prompts/toc.md.erb` stays as it is: it already reads only the folder's `.md`
files, and the partial covers listing folders and other files.

### 2. `spec/planner/table_of_content_spec.rb`

- `'renders the format without update rules'`: replace the expected string
  `"except\n  `TABLE_OF_CONTENT.md`"` with `'grouped by number'`, `'`NNN - <summary>`'`,
  `'- [PLAN-<NNN>.md](PLAN-<NNN>.md) (<status>)'`, `'- [<folder>/](<folder>/)'` and
  `"by the plain line `Other`"`. Keep `'# Table of contents — x'`, `'| Status | Completed |'`
  and `'Not completed'`, and keep the `not_to include` line unchanged.
- `'renders the update rules before the format'`: also expect
  `'adding the group if it is missing'` and `'rewrite the summary line of every group'`.

If rubocop flags line length, wrap the `include(...)` arguments across lines without
changing the strings.

### 3. `README.md`

Use the `update-readme` skill. Replace the `planner toc` bullet with exactly:

```markdown
- `planner toc [--model <model>] <plan-folder>`: have the agent write `TABLE_OF_CONTENT.md` in a plan folder, replacing any existing one: a short summary of the work, then the files and folders grouped by number, each group with a one-line summary and, for plans, whether they are completed. Once it exists, `planner plan`, `explore`, `review` and `run` keep it up to date (default model `haiku`).
```

Change nothing else.

### 4. `docs/GLOSSARY.md`

Replace the **table of contents** entry with exactly:

```markdown
- **table of contents**: `TABLE_OF_CONTENT.md` in a plan folder. A short plain-English summary of the folder's work, then its files and folders grouped by number, each group with a one-line summary, and `Completed` or `Not completed` on each plan file. Entries without a number go in a final `Other` group. Written by `planner toc`, and updated by `planner plan`, `planner explore`, `planner review` and `planner run` when it exists.
```

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `bundle exec ruby -Ilib -e 'require "planner"; puts Planner::TableOfContent.section("docs/plans/x", update: true)'`
   prints the update rules followed by the grouped format, with `docs/plans/x` substituted,
   `# Table of contents — x` in the example, and no `<%` anywhere.
3. The same command with `update: false` prints the format only, starting with
   `The table of contents lists the files and folders in`.
4. `git status` shows changes only to the four files listed above, plus this folder's
   `ITERATION-002.md` and `PLAN-002.md`.

## Commit

Commit only after every change above is made and every Verification step passes. Do not
commit before.

Stage:

```
lib/planner/prompts/_table_of_content.md.erb
spec/planner/table_of_content_spec.rb
README.md
docs/GLOSSARY.md
docs/plans/202611011829-table-of-content/ITERATION-002.md
docs/plans/202611011829-table-of-content/PLAN-002.md
```

If `docs/plans/202611011829-table-of-content/TABLE_OF_CONTENT.md` exists by then, stage it
too.

Write the message with the `commit-message` skill. Suggested message:

```
Group the table of contents by number

A flat list of files hides that each number is one piece of work.
List the files and folders under a `NNN - <summary>` line per
number, with anything else numbered the same in that group and
unnumbered entries in a final Other group.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-01T20:58:36Z |
| Finished | 2026-11-01T20:59:05Z |
| Elapsed | 29s |
| Model | sonnet |
| Tokens | ~30k (estimate) |

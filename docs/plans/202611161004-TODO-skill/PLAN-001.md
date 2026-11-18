# PLAN-001 — Ship a writing-todos skill

Ship a fifth planner skill, `writing-todos`, under `lib/planner/skills/writing-todos/`. It
tells the agent how to add a todo item for work to be done later, and how to remove one once
the work is done. Items go in the global todo, `docs/TODO.md`, or in a plan todo, `TODO.md`
in a plan folder. Each item is a single bullet in plain English of at most three sentences,
and ends with a link to the iteration, findings, plan or review file it came from, when it
came from one. The skill is built with the `skill-creator` skill, using the same process as
`writing-erb`, ships in the gem and is installed with `planner skills install`. The README
Skills section gets a bullet for it and `docs/GLOSSARY.md` gets entries for the two kinds of
todo. No Ruby code, prompt or spec changes, and the existing items in `docs/TODO.md` are left
as they are.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Skill name and location | `writing-todos`, at `lib/planner/skills/writing-todos/SKILL.md`, shipped in the gem. Not copied into this repo's `.claude/skills`. |
| Global todo file | `docs/TODO.md` (the file that already exists). |
| Plan todo file | `TODO.md` in the plan folder. |
| Which todo to write to | When the work is on a file in a plan folder, that folder's `TODO.md`; otherwise `docs/TODO.md`. If the user names one, use the one they name. |
| Source note | When an item came from an `ITERATION`, `FINDINGS`, `PLAN` or `REVIEW` file (including lettered ones such as `REVIEW-001-a.md`), end it with `From [<file name>](<path>).`, the path relative to the todo file. Items from anywhere else get no source note. |
| Scope of the skill | Adding items, and removing items once they are done. |
| When to remove an item | Delete the item's line once the agent has done that work in the session, or when the user says it is done. |
| File layout | If the todo file does not exist, create it with a `# TODO` heading and a blank line. Add each item as a `- ` bullet at the end of the list. |
| Plain English | Short everyday words, full sentences that end in a full stop, code names in backticks, no unexplained abbreviations. Say what needs doing and, when it is not obvious, why. |
| Length | At most three sentences per item, kept short. |
| Duplicates | Before adding, read the todo. If an item already covers the work, do not add another; tell the user. |
| Existing `docs/TODO.md` items | Left as they are. The skill applies only to items the agent writes or removes. |
| Build process | The skill-creator process the `writing-erb` plan used (docs/plans/202611051233-add-erb-writing-skill/PLAN-001.md): skill-creator draft, evals, pause for user review in the viewer, iterate, description optimisation, packaging. Workspace, evals, benchmark, viewer and `.skill` output go in `$TMPDIR`. Only `SKILL.md` is committed, as with the shipped `writing-erb`; the evals are not committed, because everything under `lib/planner/skills/` is packed into the gem and copied by `planner skills install`. Description on one line, single-quoted. Frontmatter has only `name` and `description`. |
| Eval scenarios | (1) plan todo from a review; (2) global todo with no source; (3) removing a done item; (4) a long, jargon-heavy request written as at most three plain sentences. |
| Planner prompts and code | No change. The table of contents already lists `TODO.md` in its `Other` group. |
| README | Add a `writing-todos` bullet to `## Skills`. Leave the leftover merge conflict lines at `README.md:20-24` as they are. |
| Glossary | Add `global todo` and `plan todo` entries to `docs/GLOSSARY.md`. |
| Commit | Yes |

## Files to create / change

```
lib/planner/skills/writing-todos/SKILL.md          new: the skill
README.md                                          new bullet in the Skills section
docs/GLOSSARY.md                                   two new entries
```

`SkillCatalog`, `planner skills list/install` and the gemspec already pick up a new skill
folder. `spec/planner/skill_catalog_spec.rb` already checks every shipped skill's `name`
matches its folder and its description is not blank. `spec/exe/planner_spec.rb` only checks
the first line of `planner skills list`, so it needs no change.

## Implementation

### 1. Build the skill with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to create the skill
directly at `lib/planner/skills/writing-todos/`. Keep all workspace, evals, benchmark,
grading and viewer output under `$TMPDIR` (for example `$TMPDIR/writing-todos-workspace/`),
never in the repo.

`SKILL.md` must have this frontmatter, and only these keys:

```
---
name: writing-todos
description: <written and then optimised with skill-creator>
---
```

Write the description on a single line as a single-quoted YAML string, escaping any `'`
inside it as `''`, as `lib/planner/skills/writing-erb/SKILL.md` does. Do not use a YAML
block scalar (`|` or `>`).

The description must say the skill is for adding a todo item for later work, or removing one
that is done, in `docs/TODO.md` or a plan folder's `TODO.md`.

The body of `SKILL.md` must state every rule below and nothing that contradicts them. Keep
it concise.

- **Where.** There are two kinds of todo. The global todo is `docs/TODO.md`. A plan todo is
  `TODO.md` in a plan folder. When the work is on a file in a plan folder, write to that
  folder's `TODO.md`; otherwise write to `docs/TODO.md`. If the user names one, use that one.
- **Creating the file.** If the todo file does not exist, create it with a `# TODO` heading
  followed by a blank line.
- **Adding.** Read the todo first. If an item already covers the work, do not add another;
  tell the user which item covers it. Otherwise add the item as one `- ` bullet at the end of
  the list.
- **Plain English.** Use short everyday words and full sentences that end in a full stop.
  Put code names (files, commands, methods, flags) in backticks. Do not use abbreviations
  without explaining them. Say what needs doing and, when it is not obvious, why.
- **Length.** Keep the item short: at most three sentences.
- **Source.** When the item came from an `ITERATION`, `FINDINGS`, `PLAN` or `REVIEW` file
  (including lettered ones such as `REVIEW-001-a.md`), end it with
  `From [<file name>](<path>).`, where the path is relative to the todo file. In a plan todo
  that is just the file name; in the global todo it is `plans/<plan folder>/<file name>` for
  a plan folder under `docs/plans/`. Items from anywhere else get no source note.
- **Removing.** When you have done the work an item describes in this session, or the user
  says it is done, delete the item's line. Do not change other items.
- The rules apply only to items you add or remove. Do not reword, reorder or reformat items
  already in the file.

Include one example of a plan todo and one of the global todo, each a short fenced
`markdown` block showing a `# TODO` heading and one or two items, at least one with a source
link. Use this pair as written:

Plan todo (`docs/plans/202611161004-TODO-skill/TODO.md`):

```markdown
# TODO

- Show the todo count in `planner toc` output. People miss open items when they only read the summary. From [REVIEW-001.md](REVIEW-001.md).
```

Global todo (`docs/TODO.md`):

```markdown
# TODO

- Check that `planner run` is given a `PLAN-*.md` file before it starts. From [FINDINGS-001.md](plans/202611141235-longer-unintended-explore-sessions/FINDINGS-001.md).
- Print usage and exit cleanly when `--help` is passed.
```

End with a short "Before you finish" step: check each item you added is in the right todo,
is plain English of at most three sentences, ends with a source link when it came from an
iteration, findings, plan or review file, and does not repeat an existing item; and check
you removed the items for work you finished.

Do not add any file other than `SKILL.md` to `lib/planner/skills/writing-todos/`.

### 2. Evals

Use skill-creator to write its default number of eval prompts into
`$TMPDIR/writing-todos-workspace/evals/evals.json`, not into the skill folder, run them, grade
them, and iterate on `SKILL.md` until skill-creator's results show the rules are followed.
Between them, the evals must cover:

1. **Plan todo from a review.** The agent is working on a `REVIEW-001.md` in a plan folder
   with no `TODO.md`, and the user defers one of its suggestions. Expected: the folder's
   `TODO.md` is created with `# TODO`, and the item ends `From [REVIEW-001.md](REVIEW-001.md).`
2. **Global todo, no source.** Outside any plan folder, the user asks to note a follow-up.
   Expected: the item is appended to the end of `docs/TODO.md`, at most three plain
   sentences, with no source note, and existing items are unchanged.
3. **Removing a done item.** The agent finishes work that matches an existing todo item.
   Expected: that item's line is deleted and the other items are unchanged.
4. **Long rambling request.** The user dictates a long, jargon-heavy follow-up. Expected: the
   item is at most three sentences, in plain English, saying what needs doing.

Give every file the evals need (existing todo contents, the review text) inline in the
prompt. Do not add input files.

After each run, start skill-creator's viewer and pause for the user to review the results
before you iterate. The sandbox blocks `open` and `osascript`, so the viewer will not open by
itself: give the user its URL (or generate it with `--static <path>` under `$TMPDIR` and give
them that path), and wait for them to say they have finished. Then read their feedback
directly by path, at `<workspace>/iteration-<N>/feedback.json`; do not search for it with
`find`. Do not use `timeout` in any command; it is not installed on macOS.

### 3. Description optimisation and packaging

Run skill-creator's description optimisation on the finished skill. If the optimiser or the
packager is blocked by the sandbox or a missing package, do not stop: give the user the
exact command (and, for a missing package, the install command such as
`python3 -m pip install pyyaml`), ask them to run it with `! <command>`, wait for them, and
carry on with its output. If a long one-line command does nothing when pasted, write it to a
short script in `$TMPDIR` and ask the user to run that. Record each one under "Commands that
needed help" in the stats. If it still cannot run after the user has tried, stop under run
rule 4.

The optimised description must still say the skill is for adding or removing todo items in
`docs/TODO.md` or a plan folder's `TODO.md`. If the optimiser's result drops that, edit the
description by hand to add it back, changing as little of the optimised text as possible.

Then use skill-creator to package the skill, writing the `.skill` file to `$TMPDIR`. Do not
put it in the repo.

### 4. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. In `## Skills`, add
after the `writing-rspec-controller-specs` bullet (the list follows `planner skills list`
order):

```
- `writing-todos`: <one line in plain English, written from the finished skill: the agent adds todo items for later work to `docs/TODO.md` or a plan folder's `TODO.md` in at most three plain sentences, citing the file they came from, and removes them when done>
```

`README.md:20-24` hold a leftover merge conflict marker (`||||||| parent of 583842a ...`) and
two versions each of the `planner review` and `planner explore` bullets. Leave those lines as
they are; they are out of scope for this plan. The only change to `README.md` is the new
bullet.

### 5. `docs/GLOSSARY.md`

Add these two entries straight after the `**table of contents**` entry:

```
- **global todo**: `docs/TODO.md`. Work to do later that is not tied to one plan folder. Written with the `writing-todos` skill.
- **plan todo**: `TODO.md` in a plan folder. Work to do later that came up in that plan folder, each item linking to the iteration, findings, plan or review file it came from. Written with the `writing-todos` skill.
```

## Verification

1. `bundle exec rake` passes: all specs (including "every shipped skill names itself and
   has a description" and "lists the shipped skills"), plus RuboCop with no offences.
2. `bundle exec exe/planner skills list` prints five lines, for `commit-message`,
   `writing-erb`, `writing-rspec`, `writing-rspec-controller-specs` and `writing-todos` in
   that order, with descriptions lined up in one column, and exits 0.
3. Read `lib/planner/skills/writing-todos/SKILL.md` and confirm:
   - it states every rule in Implementation step 1, and mentions no other skill
   - it has the plan todo and global todo examples from Implementation step 1
   - its frontmatter has only `name` and `description`
   - the description is on a single line as a single-quoted string, and mentions adding or
     removing todo items in `docs/TODO.md` or a plan folder's `TODO.md`
4. Read `$TMPDIR/writing-todos-workspace/evals/evals.json` and confirm it covers the four
   scenarios in Implementation step 2, with files inline in the prompts and no input files.
5. `git status` shows no skill-creator workspace, evals, benchmark, viewer or `.skill` files
   in the repo, and `lib/planner/skills/writing-todos/` contains only `SKILL.md`.
6. `git diff --stat` shows changes only to `lib/planner/skills/writing-todos/`, `README.md`
   and `docs/GLOSSARY.md`. `docs/TODO.md` is unchanged.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Only after every step above is implemented and every verification step passes, stage
exactly these files:

```
lib/planner/skills/writing-todos/SKILL.md
README.md
docs/GLOSSARY.md
docs/plans/202611161004-TODO-skill/ITERATION-001.md
docs/plans/202611161004-TODO-skill/PLAN-001.md
```

Run each git command as its own Bash call: one `git add` per call, with no `&&`, pipes or
`-C`. Write the commit message to a file in `$TMPDIR` and commit with
`git commit -F <file>`. Follow the `commit-message` skill: end the message with an
`Assisted-by:` trailer naming your own agent and model, and do not add a `Co-Authored-By:`
trailer.

Suggested commit message:

```
Add a writing-todos skill

The skill tells the agent how to note work for later. Items go in
docs/TODO.md, or in TODO.md in the plan folder when the work is on a
plan, as one bullet of at most three plain English sentences. An item
from an iteration, findings, plan or review file links to it, and the
agent deletes an item once the work is done. The README and glossary
describe the global todo and the plan todo.

Assisted-by: <agent> (<model>)
```

Do not commit before the change has been made and verified.

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-16T11:56:17Z |
| Finished | 2026-11-18T12:41:37Z |
| Elapsed | 2d 0h 45m 20s (includes waiting for the user's review) |
| Model | sonnet |
| Tokens | ~450k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `Read /tmp/claude-501/writing-todos-workspace/iteration-1/feedback.json` | Denied: the path is outside the working directories. The user copied the file into the plan folder instead. | Allow Read for `$TMPDIR`, or have the plan say where the viewer's feedback should be copied. |
| `python3 -m scripts.run_loop ...` (description optimiser) | Failed in the sandbox with `PermissionError: [Errno 1] Operation not permitted` from `os.sysconf("SC_SEM_NSEMS_MAX")`. The user ran it via `! /tmp/claude-501/writing-todos-workspace/run-optimise.sh`. | Run the optimiser outside the sandbox, or allow it to read the semaphore limit. |

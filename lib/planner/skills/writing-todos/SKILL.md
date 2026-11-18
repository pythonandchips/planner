---
name: writing-todos
description: 'Rules for adding a todo item for work to be done later, or removing one once the work is done, in the global todo `docs/TODO.md` or a plan folder''s `TODO.md`. Use this skill whenever the user asks you to note, defer, park or follow up on something later, or when you finish work that a todo item describes: write each item as one plain English bullet of at most three sentences, link the iteration, findings, plan or review file it came from, and delete the item when the work is done.'
---

# Writing todos

Follow these rules whenever you add a todo item for work to be done later, or remove one
because the work is done. They apply only to the items you add or remove. Do not reword,
reorder or reformat items already in the file.

## Where

There are two kinds of todo. The global todo is `docs/TODO.md`. A plan todo is `TODO.md` in a
plan folder.

When the work is on a file in a plan folder, write to that folder's `TODO.md`. Otherwise write
to `docs/TODO.md`. If the user names one, use that one.

If the todo file does not exist, create it with a `# TODO` heading followed by a blank line.

## Adding an item

Read the todo first. If an item already covers the work, do not add another. Tell the user
which item covers it.

Otherwise add the item as one `- ` bullet at the end of the list.

- Use plain English: short everyday words and full sentences that end in a full stop.
- Put code names (files, commands, methods, flags) in backticks.
- Do not use abbreviations without explaining them.
- Say what needs doing and, when it is not obvious, why.
- Keep the item short: at most three sentences. Whoever reads the todo later has none of
  today's context, so cut the story and keep the task.

## Source

When the item came from an `ITERATION`, `FINDINGS`, `PLAN` or `REVIEW` file (including
lettered ones such as `REVIEW-001-a.md`), end it with `From [<file name>](<path>).`, where the
path is relative to the todo file. In a plan todo that is just the file name. In the global
todo it is `plans/<plan folder>/<file name>` for a plan folder under `docs/plans/`.

Items from anywhere else get no source note.

## Removing an item

When you have done the work an item describes in this session, or the user says it is done,
delete the item's line. Do not change other items.

## Examples

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

## Before you finish

- Each item you added is in the right todo.
- Each item is plain English of at most three sentences.
- Each item that came from an iteration, findings, plan or review file ends with a source link.
- No item repeats an existing item.
- You removed the items for work you finished.

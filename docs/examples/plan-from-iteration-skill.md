---
name: plan-from-iteration
description: Turn an ITERATION-<N>.md requirements file under docs/plans/<folder>/ into a PLAN-<N>.md implementation plan in the same folder. Use whenever the user points at an ITERATION file, asks to "plan out" a change described in docs/plans, or asks to turn requirements into a plan. Resolves every open question with the user before writing a single line of the plan.
---

# Plan From Iteration

Turns a requirements doc (`ITERATION-<N>.md`) into an implementation plan
(`PLAN-<N>.md`), both living in the same `docs/plans/<folder>/` subfolder.

## Steps

1. **Identify the iteration file.** If it's ambiguous which folder or number the user
   means, ask.
2. **Read the whole folder, not just the one file.** Read the target `ITERATION-<N>.md`,
   plus every other `ITERATION-*.md` and `PLAN-*.md` already in that folder. Earlier
   plans record decisions that still apply — treat them as established context, not
   something to re-ask about.
3. **Resolve every open question before writing anything.** Do not assume a requirement,
   guess at a default, or fill a gap silently. Read the iteration file and list every
   decision point it leaves open, then ask the user about all of them together. Keep
   iterating — ask follow-ups, refine, ask again — until nothing is left ambiguous. Only
   once every question has an explicit answer do you move on to drafting the plan.
4. **Write `PLAN-<N>.md`** in the same folder, where `<N>` matches the source file's
   number, zero-padded to 3 digits (`ITERATION-3.md` or `ITERATION-003.md` → `PLAN-003.md`).
   Follow the structure below. Keep it concise and unambiguous — a developer should be
   able to execute it without needing to ask a follow-up question.
5. **End the plan with a Commit section.** State exactly what to stage and give a
   suggested commit message, with the instruction that the commit happens only after the
   plan's change has actually been made (implemented and verified) — never before.

## Plan structure

Match the convention already used by `PLAN-*.md` files elsewhere in `docs/plans/`:

```markdown
# PLAN-<N> — <short title>

<One paragraph: what this change is and its scope.>

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| <each question you resolved with the user, one row per decision> | <the answer> |

## Files to create / change

<concrete file list or diff-shaped description>

## Implementation

<the plan itself, in as much concrete detail as the decisions support>

## Verification

<how to confirm the change works — tests to run, commands to execute>

## Commit

<what to stage and a suggested commit message, contingent on verification passing>
```

The "Decisions" table is the record of every question you asked and how the user
answered it — it's what lets a future iteration in the same folder skip re-asking
things that are already settled.

## Notes

- Never make a decision on the user's behalf, even a small one — surface it as a
  question instead. This is the one rule the whole skill exists to enforce.
- Check sibling files in the folder for precedent before asking a question that was
  already answered there.

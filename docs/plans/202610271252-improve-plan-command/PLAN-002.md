# PLAN-002 — Call the iteration file a "brief", not a requirements doc

The plan prompt and the glossary describe an iteration file as a requirements doc. It isn't
one. It's a loose brief, and drawing the requirements out of it is part of planning. This
change renames it to "brief" in two places: the prompt template
`lib/planner/prompts/plan.md.erb` (the opening line and step 2) and the iteration file entry in
`docs/GLOSSARY.md`. The term "iteration file" and the `ITERATION-<N>.md` file name don't change.
No code, spec or README changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| New name for what an iteration file contains | "brief" |
| Term "iteration file" / `ITERATION-<N>.md` name | Unchanged |
| Prompt scope | Reword only: replace "requirements doc" in the opening line, and say "the brief" in step 2. No extra paragraph about drawing out requirements, because step 2 already covers it. |
| Glossary text | "The brief for one iteration of work." (name only, no mention of the plan phase) |
| Specs | No change. The existing `plan_spec` content checks are enough. |
| README | No change. It doesn't describe the iteration file's contents. |
| `~/.claude/skills/plan-from-iteration` (installed copy) | Untouched (as in PLAN-001) |
| Commit ordering | Commit PLAN-001 first (per its Commit section). PLAN-002 commits only its own changes. |

## Files to create / change

```
lib/planner/prompts/plan.md.erb   opening line and step 2 wording
docs/GLOSSARY.md                  iteration file entry
```

## Implementation

Prerequisite: PLAN-001 has been implemented, verified and committed. Check that
`git status` doesn't list `lib/planner/prompts/` as untracked. If it does, stop and tell the user.

### `lib/planner/prompts/plan.md.erb`

Opening line. Replace:

```
Turn the requirements doc `<%= iteration_file %>` into an implementation plan
```

with:

```
Turn the brief `<%= iteration_file %>` into an implementation plan
```

The next line (`` `<%= plan_file %>`. Both live in the plan folder `<%= folder %>/`. ``) stays
as it is.

Step 2. Replace:

```
   guess at a default, or fill a gap silently. Read the iteration file and list every
```

with:

```
   guess at a default, or fill a gap silently. Read the brief and list every
```

Change nothing else in the template. The title `# Plan From Iteration` stays, and the spec
depends on it.

### `docs/GLOSSARY.md`

Replace:

```
- **iteration file**: `ITERATION-<NNN>.md`. The requirements prompt for one iteration of work.
```

with:

```
- **iteration file**: `ITERATION-<NNN>.md`. The brief for one iteration of work.
```

## Verification

1. `bundle exec rake` passes: all specs and RuboCop.
2. `grep -rn -i "requirements doc\|requirements prompt" lib docs/GLOSSARY.md` prints nothing.
3. Render the prompt and read the top of it:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, agent: a, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/ITERATION-002.md"])'`
   The opening reads "Turn the brief `…/ITERATION-002.md` into an implementation plan
   `…/PLAN-002.md`." Step 2 reads "Read the brief and list every decision point it leaves open".

## Commit

Commit only after you have made the changes above and every Verification step passes. Run each
git command as its own Bash call:

```
git add lib/planner/prompts/plan.md.erb docs/GLOSSARY.md docs/plans/202610271252-improve-plan-command/ITERATION-002.md docs/plans/202610271252-improve-plan-command/PLAN-002.md
```

Write the message to a file and commit with `git commit -F <file>`. Suggested message:

```
Call the iteration file a brief, not a requirements doc

An iteration file is a loose starting point, and planning is where
the requirements get drawn out of it. Reword the plan prompt and the
glossary to match.
```

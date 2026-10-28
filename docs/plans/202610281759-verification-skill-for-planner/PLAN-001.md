# PLAN-001 — Add a `verify-planner` skill

Add a repo-local skill, `.claude/skills/verify-planner/SKILL.md`, that stops plans for this
repo from putting steps that write outside the repo (such as `bundle exec rake install`) in
their Verification section, and has reviews flag such steps. The agent can't write outside
the repo, so those steps are always blocked. The skill is for planning and reviewing only,
not for `planner run`. It is picked up through its description alone: the shipped prompts
do not change. Also in scope: removing the matching bullet from `docs/TODO.md`.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the skill lives | Repo-local `.claude/skills/verify-planner/SKILL.md`, like `update-readme`. Not shipped in the gem (`lib/planner/skills` is untouched). |
| Skill name | `verify-planner` |
| Scope of the rule | Ban only: no Verification step may write outside the repo, with `rake install` as the named example. `bundle exec rake` is the stated check. |
| End-to-end checks of the `planner` executable | The skill says nothing about them |
| Which steps it applies to | Planning and reviewing. Not running. |
| How it is triggered | Its `description` alone. `lib/planner/prompts/plan.md.erb` and `review.md.erb` do not change. |
| Review behaviour | Flag a step that writes outside the repo as a problem (it will be blocked) and suggest removing it and relying on `bundle exec rake` |
| Skill wording | Exactly the text under Implementation |
| Docs | Remove the matching bullet from `docs/TODO.md`. README and glossary unchanged. |
| Sandbox writes to `.claude/skills/` | The implementer writes the file. The user loosens the sandbox before running the plan. |
| Verification | `bundle exec rake` passes, and the SKILL.md frontmatter has `name: verify-planner` and a non-empty `description` |

## Files to create / change

```
.claude/skills/verify-planner/SKILL.md   new: the skill
docs/TODO.md                             remove the verification-skill bullet
```

## Implementation

### `.claude/skills/verify-planner/SKILL.md`

Create the file with exactly this content (ending with a single newline):

```markdown
---
name: verify-planner
description: Rules for the Verification section of a planner PLAN-*.md. Use when writing or reviewing a plan in this repo. Verification steps must never write outside the repo, so never add `rake install`.
---

# Verify Planner

The agent cannot write outside this repo. Any Verification step that
does (for example `bundle exec rake install`) is blocked.

## Writing a plan

- Never add a Verification step that writes outside the repo. That
  includes `rake install` in any form.
- `bundle exec rake` is the check.

## Reviewing a plan

- Flag any Verification step that writes outside the repo as a problem
  in the review: it will be blocked.
- Suggest removing it and relying on `bundle exec rake`.
```

### `docs/TODO.md`

Delete this line and nothing else:

```
- add a verification skill for this repo to stop it tying to install the gem. It will not be allowed to do that.
```

## Verification

1. `bundle exec rake` passes (all specs, RuboCop with no offences).
2. `head -4 .claude/skills/verify-planner/SKILL.md` shows the frontmatter opening with `---`,
   then `name: verify-planner`, then a `description:` line with non-empty text, then `---`.
3. `grep -n 'verification skill' docs/TODO.md` finds nothing.

## Commit

Commit only after both changes are made and every Verification step passes. Run each git
command as its own Bash call:

```
git add .claude/skills/verify-planner/SKILL.md docs/TODO.md docs/plans/202610281759-verification-skill-for-planner/ITERATION-001.md docs/plans/202610281759-verification-skill-for-planner/PLAN-001.md
```

Stage only this folder's `ITERATION-001.md` and `PLAN-001.md`. Do not stage any `REVIEW-*.md`
file in the folder. Write the message to a file and commit:

```
git commit -F <file>
```

Suggested message:

```
Add verify-planner skill for plan verification steps

Plans for this repo kept adding `bundle exec rake install` to their
Verification section, which the agent is never allowed to run because
it writes outside the repo. The new repo-local skill tells the agent
not to add such steps when planning, and to flag them when reviewing.
```

## Run summary

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-29T14:05:42Z |
| Finished | 2026-10-29T14:17:12Z |
| Elapsed | 11m 30s |
| Model | sonnet |
| Tokens | ~300k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `python3 -m scripts.run_loop ...` (skill-creator) | Failed twice in the sandbox with `PermissionError: [Errno 1] Operation not permitted` when `ProcessPoolExecutor` checked system limits. The user then ran it outside the sandbox and it finished. | Allow the sandbox to use POSIX semaphores, or run the optimisation outside the sandbox. |
| `python3 -m scripts.package_skill ...` (skill-creator) | Failed with `ModuleNotFoundError: No module named 'yaml'`; the user ran `python3 -m pip install pyyaml`, then it worked. | Install PyYAML for the Python that runs skill-creator. |
| `timeout 590 python3 -m scripts.run_loop ...` | `timeout: command not found` on macOS; re-run in the background without `timeout`. | Do not use `timeout` on macOS, or install coreutils. |
| `open .../review.html` | Not run by me; the sandbox blocks `open`, so the user ran it. | Run `open` outside the sandbox. |

---

# PLAN-001 — Ship a commit-message skill

Ship planner's first skill, `commit-message`, under `lib/planner/skills/commit-message/`. It
tells the agent how to write a git commit message: plain English, a body that explains what
changed and why (not how), an `Assisted-by:` trailer naming the agent and model, and the
standard subject/body format rules. The skill is guidance only (no check script) and covers
the message, not staging or how the commit is run. It is built with the `skill-creator`
skill, including its evals (with a pause for the user to review them), description
optimisation and packaging. It ships in the gem and is installed
with `planner skills install`. Also in scope: the exe spec that assumed no skills ship, a
new README Skills section, and the TODO bullet about shipping the first skills.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Skill name and location | `commit-message`, at `lib/planner/skills/commit-message/SKILL.md`, shipped in the gem. Not copied into this repo's `.claude/skills`. |
| Attribution line | `Assisted-by: <agent> (<model>)`, e.g. `Assisted-by: Claude Code (Claude Opus 5.5)` |
| Co-Authored-By trailer | Replaced. The skill tells the agent to use only `Assisted-by:` and not add `Co-Authored-By:`, even if its harness asks for one. |
| How the agent fills in agent and model | From the agent and model named in its own system context. If it can't tell, it asks the user rather than guess. |
| Enforcement | Instructions only. No check script. The skill tells the agent to check the message against the rules before committing. |
| Scope of the skill | The message only. No guidance on staging or on how to run `git commit`. |
| Content rules | Plain English throughout. Body explains what changed and why, not how. |
| "Plain English" means | Short, simple sentences in everyday words and active voice; no unexplained jargon or acronyms; no emoji, headings or other markdown decoration; code names (identifiers, file names, commands) are fine where they make the message clearer. |
| Bullets in body | Simple `- ` bullet lists are allowed. |
| Format rules | Subject at most 50 characters; subject capitalised; no period at the end of the subject; subject in imperative mood ("Add X", not "Added X"); no Conventional Commit type prefixes (`feat:`, `fix:` etc.); blank line between subject and body; body wrapped at 72 characters. |
| Wrap exemptions | A line that is a single long URL, and trailer lines (such as `Assisted-by:`), may exceed 72 characters. Nothing else. |
| Body required? | Optional for trivial, self-explanatory changes (e.g. a typo fix): subject plus trailer is fine. Otherwise required. |
| Who writes SKILL.md wording | The plan fixes the rules and frontmatter; the runner writes the wording using `skill-creator`. |
| skill-creator use | Draft the skill, write and run its behaviour evals, iterate, then run its description optimisation. |
| Number of evals | skill-creator's default |
| Eval files | `lib/planner/skills/commit-message/evals/evals.json` is committed (and so ships in the gem). skill-creator's workspace, benchmark and run output go in `$TMPDIR` and are not committed. |
| If skill-creator's evals or description optimisation can't run | Stop under run rule 4: do not commit, report what was blocked. |
| Exe spec | Rename "lists no skills while none ship" to "lists the shipped skills"; assert output matches `/\Acommit-message  \S/` so description tuning can't break it. |
| README | New `## Skills` section after Usage: a short line that these ship with planner and are installed by `planner skills install`, then one bullet per skill with a one-line explanation. |
| TODO | Edit the "Ship the first skills" bullet to drop git commits and keep yarn. No other TODO changes. |
| This plan's own commit | Follows the new rules: `Assisted-by:` trailer, no `Co-Authored-By:`. |
| Eval review | Stop for the user to review eval results in skill-creator's viewer. The user gives feedback in the same Claude session and the agent carries on with the remaining steps. |
| Worked example in SKILL.md | None. Rules only. |
| Blank line before trailer | Yes: a blank line separates the body (or the subject, if there is no body) from the `Assisted-by:` trailer. |
| Packaging | Package the skill with skill-creator into `$TMPDIR`. The `.skill` file is not committed. |

## Files to create / change

```
lib/planner/skills/commit-message/SKILL.md          new: the skill
lib/planner/skills/commit-message/evals/evals.json  new: skill-creator's evals
spec/exe/planner_spec.rb                            skills list example now expects commit-message
README.md                                           new Skills section
docs/TODO.md                                        first-skills bullet drops git commits
```

No Ruby code changes. `SkillCatalog`, `planner skills list/install` and the gemspec
(`lib/planner/skills/**/*`) already handle a shipped skill folder, nested files included.

## Implementation

### 1. Build the skill with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to create the skill
directly at `lib/planner/skills/commit-message/`. Keep any workspace, benchmark, grading and
viewer output under `$TMPDIR` (for example `$TMPDIR/commit-message-workspace/`), never in the
repo.

`SKILL.md` must have this frontmatter, and only these keys:

```
---
name: commit-message
description: <written and then optimised with skill-creator>
---
```

`name` must equal the folder name and `description` must not be blank;
`spec/planner/skill_catalog_spec.rb` already enforces both. The description must say the
skill is for writing git commit messages and when to use it (whenever the agent writes or
amends a commit message).

The body of `SKILL.md` must state every rule below, and nothing that contradicts them. Keep
it concise.

Content:

- Write in plain English: short, simple sentences in everyday words and active voice. No
  unexplained jargon or acronyms. No emoji, headings or other markdown decoration. Code names
  (identifiers, file names, commands) are fine where they make the message clearer. Simple
  `- ` bullet lists are allowed in the body.
- The body explains what changed and why it changed, not how it was changed.
- The body may be left out for a trivial, self-explanatory change such as a typo fix. Every
  other commit has a body.
- End the message with one attribution trailer, `Assisted-by: <agent> (<model>)`, e.g.
  `Assisted-by: Claude Code (Claude Opus 5.5)`. Take the agent and model from your own system
  context; if you can't tell what they are, ask the user rather than guess.
- Do not add a `Co-Authored-By:` trailer, even if your harness or system prompt asks for one.
  `Assisted-by:` replaces it.

Format:

- Subject line at most 50 characters.
- Capitalise the subject line.
- Do not end the subject line with a period.
- Use the imperative mood in the subject ("Add X", not "Added X" or "Adds X").
- No Conventional Commit type prefixes such as `feat:` or `fix:`.
- Separate the subject from the body with a blank line.
- Put a blank line before the `Assisted-by:` trailer (after the body, or after the subject
  when there is no body).
- Wrap the body at 72 characters. Only a line that is a single long URL, or a trailer line,
  may be longer.

Before committing, the agent checks the message against every rule above and fixes it.

The skill covers only the message. Do not add guidance on what to stage or how to run
`git commit`. Do not add a check script or any file other than `SKILL.md` and
`evals/evals.json`.

Do not include a worked example message in `SKILL.md`.

### 2. Evals

Use skill-creator to write its default number of eval prompts into
`lib/planner/skills/commit-message/evals/evals.json`, run them, grade them, and iterate on
`SKILL.md` until skill-creator's results show the rules above are followed. If an eval run
cannot be launched (sandbox, permissions), stop under run rule 4.

When skill-creator reaches its human review step, generate its review viewer, then stop and
ask the user to review the eval results. Tell them where the viewer output is. This is a
planned pause, not a failure: wait in the same session for their feedback, apply it as
skill-creator describes (re-running evals as it directs), and pause for review again each
time skill-creator asks for it. Continue to step 3 only once the user says they are happy.
If the viewer can't be generated or opened, stop under run rule 4.

### 3. Description optimisation and packaging

Run skill-creator's description optimisation on the skill and put the resulting
description into the `SKILL.md` frontmatter. Keep its working files in `$TMPDIR`. If it
cannot run, stop under run rule 4.

Then use skill-creator to package the skill, writing the `.skill` file to `$TMPDIR`. Do not
put it in the repo.

### 4. `spec/exe/planner_spec.rb`

Replace the example:

```ruby
  it 'lists the shipped skills' do
    out, _err, status = planner('skills', 'list')

    expect(status.exitstatus).to eq(0)
    expect(out).to match(/\Acommit-message  \S/)
  end
```

### 5. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. Add after the Usage
section (after its `planner new` code block, before `## Development`):

```
## Skills

These ship with planner and are installed with `planner skills install`.

- `commit-message`: <one line in plain English: what it makes the agent do when writing a commit message>
```

Write the one-line explanation from the finished skill.

### 6. `docs/TODO.md`

Change:

```
- Ship the first skills under `lib/planner/skills` (for example writing git commits, running yarn commands).
```

to:

```
- Ship more skills under `lib/planner/skills` (for example running yarn commands).
```

## Verification

1. `bundle exec rake` passes: all specs (including the changed exe example and the existing
   "every shipped skill names itself and has a description" example), plus RuboCop with no
   offences.
2. `bundle exec exe/planner skills list` prints one line starting `commit-message  ` followed
   by the description, exit 0.
3. Read `lib/planner/skills/commit-message/SKILL.md` and confirm it states every Content and
   Format rule in Implementation step 1, has only `name` and `description` in its
   frontmatter, and contains no staging or `git commit` guidance.
4. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the repo, and
   `lib/planner/skills/commit-message/` contains only `SKILL.md` and `evals/evals.json`.

Do not run `planner skills install` or `bundle exec rake install`; they write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/commit-message spec/exe/planner_spec.rb README.md docs/TODO.md docs/plans/202610291133-git-commit-skill/ITERATION-001.md docs/plans/202610291133-git-commit-skill/PLAN-001.md
```

Write the message to a file and commit with `git commit -F <file>`. The message follows the
new skill's rules: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Ship a commit-message skill with planner

Add planner's first shipped skill. It tells the agent how to write a
commit message: plain English, a body that says what changed and why
rather than how, an Assisted-by trailer naming the agent and model,
and the usual subject and wrapping rules.

The README now lists the shipped skills, and the TODO no longer asks
for a git commit skill.

Assisted-by: <agent> (<model>)
```

# PLAN-001 — Tidy up the README

Rewrite parts of `README.md` so it is easier to read: the opening describes the explore, plan, review,
run workflow planner manages; Install starts with a `git clone` and loses the mise line; Usage becomes
one short subsection per command, cut to essentials; and a new Contributing section closes the file.
Skills and Development are unchanged. No code, spec or other doc changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Opening | One intro paragraph, then the four workflow steps as a numbered list, each naming its command |
| `planner new` in the workflow | Lead-in sentence before the list (`planner new` comes first); the Plan step names only `planner plan` |
| Clone step | HTTPS: `git clone https://github.com/pythonandchips/planner.git`, then `cd planner`, then the existing bundle line |
| mise | Remove the `mise reshim` line from the README only |
| Contributing placement | New `## Contributing` section after `## Development`, as the last section |
| Contributing content | Every PR includes an iteration file and a plan file created with planner, in their plan folder under `docs/plans/`; run `bundle exec rake` before opening it |
| Usage layout | `### planner <cmd>` per command: synopsis code block, one or two sentences, one bullet per option |
| Usage order | Workflow order (new, explore, plan, review, run), then summarise, toc, skills |
| Usage detail | Essentials only: what the command does and writes, plus options with defaults; drop behaviour detail (e.g. `--deep` internals, review's `**Applied:**` marking, toc's auto-update list) |
| `planner new` examples | Move into the `### planner new` subsection |
| "Run from the project root." | Stays at the top of Usage |
| Skills commands | One `### planner skills` subsection covering `list` and `install` |
| Skills and Development sections | Unchanged |
| Commit | Yes |

## Files to create / change

- `README.md`: replace the opening paragraph, the Install section and the Usage section; append a
  Contributing section.

## Implementation

Use the `update-readme` skill's rules (no marketing prose, glossary names). Edit `README.md` as below.
Text in the blocks is the exact text to write.

### Opening

Replace the line `Creates plan folders and hands iteration files and plan files to an agent.` with:

```markdown
planner manages a four-step workflow for working with a coding agent. Start with `planner new <name>`, which creates a plan folder with an empty `ITERATION-001.md`, and write the task's brief in it.

1. **Explore** (optional): an agent explores the codebase and gathers context for the task. `planner explore`
2. **Plan**: give the agent a specific task and shape the solution. `planner plan`
3. **Review** (optional): an agent reviews the plan and recommends improvements, optionally through a lens such as security or performance. `planner review`
4. **Run**: apply the plan to the codebase. `planner run`
```

### Install

Replace the section body (code block and the `mise reshim` line) with:

````markdown
```sh
git clone https://github.com/pythonandchips/planner.git
cd planner
bundle install && bundle exec rake install
```
````

### Usage

Replace everything between `## Usage` and `## Skills` (the intro line, the command bullets and the example
block) with:

````markdown
Run from the project root. A command that takes a file also takes a plan folder, and then uses the folder's latest file of the kinds it accepts.

### planner new

```sh
planner new [--dir <folder>] <given-name>
```

Creates a plan folder under `docs/plans/` with an empty `ITERATION-001.md` in it, and prints the file's path.

- `--dir <folder>`, `-d`: create the plan folder under this folder, relative to the project root.

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login/ITERATION-001.md
planner new --dir work/plans "Add login"  # => work/plans/202610271216-add-login/ITERATION-001.md
```

### planner explore

```sh
planner explore [--model <model>] [--deep] <iteration-file|plan-folder>
```

Has the agent answer an `ITERATION-<N>.md` brief by exploring the code or data in rounds, checking in with you after each, and write a read-only `FINDINGS-<N>.md` next to it.

- `--model <model>`: default `opus`.
- `--deep`, `-d`: once you have clarified the brief and replied `Make it so`, the agent works on its own, researching and building spikes, and lists the spikes' branches in the findings.

### planner plan

```sh
planner plan <iteration-file|plan-folder>
```

Has the agent write the `PLAN-<N>.md` for an `ITERATION-<N>.md` next to it. It asks you about anything left open, including whether the plan should end in a commit.

### planner review

```sh
planner review [--model <model>] [--lens <text>|-] <file|plan-folder>
```

Has the agent review a `PLAN-<N>.md` or `FINDINGS-<N>.md` against the code and write `REVIEW-<N>.md` next to it. Ask in the session and it applies its suggestions to the plan.

- `--model <model>`: default `opus`.
- `--lens <text>`: narrow the review, for example to security or performance; `--lens -` reads it from stdin.

### planner run

```sh
planner run [--model <model>] [--print] <plan-file|plan-folder>
```

Has the agent implement a `PLAN-<N>.md` exactly, fixing failing verification steps or stopping to explain, then append deviations and stats to the plan. It commits only when the plan says to.

- `--model <model>`: default `sonnet`.
- `--print`, `-p`: print the prompt, model and allowed tools as JSON instead, to run with your own `claude` command.

### planner summarise

```sh
planner summarise [--model <model>] [--brief <text>|-] <file|plan-folder>
```

Has the agent summarise a `PLAN-<N>.md`, `REVIEW-<N>.md` or `FINDINGS-<N>.md` in the format the brief asks for (markdown, a diagram, a slide deck ...). The summary comes back in the session, or is written to `SUMMARY-<N>.<ext>` next to the file when the brief asks for it on disk.

- `--model <model>`: default `opus`.
- `--brief <text>`: what to summarise and how; `--brief -` reads it from stdin. Without it you get a short markdown summary.

### planner toc

```sh
planner toc [--model <model>] <plan-folder>
```

Has the agent write `TABLE-OF-CONTENT.md` in a plan folder, replacing any existing one.

- `--model <model>`: default `haiku`.

### planner skills

```sh
planner skills list
planner skills install [--global] [--only <slug>,...]
```

`list` lists the skills planner ships. `install` copies them into `.claude/skills`, asking before replacing a skill that has changed.

- `--global`: install into `~/.claude/skills` instead.
- `--only <slug>,...`: install only these skills.
````

### Contributing

After the `## Development` section (leave it as is), append:

```markdown
## Contributing

- Every pull request must include an iteration file and a plan file created with planner, in their plan folder under `docs/plans/`.
- Run `bundle exec rake` before opening it.
```

## Verification

1. `grep -n mise README.md` prints nothing.
2. `grep -n '^## \|^### ' README.md` lists, in order: `## Install`, `## Usage`, `### planner new`,
   `### planner explore`, `### planner plan`, `### planner review`, `### planner run`,
   `### planner summarise`, `### planner toc`, `### planner skills`, `## Skills`, `## Development`,
   `## Contributing`.
3. Each synopsis's options, short flags and default models match the option parsing in
   `lib/planner/commands/`; fix the README if one differs.
4. `bundle exec rake` (specs, then RuboCop) passes.

Do not add `rake install` or any step that writes outside the repo.

## Commit

Commit only after the change has been implemented and every Verification step passes. Never commit before.

Stage exactly:

- `README.md`
- `docs/plans/202611191027-improve-readme/` (`ITERATION-001.md` and `PLAN-001.md`)

Suggested commit message (write it with the `commit-message` skill, which sets the trailer):

```
Tidy up the README

The README had grown hard to read: the opening did not say what planner
is for, and each command was described in one long bullet.

It now opens with the explore, plan, review, run workflow, starts Install
with a git clone, gives each command a short subsection with its options,
and ends with contribution guidelines requiring an iteration and a plan
made with planner in every pull request.
```

## Deviations

- The README's options lacked the short flags the code defines (`-m`, `-l`, `-b`), which Verification step 3 requires; changed `README.md` to add `-m` to every `--model` bullet, `-l` to `--lens` and `-b` to `--brief`.

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-19T10:49:43Z |
| Finished | 2026-11-19T10:50:18Z |
| Elapsed | 35s |
| Model | sonnet |
| Tokens | ~40k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sed -i 's/.../' README.md` | Failed on macOS BSD sed, which needs a backup suffix argument; re-run as `sed -i ''` | Use `sed -i ''` on macOS, or the Edit tool |
